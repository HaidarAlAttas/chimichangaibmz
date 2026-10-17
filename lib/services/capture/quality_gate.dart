import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../../config/scan_spec.dart';

/// Architecture step 1.4: on-device quality gate.
///
/// Three live checks (lighting, face, movement). Start unlocks only after all
/// three pass continuously for [holdMs]. During recording each frame is marked
/// valid/invalid; the share of valid frames is the on-device SQI sent to the
/// server, and a low share sends the user straight to the retake screen.

enum CheckState { pending, ok, fail }

class Check {
  final CheckState state;
  final String message;
  const Check(this.state, this.message);

  bool get ok => state == CheckState.ok;
}

/// What the face detector saw, in normalised upright-frame coordinates.
class FaceObservation {
  final Rect box;
  final double? yawDeg;
  final double? rollDeg;
  final int tMs;
  const FaceObservation(this.box, this.tMs, {this.yawDeg, this.rollDeg});
}

class GateSnapshot {
  final Check lighting;
  final Check face;
  final Check movement;

  /// All checks have held long enough to start.
  final bool ready;
  const GateSnapshot(this.lighting, this.face, this.movement, this.ready);

  int get passed => [lighting, face, movement].where((c) => c.ok).length;
  bool get allOk => lighting.ok && face.ok && movement.ok;
}

class QualityGate {
  QualityGate({this.faceDetectionAvailable = true});

  /// False on platforms without ML Kit (desktop, web, simulator). The face
  /// check then relies on brightness only and says so.
  final bool faceDetectionAvailable;

  static const int holdMs = 1000;
  static const int faceStaleMs = 700;
  static const double minBrightness = 55;
  static const double maxBrightness = 225;
  static const double maxCentreOffset = 0.10;
  static const double maxAngleDeg = 15;
  static const double maxDrift = 0.025; // of frame width, over the last second

  final _brightness = ListQueue<_T>();
  final _centres = ListQueue<_P>();
  FaceObservation? _face;
  int? _allOkSince;

  void addFace(FaceObservation? f, int tMs) {
    if (f == null) {
      _face = null;
      return;
    }
    _face = f;
    _centres.add(_P(tMs, f.box.center));
    _trim(_centres, tMs, 1000);
  }

  /// Call once per frame with the ROI brightness (0-255).
  GateSnapshot update(double brightness, int tMs) {
    _brightness.add(_T(tMs, brightness));
    _trim(_brightness, tMs, 500);

    final lighting = _lighting();
    final face = _faceCheck(tMs);
    final movement = face.ok ? _movement() : const Check(CheckState.pending, 'Waiting for face');

    final allOk = lighting.ok && face.ok && movement.ok;
    if (allOk) {
      _allOkSince ??= tMs;
    } else {
      _allOkSince = null;
    }
    final ready = allOk && tMs - _allOkSince! >= holdMs;
    return GateSnapshot(lighting, face, movement, ready);
  }

  void reset() {
    _brightness.clear();
    _centres.clear();
    _face = null;
    _allOkSince = null;
  }

  Check _lighting() {
    if (_brightness.isEmpty) return const Check(CheckState.pending, 'Checking…');
    final mean = _brightness.map((e) => e.v).reduce((a, b) => a + b) / _brightness.length;
    if (mean < minBrightness) return const Check(CheckState.fail, 'Too dark');
    if (mean > maxBrightness) return const Check(CheckState.fail, 'Too bright');
    return const Check(CheckState.ok, 'Good');
  }

  Check _faceCheck(int tMs) {
    if (!faceDetectionAvailable) return const Check(CheckState.ok, 'Assumed');
    final f = _face;
    if (f == null || tMs - f.tMs > faceStaleMs) {
      return const Check(CheckState.fail, 'No face found');
    }
    final fb = ScanSpec.faceBox;
    final widthRatio = f.box.width / fb.width;
    if (widthRatio < 0.65) return const Check(CheckState.fail, 'Move closer');
    if (widthRatio > 1.35) return const Check(CheckState.fail, 'Move back');
    final d = f.box.center - fb.center;
    if (d.dx.abs() > maxCentreOffset || d.dy.abs() > maxCentreOffset) {
      return const Check(CheckState.fail, 'Centre your face');
    }
    if ((f.yawDeg ?? 0).abs() > maxAngleDeg || (f.rollDeg ?? 0).abs() > maxAngleDeg) {
      return const Check(CheckState.fail, 'Look straight ahead');
    }
    return const Check(CheckState.ok, 'Locked');
  }

  Check _movement() {
    if (!faceDetectionAvailable) {
      // Without a face box, use brightness jitter as a proxy for movement.
      if (_brightness.length < 5) return const Check(CheckState.pending, 'Hold still…');
      final vals = _brightness.map((e) => e.v).toList();
      final spread = vals.reduce(math.max) - vals.reduce(math.min);
      return spread < 6
          ? const Check(CheckState.ok, 'Steady')
          : const Check(CheckState.pending, 'Hold still…');
    }
    if (_centres.length < 3) return const Check(CheckState.pending, 'Hold still…');
    final first = _centres.first.p;
    var drift = 0.0;
    for (final c in _centres) {
      drift = math.max(drift, (c.p - first).distance);
    }
    return drift <= maxDrift
        ? const Check(CheckState.ok, 'Steady')
        : const Check(CheckState.pending, 'Hold still…');
  }

  static void _trim<E extends _Timed>(ListQueue<E> q, int now, int windowMs) {
    while (q.isNotEmpty && now - q.first.t > windowMs) {
      q.removeFirst();
    }
  }
}

abstract class _Timed {
  int get t;
}

class _T implements _Timed {
  @override
  final int t;
  final double v;
  _T(this.t, this.v);
}

class _P implements _Timed {
  @override
  final int t;
  final Offset p;
  _P(this.t, this.p);
}

/// Tracks frame validity during recording.
class RecordingQuality {
  int _total = 0;
  int _valid = 0;
  final _recent = ListQueue<bool>();
  final Map<String, int> _failures = {};

  void add(GateSnapshot s) {
    final ok = s.allOk;
    _total++;
    if (ok) _valid++;
    _recent.add(ok);
    if (_recent.length > 60) _recent.removeFirst();
    if (!s.lighting.ok) _failures.update('lighting', (v) => v + 1, ifAbsent: () => 1);
    if (!s.face.ok) _failures.update('face_lost', (v) => v + 1, ifAbsent: () => 1);
    if (s.face.ok && !s.movement.ok) {
      _failures.update('motion', (v) => v + 1, ifAbsent: () => 1);
    }
  }

  /// Share of valid frames over the whole recording (on-device SQI).
  double get deviceSqi => _total == 0 ? 0 : _valid / _total;

  /// 0-4 bars over the last ~2 s, for the live meter.
  int get liveBars {
    if (_recent.isEmpty) return 0;
    final share = _recent.where((v) => v).length / _recent.length;
    return (share * 4).round().clamp(0, 4);
  }

  /// Most common failure reasons, worst first.
  List<String> get reasons {
    final e = _failures.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in e) if (x.value > _total * 0.1) x.key];
  }
}
