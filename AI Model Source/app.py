import time, uuid, threading
from pathlib import Path
import numpy as np, torch, uvicorn, cv2
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
import pulsepal_core as core
from pulsepal_core import *

torch.set_num_threads(2)
HERE = Path(__file__).resolve().parent
MIN_SECONDS = 20        # shortest scan accepted (no quality gate: the model always returns an HR)
OUT_W = 480             # frames are resized to this width (same as training)
DETECT_EVERY = 3        # run the face detector on every 3rd frame, reuse the box in between
MAX_IDLE = 120          # a scan with no frames for 120 s is deleted
MAX_FRAMES = 3000       # safety cap per scan

app = FastAPI(title="PulsePal AI API", version="2.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

def load_model():
    npz = HERE / "models" / "pulsenet_portable.npz"
    if npz.exists():
        z = np.load(npz); m = PulseNet(12, 64)
        m.load_state_dict({k: torch.from_numpy(z[k].astype(z[k].dtype.newbyteorder("="))) for k in z.files})
    else:
        ck = torch.load(HERE / "models" / "pulsenet.pt", map_location="cpu")
        m = PulseNet(ck["in_ch"], ck["hid"]); m.load_state_dict(ck["state"])
    return m.eval()

model = load_model()

def bad(msg, code=400):
    return JSONResponse(status_code=code, content={"error": msg})

def compute_hr(t_ms, rgb):
    """frame timestamps (ms) + 12 colour averages per frame -> (hr, None) or (None, error message)"""
    try:
        t = np.asarray(t_ms, float) / 1000.0; rgb = np.asarray(rgb, float)
    except Exception:
        return None, "Bad data"
    if rgb.ndim != 2 or rgb.shape[1] != 12 or len(t) != len(rgb) or not np.isfinite(rgb).all():
        return None, "rgb must have 12 numbers per frame, same length as t"
    if len(t) < 60 or t[-1] - t[0] < MIN_SECONDS:
        return None, "Recording too short (need %d s or more)" % MIN_SECONDS
    if np.any(np.diff(t) <= 0):
        return None, "Timestamps must be increasing"
    grid = np.arange(t[0], t[-1], 1.0 / FPS)
    sig = np.stack([np.interp(grid, t, rgb[:, c]) for c in range(12)], 1)
    est = estimate_hr(model, sig)
    if est is None:
        return None, "Not enough signal"
    return round(float(est["hr"]), 1), None

# ------------------------------------------------------------------ scan sessions (frames sent to the server)
SCANS, SCANS_LOCK = {}, threading.Lock()
_warned = [False]

def find_face(fr):
    """RGB frame -> np.array [x, y, w, h] in pixels, or None. Uses the same detector as training."""
    try:
        b = core.detect_box(fr)
    except Exception as e:
        if not _warned[0]:
            _warned[0] = True; print("detect_box failed:", repr(e), flush=True)
        return None
    if b is None: return None
    b = np.asarray(b, float).ravel()
    if b.size < 4 or not np.isfinite(b[:4]).all() or b[2] <= 0 or b[3] <= 0: return None
    return b[:4]

def blend(box, b):
    """keep the box steady: only move it when the face really moved (> 6% of its size)"""
    if box is None: return b.copy()
    if np.abs(b - box).max() / max(b[2], 1.0) < 0.06: return box
    return box + 0.3 * (b - box)

def sweep():
    now = time.time()
    with SCANS_LOCK:
        for k in [k for k, s in SCANS.items() if now - s["last"] > MAX_IDLE]:
            del SCANS[k]

def process_frame(st, jpg, t_ms):
    img = cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_COLOR)
    if img is None: raise ValueError("Bad JPEG")
    fr = img[:, :, ::-1]                                    # BGR -> RGB
    H0, W0 = fr.shape[:2]
    if W0 != OUT_W:
        fr = cv2.resize(fr, (OUT_W, max(2, int(round(H0 * OUT_W / W0)))), interpolation=cv2.INTER_AREA)
    fr = np.ascontiguousarray(fr); H, W = fr.shape[:2]
    with st["lock"]:
        st["last"] = time.time()
        if st["t0"] is None: st["t0"] = t_ms
        if st["t"] and t_ms <= st["t"][-1]:                 # out-of-order frame: ignore
            return _status(st, W, H)
        if len(st["t"]) >= MAX_FRAMES: raise ValueError("Too many frames for one scan")
        if st["n"] % DETECT_EVERY == 0 or st["box"] is None:
            b = find_face(fr)
            if b is not None: st["box"] = blend(st["box"], b); st["miss"] = 0
            else: st["miss"] += 1
        st["n"] += 1
        found = st["box"] is not None and st["miss"] < 4
        x, y, w, h = st["box"] if st["box"] is not None else box_for(H, W)
        row = []
        for x0, x1, y0, y1 in ROIS:
            ya = min(max(int(y + y0 * h), 0), H - 1); yb = min(max(int(y + y1 * h), ya + 1), H)
            xa = min(max(int(x + x0 * w), 0), W - 1); xb = min(max(int(x + x1 * w), xa + 1), W)
            row.extend(fr[ya:yb, xa:xb].reshape(-1, 3).mean(0))
        st["t"].append(float(t_ms)); st["rgb"].append([float(v) for v in row])
        if not found: st["lost"] += 1
        return _status(st, W, H)

def _status(st, W, H):
    found = st["box"] is not None and st["miss"] < 4
    box = None
    if found:
        x, y, w, h = st["box"]
        box = dict(x=round(float(x) / W, 4), y=round(float(y) / H, 4), w=round(float(w) / W, 4), h=round(float(h) / H, 4))
    el = (st["t"][-1] - st["t0"]) / 1000.0 if st["t"] else 0.0
    return dict(face=bool(found), box=box, elapsed_s=round(el, 1), frames=len(st["t"]))

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/scan/start")
def scan_start():
    sweep()
    sid = uuid.uuid4().hex[:12]
    with SCANS_LOCK:
        SCANS[sid] = dict(t=[], rgb=[], box=None, miss=0, n=0, lost=0, t0=None, last=time.time(), lock=threading.Lock())
    return {"scan_id": sid, "min_seconds": MIN_SECONDS, "target_fps": 15}

@app.post("/scan/{scan_id}/frame")
async def scan_frame(scan_id: str, request: Request, t_ms: float):
    st = SCANS.get(scan_id)
    if st is None: return bad("Unknown or expired scan_id", 404)
    jpg = await request.body()
    if not jpg: return bad("Empty body: send the JPEG bytes")
    try:
        return await run_in_threadpool(process_frame, st, jpg, t_ms)
    except ValueError as e:
        return bad(str(e))

@app.post("/scan/{scan_id}/finish")
def scan_finish(scan_id: str):
    st = SCANS.get(scan_id)
    if st is None: return bad("Unknown or expired scan_id", 404)
    with st["lock"]:
        t, rgb = list(st["t"]), list(st["rgb"])
    hr, err = compute_hr(t, rgb)
    if err: return bad(err)                                 # scan is kept, the app may send more frames
    with SCANS_LOCK: SCANS.pop(scan_id, None)
    return {"hr": hr}

if __name__ == "__main__":
    kw = {}
    if (HERE / "cert.pem").exists():
        kw = dict(ssl_certfile=str(HERE / "cert.pem"), ssl_keyfile=str(HERE / "key.pem"))
    uvicorn.run(app, host="0.0.0.0", port=5000, **kw)