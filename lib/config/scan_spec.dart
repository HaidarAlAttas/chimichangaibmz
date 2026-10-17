import 'dart:ui';

/// Fixed capture geometry shared by the phone and the offline training lane.
///
/// Review item 6 / Flutter feasibility flag: the training lane must sample the
/// SAME regions the phone does. These numbers are mirrored in
/// `training/roi_reference.py` and documented in docs/MODEL_INPUT_SPEC.md.
/// Change all three together.
class ScanSpec {
  ScanSpec._();

  static const int durationSeconds = 30;
  static const int nominalFps = 30;

  /// Face box in normalised coordinates of the UPRIGHT (portrait) camera
  /// frame. The on-screen oval is drawn inside exactly this box.
  static const Rect faceBox = Rect.fromLTRB(0.22, 0.16, 0.78, 0.68);

  /// Sampling regions as fractions of [faceBox]: forehead, left cheek, right
  /// cheek. Their pixels are pooled into one mean (r, g, b) per frame.
  static const List<Rect> roisInFaceBox = [
    Rect.fromLTRB(0.30, 0.10, 0.70, 0.28),
    Rect.fromLTRB(0.12, 0.50, 0.36, 0.70),
    Rect.fromLTRB(0.64, 0.50, 0.88, 0.70),
  ];

  /// ROIs in normalised upright-frame coordinates.
  static List<Rect> get roisInFrame => [
        for (final r in roisInFaceBox)
          Rect.fromLTRB(
            faceBox.left + r.left * faceBox.width,
            faceBox.top + r.top * faceBox.height,
            faceBox.left + r.right * faceBox.width,
            faceBox.top + r.bottom * faceBox.height,
          ),
      ];

  /// Share of recorded frames that must pass the on-device gate before the
  /// scan is uploaded. Below this the app shows the retake screen directly.
  static const double minDeviceSqi = 0.6;
}
