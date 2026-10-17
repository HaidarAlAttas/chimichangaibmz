import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'frame_reader.dart';
import 'quality_gate.dart';

/// ML Kit face detection, used ONLY for the quality gate (is there one
/// centred, front-facing, still face?). Colour is always sampled from the
/// fixed boxes in ScanSpec so phone and training lane match.
class FaceDetectorService {
  FaceDetectorService()
      : _detector = isSupported
            ? FaceDetector(
                options: FaceDetectorOptions(
                  performanceMode: FaceDetectorMode.fast,
                  minFaceSize: 0.2,
                ),
              )
            : null;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final FaceDetector? _detector;
  bool _busy = false;

  bool get available => _detector != null;

  /// Returns null when no single face is found, or when the detector is still
  /// busy with the previous frame (caller keeps its last observation).
  Future<FaceObservation?>? detect(Frame f, int tMs) {
    final d = _detector;
    if (d == null || _busy) return null;
    _busy = true;
    return _run(d, f, tMs).whenComplete(() => _busy = false);
  }

  Future<FaceObservation?> _run(FaceDetector d, Frame f, int tMs) async {
    final isBgra = f.layout == PixelLayout.bgra8888;
    final input = InputImage.fromBytes(
      bytes: isBgra ? f.planes[0].bytes : toNv21(f),
      metadata: InputImageMetadata(
        size: Size(f.width.toDouble(), f.height.toDouble()),
        rotation: _rotation(f.rotation),
        format: isBgra ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
        bytesPerRow: isBgra ? f.planes[0].bytesPerRow : f.width,
      ),
    );
    final faces = await d.processImage(input);
    if (faces.length != 1) return null;
    final face = faces.first;
    final uw = f.uprightWidth.toDouble(), uh = f.uprightHeight.toDouble();
    final b = face.boundingBox;
    return FaceObservation(
      Rect.fromLTRB(b.left / uw, b.top / uh, b.right / uw, b.bottom / uh),
      tMs,
      yawDeg: face.headEulerAngleY,
      rollDeg: face.headEulerAngleZ,
    );
  }

  static InputImageRotation _rotation(int deg) {
    switch (deg) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> dispose() async => _detector?.close();
}
