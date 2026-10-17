"""
Reference ROI pooling for the offline training lane.

Mirrors lib/config/scan_spec.dart + lib/services/capture/frame_reader.dart so
the model is trained on exactly what the phone sends. See
docs/MODEL_INPUT_SPEC.md.

Usage with OpenCV:
    face = detect_face_once(first_frame_bgr)            # your detector -> (x, y, w, h) px
    for frame in video:
        r, g, b = roi_mean_rgb(frame_rgb, face_box_px=face)
"""

from __future__ import annotations

from typing import Optional, Sequence, Tuple

import numpy as np

# Normalised to the upright frame. Must match ScanSpec.faceBox.
FACE_BOX = (0.22, 0.16, 0.78, 0.68)  # left, top, right, bottom

# Fractions of the face box. Must match ScanSpec.roisInFaceBox.
ROIS_IN_FACE_BOX = (
    (0.30, 0.10, 0.70, 0.28),  # forehead
    (0.12, 0.50, 0.36, 0.70),  # left cheek
    (0.64, 0.50, 0.88, 0.70),  # right cheek
)
STEP = 2


def roi_rects_px(frame_w: int, frame_h: int,
                 face_box_px: Optional[Tuple[float, float, float, float]] = None):
    """ROI rectangles in pixels. face_box_px = (x, y, w, h); if None, the
    fixed phone face box is used (for footage framed like the app)."""
    if face_box_px is None:
        l, t, r, b = FACE_BOX
        fx, fy, fw, fh = l * frame_w, t * frame_h, (r - l) * frame_w, (b - t) * frame_h
    else:
        fx, fy, fw, fh = face_box_px
    out = []
    for l, t, r, b in ROIS_IN_FACE_BOX:
        out.append((int(np.floor(fx + l * fw)), int(np.floor(fy + t * fh)),
                    int(np.ceil(fx + r * fw)), int(np.ceil(fy + b * fh))))
    return out


def roi_mean_rgb(frame_rgb: np.ndarray,
                 face_box_px: Optional[Sequence[float]] = None) -> Tuple[float, float, float]:
    """Pooled mean (r, g, b) over the three ROIs, sampling every STEP-th pixel.
    frame_rgb: HxWx3 uint8 in RGB order (convert from OpenCV's BGR first)."""
    h, w = frame_rgb.shape[:2]
    chunks = []
    for x0, y0, x1, y1 in roi_rects_px(w, h, tuple(face_box_px) if face_box_px else None):
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(w, x1), min(h, y1)
        if x1 > x0 and y1 > y0:
            chunks.append(frame_rgb[y0:y1:STEP, x0:x1:STEP].reshape(-1, 3))
    if not chunks:
        raise ValueError("ROIs fall outside the frame")
    px = np.concatenate(chunks).astype(np.float64)
    r, g, b = px.mean(axis=0)
    return float(r), float(g), float(b)


if __name__ == "__main__":
    img = np.zeros((640, 480, 3), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = 200, 120, 90
    assert roi_mean_rgb(img) == (200.0, 120.0, 90.0)
    print("ok", roi_rects_px(480, 640))
