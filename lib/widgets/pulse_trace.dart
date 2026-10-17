import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Live pulse trace from the green channel, detrended with a 1 s moving
/// average so the heartbeat is visible. Display only; analysis is server-side.
class PulseTrace extends StatelessWidget {
  const PulseTrace({super.key, required this.green, this.height = 64});
  final Iterable<double> green;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _TracePainter(green.toList(growable: false))),
      );
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.raw);
  final List<double> raw;

  @override
  void paint(Canvas canvas, Size size) {
    if (raw.length < 35) {
      final tp = TextPainter(
        text: const TextSpan(
            text: 'Waiting for signal…',
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13, color: AppColors.cameraText2)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, (size.height - tp.height) / 2));
      return;
    }
    const win = 30;
    final v = <double>[];
    for (var i = win; i < raw.length; i++) {
      var s = 0.0;
      for (var j = i - win; j < i; j++) {
        s += raw[j];
      }
      v.add(-(raw[i] - s / win)); // invert: blood volume up = darker green
    }
    var lo = v.first, hi = v.first;
    for (final x in v) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    final span = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;

    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height * (0.9 - 0.8 * (v[i] - lo) / span);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        AppColors.cameraAccent.withValues(alpha: 0.15),
        AppColors.cameraAccent,
      ], stops: const [0, 0.7])
          .createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
