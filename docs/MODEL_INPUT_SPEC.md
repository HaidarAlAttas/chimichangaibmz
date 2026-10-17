# Model input spec (phone ⇄ server ⇄ training lane)

Review item 6: the vitals model must receive **exactly the same input** in
training and in serving. This file is the single definition. If you change
anything here, change the three code locations listed at the bottom in the
same commit.

## 1. Regions of interest (phone and training lane)

All coordinates are normalised to the **upright (portrait) frame**, origin top-left.

| Name | Definition |
|---|---|
| Face box | `x 0.22–0.78, y 0.16–0.68` of the frame. The on-screen oval is drawn inside this box. |
| Forehead ROI | `x 0.30–0.70, y 0.10–0.28` of the face box |
| Left cheek ROI | `x 0.12–0.36, y 0.50–0.70` of the face box |
| Right cheek ROI | `x 0.64–0.88, y 0.50–0.70` of the face box |

Per frame, pool **all pixels of the three ROIs** (every 2nd pixel in x and y)
and take the mean R, G, B on a 0–255 scale. That gives one `(t_ms, r, g, b)`
row per frame. No other pixel data is used or sent.

- **Phone:** the boxes are fixed relative to the frame; the user aligns their
  face to the oval and the quality gate (ML Kit) checks that they did.
  ML Kit's face box is **not** used for sampling.
- **Training lane (OpenCV):** dataset videos aren't framed with our oval, so
  detect the face **once on the first frame**, set the face box to that
  detection, then keep it **fixed** for the whole clip and apply the same ROI
  fractions. Use `training/roi_reference.py` — it is the reference
  implementation of the pooling above.
- YUV frames are converted with BT.601 full-range coefficients after averaging
  Y, U, V (the conversion is linear, so this equals the per-pixel mean).

## 2. Upload (phone → server)

`POST /api/v1/scans` body (see `linuxone_server/schemas.py`):

```json
{ "age": 34, "sex": "female", "fps": 30, "duration_s": 30.0,
  "traces": { "t_ms": [0, 33, 67, ...], "r": [...], "g": [...], "b": [...] },
  "device_sqi": 0.93, "source": "camera", "app_version": "1.1.0" }
```

- `t_ms` is real capture time, so dropped frames are visible. Never assume 30 fps.
- `device_sqi` = share of recorded frames that passed the on-device gate.

## 3. Server preprocessing (stage 2, `linuxone_server/pipeline/dsp.py`)

1. Resample R, G, B to a uniform **30 Hz** grid by linear interpolation on `t_ms`.
2. **Cardiac path:** POS projection (window 1.6 s) → linear detrend →
   Butterworth band-pass **0.7–4.0 Hz**, order 3, zero-phase (`filtfilt`) → `bvp`.
3. **Respiratory path (separate, review item 5):** green channel divided by its
   mean → linear detrend → band-pass **0.1–0.5 Hz**, order 2 → `resp`.
4. SQI = share of in-band cardiac power at the spectral peak ± 0.12 Hz and its
   2nd harmonic, mapped to 0–1. Below 0.45 the scan is rejected (no numbers).

## 4. Vitals model input tensor (stage 3)

```
x: float32[1, 2, 900]   # 30 s × 30 Hz
   channel 0 = bvp   (cardiac path above)
   channel 1 = resp  (respiratory path above)
   each channel z-scored per clip: (x - mean) / (std + 1e-6)
   shorter clips: zero-pad at the end; longer: keep the last 900 samples
outputs: heart_rate_bpm (float), respiratory_rate_bpm (float)
```

Training must build `x` by calling the **same** `pipeline/dsp.py` functions on
the RGB traces produced by `training/roi_reference.py`. Don't re-implement the
filters in the notebook.

No SpO₂ head: a phone RGB camera can't measure it reliably (review item 1).

## Where this is implemented

| Part | File |
|---|---|
| ROI geometry (phone) | `lib/config/scan_spec.dart` |
| ROI pooling (phone) | `lib/services/capture/frame_reader.dart` |
| ROI geometry + pooling (training) | `training/roi_reference.py` |
| Resampling, POS, filters, SQI | `linuxone_server/pipeline/dsp.py` |
