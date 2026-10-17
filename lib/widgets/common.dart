import 'package:flutter/material.dart';

import '../app/theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AppText.eyebrow);
}

/// Rounded pill with an optional leading dot.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.dot,
    this.onTap,
    this.height = 30,
    this.fontSize = 13,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color? dot;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(height)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: foreground)),
      ]),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(height), child: pill),
    );
  }
}

/// Blue rounded square with a pulse line. Not a third-party logo.
class PulseLogo extends StatelessWidget {
  const PulseLogo({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.3));
    canvas.drawRRect(r, Paint()..color = AppColors.accent);
    final k = s.width / 26;
    final p = Path()
      ..moveTo(4 * k, 14 * k)
      ..lineTo(8 * k, 14 * k)
      ..lineTo(10.5 * k, 9 * k)
      ..lineTo(14.5 * k, 18 * k)
      ..lineTo(17 * k, 14 * k)
      ..lineTo(22 * k, 14 * k);
    canvas.drawPath(
        p,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small rounded-square icon tile.
class IconTile extends StatelessWidget {
  const IconTile(this.icon,
      {super.key, this.color = AppColors.ink2, this.background = AppColors.paper, this.size = 32});
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration:
            BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, size: size * 0.52, color: color),
      );
}

/// Shown on every screen that displays sample data.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.watchSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(children: [
          Text('DEMO',
              style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 12,
                  color: AppColors.watch)),
          SizedBox(width: 10),
          Expanded(
            child: Text('Sample data, not a reading of you.',
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13, color: AppColors.watch)),
          ),
        ]),
      );
}

/// Horizontal bar with a highlighted band and a marker for the value.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.min,
    required this.max,
    required this.bandLow,
    required this.bandHigh,
    required this.value,
  });

  final double min, max, bandLow, bandHigh, value;

  @override
  Widget build(BuildContext context) {
    double pos(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0, right: 0, top: 4,
            child: Container(
                height: 6,
                decoration: BoxDecoration(
                    color: const Color(0xFFEEECE6), borderRadius: BorderRadius.circular(3))),
          ),
          Positioned(
            left: w * pos(bandLow),
            width: w * (pos(bandHigh) - pos(bandLow)),
            top: 4,
            child: Container(
                height: 6,
                decoration: BoxDecoration(
                    color: const Color(0xFFBFE3CC), borderRadius: BorderRadius.circular(3))),
          ),
          Positioned(
            left: w * pos(value) - 6,
            top: 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Four small signal bars (0-4 lit).
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.lit, required this.on, required this.off});
  final int lit;
  final Color on;
  final Color off;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.only(right: 3),
              width: 4,
              height: 6.0 + i * 3,
              decoration: BoxDecoration(
                  color: i < lit ? on : off, borderRadius: BorderRadius.circular(1)),
            ),
        ],
      );
}
