"""
Stage 2 - Signal DSP.

RGB traces from the phone -> clean blood-volume-pulse (BVP) signal + SQI.

  1. resample to a uniform grid (phones drop frames)
  2. POS projection (Wang et al., 2017, "Algorithmic principles of remote PPG")
  3. detrend + Butterworth band-pass 0.7-4 Hz (42-240 bpm)
  4. separate respiratory path: green channel, band-pass 0.1-0.5 Hz
  5. SQI = share of in-band power that sits at the pulse peak and its harmonic
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import signal

FS = 30.0                 # analysis sampling rate (Hz)
HR_BAND = (0.7, 4.0)      # Hz, cardiac path
RESP_BAND = (0.1, 0.5)    # Hz, respiratory path (kept separate - review #5)
MODEL_LEN = 900           # 30 s x 30 Hz
POS_WINDOW_S = 1.6


@dataclass
class DspOutput:
    fs: float
    rgb: np.ndarray          # (3, n) uniformly resampled raw RGB
    bvp: np.ndarray          # (n,) band-passed POS pulse signal
    resp: np.ndarray         # (n,) respiratory path: green, 0.1-0.5 Hz
    sqi: float               # 0..1
    peak_hz: float           # dominant pulse frequency


def resample(t_ms, r, g, b, fs: float = FS) -> np.ndarray:
    t = (np.asarray(t_ms, dtype=float) - t_ms[0]) / 1000.0
    grid = np.arange(0.0, t[-1], 1.0 / fs)
    return np.vstack([np.interp(grid, t, np.asarray(c, dtype=float)) for c in (r, g, b)])


def pos(rgb: np.ndarray, fs: float = FS) -> np.ndarray:
    n = rgb.shape[1]
    w = max(2, int(round(POS_WINDOW_S * fs)))
    proj = np.array([[0.0, 1.0, -1.0], [-2.0, 1.0, 1.0]])
    h = np.zeros(n)
    for start in range(0, n - w + 1):
        seg = rgb[:, start:start + w]
        mean = seg.mean(axis=1, keepdims=True)
        if np.any(mean <= 1e-9):
            continue
        s = proj @ (seg / mean)
        std1 = s[1].std()
        alpha = s[0].std() / std1 if std1 > 1e-12 else 0.0
        p = s[0] + alpha * s[1]
        h[start:start + w] += p - p.mean()
    return h


def bandpass(x: np.ndarray, lo: float, hi: float, fs: float = FS, order: int = 3) -> np.ndarray:
    b, a = signal.butter(order, [lo / (fs / 2), hi / (fs / 2)], btype="band")
    padlen = min(len(x) - 1, 3 * max(len(a), len(b)))
    return signal.filtfilt(b, a, x, padlen=padlen)


def spectrum(x: np.ndarray, fs: float = FS):
    nfft = max(4096, 1 << int(np.ceil(np.log2(len(x)))))
    f, p = signal.periodogram(x * np.hanning(len(x)), fs=fs, nfft=nfft)
    return f, p


def quality_index(x: np.ndarray, fs: float = FS) -> tuple[float, float]:
    """(sqi 0..1, peak_hz). de Haan-style SNR mapped to 0..1."""
    f, p = spectrum(x, fs)
    band = (f >= HR_BAND[0]) & (f <= HR_BAND[1])
    if not band.any() or p[band].sum() <= 0:
        return 0.0, 0.0
    peak = f[band][np.argmax(p[band])]
    near = band & ((np.abs(f - peak) <= 0.12) | (np.abs(f - 2 * peak) <= 0.12))
    ratio = p[near].sum() / p[band].sum()
    # A clean pulse puts ~60-90 % of in-band power at the peak + harmonic;
    # white noise puts ~10 %. Map 0.15 -> 0 and 0.65 -> 1.
    sqi = float(np.clip((ratio - 0.15) / 0.5, 0.0, 1.0))
    return sqi, float(peak)


def run(t_ms, r, g, b, fs: float = FS) -> DspOutput:
    rgb = resample(t_ms, r, g, b, fs)
    bvp = bandpass(signal.detrend(pos(rgb, fs)), *HR_BAND, fs=fs)
    # Breathing modulates overall skin brightness, which POS cancels on
    # purpose, so the respiratory path uses the normalised green channel.
    resp = bandpass(signal.detrend(rgb[1] / rgb[1].mean()), *RESP_BAND, fs=fs, order=2)
    sqi, peak = quality_index(bvp, fs)
    return DspOutput(fs=fs, rgb=rgb, bvp=bvp, resp=resp, sqi=sqi, peak_hz=peak)


def model_input(d: DspOutput) -> np.ndarray:
    """Vitals-model tensor float32[1, 2, MODEL_LEN] - docs/MODEL_INPUT_SPEC.md.
    Training MUST build its inputs with this function."""
    def fit(x: np.ndarray) -> np.ndarray:
        x = (x - x.mean()) / (x.std() + 1e-6)
        x = x[-MODEL_LEN:]
        return np.pad(x, (0, MODEL_LEN - len(x)))
    return np.stack([fit(d.bvp), fit(d.resp)])[None].astype(np.float32)
