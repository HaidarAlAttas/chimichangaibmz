"""
Stage 3 - Vitals model.

Target (per architecture): PyTorch 1D-CNN with 2 heads (HR, RR), exported to
ONNX; zDLC on the Telum AIU is a stretch goal - plain CPU inference is the
fallback. Model input must match docs/MODEL_INPUT_SPEC.md exactly (review #6). Until the trained model is dropped in,
`SpectralBaseline` gives working numbers from classic signal processing so the
whole request path runs end to end. Swap implementations in `load_model()`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Protocol

import numpy as np

from . import dsp


@dataclass
class VitalsEstimate:
    heart_rate_bpm: float
    respiratory_rate_bpm: float
    method: str


class VitalsModel(Protocol):
    def predict(self, d: dsp.DspOutput) -> VitalsEstimate: ...


class SpectralBaseline:
    """HR from the BVP spectral peak (cardiac band 0.7-4 Hz); RR from a
    separate respiratory band (0.1-0.5 Hz) of the green channel - review #5.
    RR is experimental. SpO2 is deliberately not estimated - review #1.
    """

    method = "baseline-spectral"

    def predict(self, d: dsp.DspOutput) -> VitalsEstimate:
        hr = d.peak_hz * 60.0

        f, p = dsp.spectrum(d.resp, d.fs)
        band = (f >= 0.1) & (f <= 0.5)
        rr = float(f[band][np.argmax(p[band])] * 60.0) if band.any() else 16.0

        return VitalsEstimate(round(hr, 1), round(rr, 1), self.method)


def load_model() -> VitalsModel:
    """TODO(stage 3): when the trained network is exported, load it here, e.g.
    the zDLC-compiled .so or an onnxruntime session from VITALS_MODEL_PATH, and
    return an object with the same `predict(DspOutput) -> VitalsEstimate`."""
    if os.environ.get("VITALS_MODEL_PATH"):
        raise NotImplementedError("Trained vitals model loader not implemented yet")
    return SpectralBaseline()
