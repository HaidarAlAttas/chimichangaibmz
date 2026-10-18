import json, os, shutil, struct, subprocess, zlib
from pathlib import Path
import numpy as np, pandas as pd, torch, torch.nn as nn

FPS, WIN_S, STRIDE_S = 30, 10, 5
L = WIN_S * FPS
# face box (training side): centred square, side = BOX_SIDE x frame height
BOX_SIDE, BOX_CX, BOX_CY = 0.30, 0.54, 0.47
ROIS = [(0.25, 0.75, 0.05, 0.22), (0.12, 0.38, 0.50, 0.75),
        (0.62, 0.88, 0.50, 0.75), (0.20, 0.80, 0.20, 0.80)]   # forehead, L cheek, R cheek, centre (fractions of the box)

# ---------- signal helpers ----------
def read_table(path):
    df = pd.read_csv(path, sep=r"[,\s;]+", engine="python", header=None, comment="#")
    return df.apply(pd.to_numeric, errors="coerce").dropna(how="all").dropna(axis=1, how="all")

def load_ppg(path, col=None):
    df = read_table(path)
    col = df.columns[-1] if col is None else col
    return df[col].astype(float).interpolate().bfill().ffill().to_numpy()

def resample(x, n_out):
    x = np.asarray(x, float)
    if x.ndim == 1: x = x[:, None]
    a, b = np.linspace(0, 1, len(x)), np.linspace(0, 1, n_out)
    return np.stack([np.interp(b, a, x[:, i]) for i in range(x.shape[1])], 1)

def bandpass(x, fs, lo, hi):
    x = np.asarray(x, float)
    F = np.fft.rfft(x - x.mean(axis=0), axis=0)
    f = np.fft.rfftfreq(x.shape[0], 1.0 / fs)
    F[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(F, n=x.shape[0], axis=0)

def hr_snr(x, fs=FPS, lo=0.7, hi=3.0, nfft=8192):
    """-> (heart rate bpm, spectral SNR dB) of a pulse waveform"""
    x = np.asarray(x, float); x = (x - x.mean()) * np.hanning(len(x))
    P = np.abs(np.fft.rfft(x, n=nfft)) ** 2; f = np.fft.rfftfreq(nfft, 1.0 / fs)
    band = (f >= lo) & (f <= hi); pk = f[band][np.argmax(P[band])]
    s = P[band & (np.abs(f - pk) <= 0.1)].sum(); n = P[band].sum() - s
    return 60.0 * pk, 10 * np.log10((s + 1e-12) / (n + 1e-12))

def pos_signal(rgb, fs, win_s=1.6):          # classic POS baseline, no training
    T, w = len(rgb), int(win_s * fs); H = np.zeros(T)
    for t in range(T - w + 1):
        C = rgb[t:t + w].T
        Cn = C / (C.mean(axis=1, keepdims=True) + 1e-9)
        S1 = Cn[1] - Cn[2]; S2 = -2 * Cn[0] + Cn[1] + Cn[2]
        h = S1 + (S1.std() / (S2.std() + 1e-9)) * S2
        H[t:t + w] += h - h.mean()
    return H

def align(sig, ppg, fs=FPS, max_lag=20):
    """shift/sign-fix the PPG label so it lines up with the face signal (+-20 frames)"""
    pos = bandpass(pos_signal(sig.reshape(-1, 4, 3).mean(1), fs), fs, 0.7, 3.0)
    p = bandpass(ppg, fs, 0.7, 3.0); best, bl = 0.0, 0
    for lag in range(-max_lag, max_lag + 1):
        a, b = (pos[lag:], p[:len(p) - lag]) if lag >= 0 else (pos[:lag], p[-lag:])
        n = min(len(a), len(b)); c = np.corrcoef(a[:n], b[:n])[0, 1]
        if np.isfinite(c) and abs(c) > abs(best): best, bl = c, lag
    s2, p2 = (sig[bl:], ppg[:len(ppg) - bl]) if bl >= 0 else (sig[:bl], ppg[-bl:])
    n = min(len(s2), len(p2))
    return s2[:n], (p2[:n] if best >= 0 else -p2[:n]), bl, best

# ---------- video reading through ffmpeg (no OpenCV) ----------
def _ff(name):
    d = Path(os.environ.get("PULSEPAL_FFMPEG", Path(__file__).resolve().parent.parent / "ffmpeg" / "bin"))
    p = d / name
    return str(p) if p.exists() else (shutil.which(name) or str(p))

def video_info(path):
    r = subprocess.run([_ff("ffprobe"), "-v", "error", "-select_streams", "v:0", "-of", "json",
                        "-show_entries", "stream=codec_name,width,height,avg_frame_rate,r_frame_rate",
                        str(path)], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        raise RuntimeError(f"ffprobe failed: {r.stderr.strip()[:200]}")
    s = json.loads(r.stdout)["streams"][0]
    def rate(t):
        a, b = (t.split("/") + ["1"])[:2]
        return float(a) / float(b) if float(b) else 0.0
    fps = rate(s.get("avg_frame_rate", "0/1")) or rate(s.get("r_frame_rate", "0/1")) or 30.0
    return dict(codec=s.get("codec_name"), width=int(s["width"]), height=int(s["height"]), fps=fps)

def iter_frames(path, out_w=480, max_s=None):
    """-> (generator of RGB uint8 frames (H,W,3) scaled to out_w wide, fps)"""
    info = video_info(path)
    W = out_w - out_w % 2; H = int(round(info["height"] * W / info["width"] / 2)) * 2
    cmd = [_ff("ffmpeg"), "-v", "error", "-nostdin"]
    if max_s: cmd += ["-t", str(max_s)]
    cmd += ["-i", str(path), "-an", "-sn", "-vf", f"scale={W}:{H}", "-fps_mode", "passthrough",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    def gen():
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL); n = W * H * 3
        try:
            while True:
                buf = p.stdout.read(n)
                if len(buf) < n: break
                yield np.frombuffer(buf, np.uint8).reshape(H, W, 3)
        finally:
            p.stdout.close()
            try: p.kill()
            except Exception: pass
            p.wait()
    return gen(), info["fps"]

# ---------- video -> 12 colour signals (training side only) ----------
def box_for(H, W):
    s = BOX_SIDE * H
    return W * BOX_CX - s / 2, H * BOX_CY - s / 2, s, s

def extract_signals(video_path, max_s=None):
    frames, fps = iter_frames(video_path, max_s=max_s); feats = []
    for fr in frames:
        H, W = fr.shape[:2]; x, y, w, h = box_for(H, W); row = []
        for x0, x1, y0, y1 in ROIS:
            ya, yb = int(y + y0 * h), max(int(y + y1 * h), int(y + y0 * h) + 1)
            xa, xb = int(x + x0 * w), max(int(x + x1 * w), int(x + x0 * w) + 1)
            row.extend(fr[ya:yb, xa:xb].reshape(-1, 3).mean(0))         # R, G, B per region
        feats.append(row)
    return np.array(feats, float), fps

def overlay(frame):
    """draw the face box (green) and the 4 regions (yellow) on a frame, to check the placement"""
    out = np.array(frame, np.uint8, copy=True); H, W = out.shape[:2]; x, y, w, h = box_for(H, W)
    def rect(xa, ya, xb, yb, col, t):
        xa, xb = int(max(0, xa)), int(min(W, xb)); ya, yb = int(max(0, ya)), int(min(H, yb))
        out[ya:ya + t, xa:xb] = col; out[yb - t:yb, xa:xb] = col
        out[ya:yb, xa:xa + t] = col; out[ya:yb, xb - t:xb] = col
    rect(x, y, x + w, y + h, (0, 255, 0), 2)
    for x0, x1, y0, y1 in ROIS: rect(x + x0 * w, y + y0 * h, x + x1 * w, y + y1 * h, (255, 255, 0), 1)
    return out

def save_png(arr, path):
    a = np.ascontiguousarray(arr, np.uint8); H, W = a.shape[:2]
    raw = b"".join(b"\x00" + a[i].tobytes() for i in range(H))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

# ---------- model ----------
def preprocess(sig):                 # sig (T,12) at 30 fps -> filtered, scale-free
    return bandpass(sig / (sig.mean(0) + 1e-9) - 1.0, FPS, 0.6, 3.5)

def make_windows(x, stride=STRIDE_S * FPS):
    W = [((x[s:s + L] - x[s:s + L].mean(0)) / (x[s:s + L].std(0) + 1e-8)).T.astype(np.float32)
         for s in range(0, len(x) - L + 1, stride)]
    return np.stack(W) if W else np.zeros((0, x.shape[1], L), np.float32)

class PulseNet(nn.Module):
    def __init__(self, in_ch=12, hid=64):
        super().__init__()
        def blk(i, o, d): return nn.Sequential(nn.Conv1d(i, o, 7, padding=3 * d, dilation=d), nn.BatchNorm1d(o), nn.GELU())
        self.net = nn.Sequential(blk(in_ch, hid, 1), blk(hid, hid, 2), blk(hid, hid, 4),
                                 blk(hid, hid, 8), blk(hid, hid, 1), nn.Conv1d(hid, 1, 1))
    def forward(self, x): return self.net(x).squeeze(1)

def pearson_loss(p, y):
    p = p - p.mean(1, keepdim=True); y = y - y.mean(1, keepdim=True)
    return (1 - (p * y).sum(1) / (p.norm(dim=1) * y.norm(dim=1) + 1e-8)).mean()

@torch.no_grad()
def predict(model, X, bs=128):
    model.eval(); out = [model(torch.as_tensor(X[i:i + bs])).cpu() for i in range(0, len(X), bs)]
    return torch.cat(out).numpy() if out else np.zeros((0, L))

def estimate_hr(model, sig30):
    """what the app calls: 12 colour signals at 30 fps -> HR + quality"""
    X = make_windows(preprocess(np.asarray(sig30, float)), stride=2 * FPS)
    if len(X) == 0: return None
    r = np.array([hr_snr(w) for w in predict(model, X)]); hrs, snr = r[:, 0], r[:, 1]
    good = snr > -3 if (snr > -3).any() else np.ones(len(snr), bool)
    return dict(hr=float(np.median(hrs[good])), snr_db=float(np.median(snr)),
                spread=float(np.std(hrs[good])), n_windows=int(len(X)))

# ---------- risk flag: partial NEWS2 (RCP) + ESI danger zones; screening aid, not diagnosis ----------
def s_hr(x):   return 3 if x <= 40 else 1 if x <= 50 else 0 if x <= 90 else 1 if x <= 110 else 2 if x <= 130 else 3
def s_rr(x):   return 3 if x <= 8 else 1 if x <= 11 else 0 if x <= 20 else 2 if x <= 24 else 3
def s_spo2(x): return 3 if x <= 91 else 2 if x <= 93 else 1 if x <= 95 else 0
def s_sbp(x):  return 3 if x <= 90 else 2 if x <= 100 else 1 if x <= 110 else 0 if x <= 219 else 3
def s_temp(x): return 3 if x <= 35.0 else 1 if x <= 36.0 else 0 if x <= 38.0 else 1 if x <= 39.0 else 2

def assess(hr=None, rr=None, spo2=None, sbp=None, temp=None, age=None):
    if age is not None and age < 18:
        return dict(light="NOT VALIDATED", total=None, worst=None, items={}, flags=[], note="Adult thresholds only (age 18+).")
    spec = dict(HR=(hr, s_hr), RR=(rr, s_rr), SpO2=(None if spo2 is None else round(spo2), s_spo2),
                SBP=(sbp, s_sbp), Temp=(temp, s_temp))
    items = {k: (float(v), int(f(v))) for k, (v, f) in spec.items() if v is not None}
    total = sum(s for _, s in items.values()); worst = max([s for _, s in items.values()] or [0])
    flags = []
    if hr is not None and hr > 100: flags.append("HR above 100 (ESI danger zone)")
    if rr is not None and rr > 20: flags.append("RR above 20 (ESI danger zone)")
    if spo2 is not None and spo2 < 92: flags.append("SpO2 below 92% (ESI danger zone)")
    light = "RED" if (worst == 3 or total >= 5) else "YELLOW" if (total >= 1 or flags) else "GREEN"
    return dict(light=light, total=int(total), worst=int(worst), items=items, flags=flags, note="")


# ---- PATCH: per-video face detection (OpenCV 4.x Haar). No silent fallback to the fixed box. ----
def _detector():
    try:
        import cv2
    except Exception:
        return None, None
    if not hasattr(cv2, "CascadeClassifier"): return None, None
    p = Path(__file__).resolve().parent / "haarcascade_frontalface_default.xml"
    if not p.exists(): return None, None
    c = cv2.CascadeClassifier(str(p))
    return (cv2, c) if not c.empty() else (None, None)

def detect_box(frames, every=10):
    cv2, c = _detector()
    if c is None: return None
    boxes = []
    for i, fr in enumerate(frames):
        if i % every: continue
        f = c.detectMultiScale(cv2.cvtColor(fr, cv2.COLOR_RGB2GRAY), 1.1, 5, minSize=(40, 40))
        if len(f): boxes.append(max(f, key=lambda r: r[2] * r[3]))
    return np.median(np.array(boxes, float), 0) if len(boxes) >= 3 else None

def overlay(frame, box=None):
    out = np.array(frame, np.uint8, copy=True); H, W = out.shape[:2]
    x, y, w, h = box if box is not None else box_for(H, W)
    def rect(xa, ya, xb, yb, col, t):
        xa, xb = int(max(0, xa)), int(min(W, xb)); ya, yb = int(max(0, ya)), int(min(H, yb))
        out[ya:ya + t, xa:xb] = col; out[yb - t:yb, xa:xb] = col
        out[ya:yb, xa:xa + t] = col; out[ya:yb, xb - t:xb] = col
    rect(x, y, x + w, y + h, (0, 255, 0), 2)
    for x0, x1, y0, y1 in ROIS: rect(x + x0 * w, y + y0 * h, x + x1 * w, y + y1 * h, (255, 255, 0), 1)
    return out

def extract_signals(video_path, max_s=None, n_detect=150):
    frames, fps = iter_frames(video_path, max_s=max_s)
    buf = []
    for fr in frames:
        buf.append(fr)
        if len(buf) >= n_detect: break
    box = detect_box(buf)
    if box is None: raise RuntimeError("no face found")
    def feat(fr):
        x, y, w, h = box; row = []
        for x0, x1, y0, y1 in ROIS:
            ya, yb = int(y + y0 * h), max(int(y + y1 * h), int(y + y0 * h) + 1)
            xa, xb = int(x + x0 * w), max(int(x + x1 * w), int(x + x0 * w) + 1)
            row.extend(fr[max(ya, 0):yb, max(xa, 0):xb].reshape(-1, 3).mean(0))
        return row
    feats = [feat(fr) for fr in buf] + [feat(fr) for fr in frames]
    return np.array(feats, float), fps
