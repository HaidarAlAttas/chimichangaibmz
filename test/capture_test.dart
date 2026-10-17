import 'dart:typed_data';
import 'dart:ui';

import 'package:chimichangaibmz/config/scan_spec.dart';
import 'package:chimichangaibmz/services/capture/frame_reader.dart';
import 'package:chimichangaibmz/services/capture/quality_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Frame _bgra(int w, int h, int r, int g, int b) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes[i * 4] = b;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = r;
    bytes[i * 4 + 3] = 255;
  }
  return Frame(width: w, height: h, layout: PixelLayout.bgra8888,
      planes: [FramePlane(bytes, w * 4, 4)]);
}

/// NV21 frame of one colour, given as Y/U/V.
Frame _nv21(int w, int h, int y, int u, int v, {int rotation = 0}) {
  final bytes = Uint8List(w * h + w * (h ~/ 2));
  bytes.fillRange(0, w * h, y);
  for (var i = w * h; i < bytes.length; i += 2) {
    bytes[i] = v;
    bytes[i + 1] = u;
  }
  return Frame(width: w, height: h, layout: PixelLayout.nv21,
      planes: [FramePlane(bytes, w)], rotation: rotation);
}

void main() {
  group('frame_reader', () {
    test('BGRA mean colour over the fixed ROIs', () {
      final m = meanRgb(_bgra(120, 160, 200, 120, 90), ScanSpec.roisInFrame)!;
      expect(m.r, closeTo(200, 0.01));
      expect(m.g, closeTo(120, 0.01));
      expect(m.b, closeTo(90, 0.01));
      expect(m.pixels, greaterThan(100));
    });

    test('NV21 converts YUV to RGB (BT.601 full range)', () {
      // Grey: U = V = 128 -> R = G = B = Y.
      final grey = meanRgb(_nv21(160, 120, 100, 128, 128, rotation: 270), ScanSpec.roisInFrame)!;
      expect(grey.r, closeTo(100, 0.01));
      expect(grey.g, closeTo(100, 0.01));
      expect(grey.b, closeTo(100, 0.01));
      // Skin-ish: V > 128 pushes red up, blue down relative to green.
      final skin = meanRgb(_nv21(160, 120, 140, 115, 150, rotation: 270), ScanSpec.roisInFrame)!;
      expect(skin.r, greaterThan(skin.g));
      expect(skin.g, greaterThan(skin.b));
    });

    test('upright rect maps into raw bounds for every rotation', () {
      const n = Rect.fromLTRB(0.1, 0.2, 0.4, 0.5);
      for (final rot in [0, 90, 180, 270]) {
        final r = uprightToRaw(n, rot, 640, 480);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(640));
        expect(r.bottom, lessThanOrEqualTo(480));
        final swapped = rot == 90 || rot == 270;
        expect(r.width, closeTo(0.3 * (swapped ? 480 : 640), 0.01));
        expect(r.height, closeTo(0.3 * (swapped ? 640 : 480), 0.01));
      }
      // 270 (Android front camera): upright top-left -> raw right edge, top.
      final r = uprightToRaw(const Rect.fromLTRB(0, 0, 0.1, 0.1), 270, 640, 480);
      expect(r.right, 640);
      expect(r.top, 0);
    });
  });

  group('quality_gate', () {
    FaceObservation centred(int t) => FaceObservation(ScanSpec.faceBox, t);

    test('unlocks only after all checks hold for a second', () {
      final g = QualityGate();
      GateSnapshot s = g.update(120, 0);
      for (var t = 0; t <= 2000; t += 33) {
        g.addFace(centred(t), t);
        s = g.update(120, t);
        if (t < 900) expect(s.ready, isFalse);
      }
      expect(s.allOk, isTrue);
      expect(s.ready, isTrue);
    });

    test('flags dark scenes and off-centre faces', () {
      final g = QualityGate();
      g.addFace(FaceObservation(ScanSpec.faceBox.shift(const Offset(0.2, 0)), 0), 0);
      final s = g.update(20, 0);
      expect(s.lighting.message, 'Too dark');
      expect(s.face.message, 'Centre your face');
      expect(s.ready, isFalse);
    });

    test('movement fails while the face drifts', () {
      final g = QualityGate();
      late GateSnapshot s;
      for (var t = 0; t <= 1000; t += 33) {
        final box = ScanSpec.faceBox.shift(Offset(0.0015 * t / 33, 0));
        g.addFace(FaceObservation(box, t), t);
        s = g.update(120, t);
      }
      expect(s.movement.ok, isFalse);
    });

    test('recording quality reports share of good frames and reasons', () {
      const ok = Check(CheckState.ok, '');
      const bad = Check(CheckState.fail, '');
      final q = RecordingQuality();
      for (var i = 0; i < 70; i++) {
        q.add(const GateSnapshot(ok, ok, ok, true));
      }
      for (var i = 0; i < 30; i++) {
        q.add(const GateSnapshot(ok, bad, ok, false));
      }
      expect(q.deviceSqi, closeTo(0.7, 1e-9));
      expect(q.reasons, ['face_lost']);
    });
  });
}
