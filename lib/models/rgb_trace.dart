/// Per-frame mean colour of the face ROIs. This is the only physiological
/// data that leaves the phone: no pixels, no video.
class RgbSample {
  final int tMs;
  final double r;
  final double g;
  final double b;

  const RgbSample(this.tMs, this.r, this.g, this.b);
}

class RgbTrace {
  final List<RgbSample> samples;

  const RgbTrace(this.samples);

  int get length => samples.length;

  double get durationSeconds =>
      samples.length < 2 ? 0 : (samples.last.tMs - samples.first.tMs) / 1000.0;

  Map<String, dynamic> toJson() {
    final t0 = samples.isEmpty ? 0 : samples.first.tMs;
    return {
      't_ms': [for (final s in samples) s.tMs - t0],
      'r': [for (final s in samples) _round(s.r)],
      'g': [for (final s in samples) _round(s.g)],
      'b': [for (final s in samples) _round(s.b)],
    };
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}
