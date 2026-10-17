import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../config/scan_spec.dart';

/// Maps normalised upright-frame coordinates to screen coordinates for a
/// camera preview that is scaled to COVER the screen. Used so the oval and
/// ROI boxes on screen are exactly the regions being sampled.
class FrameToScreen {
  FrameToScreen(Size screen, double frameAspect) {
    // frameAspect = width / height of the upright frame (e.g. 0.75).
    if (screen.width / screen.height > frameAspect) {
      _w = screen.width;
      _h = screen.width / frameAspect;
    } else {
      _h = screen.height;
      _w = screen.height * frameAspect;
    }
    _dx = (screen.width - _w) / 2;
    _dy = (screen.height - _h) / 2;
  }

  late final double _w, _h, _dx, _dy;

  Rect map(Rect n) =>
      Rect.fromLTRB(_dx + n.left * _w, _dy + n.top * _h, _dx + n.right * _w, _dy + n.bottom * _h);
}

/// Dimmed surround, oval face guide, progress ring and ROI boxes.
class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({
    super.key,
    required this.frameAspect,
    required this.recording,
    required this.progress,
    required this.showRois,
  });

  final double frameAspect;
  final bool recording;
  final double progress;
  final bool showRois;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final m = FrameToScreen(c.biggest, frameAspect);
          return CustomPaint(
            size: c.biggest,
            painter: _OverlayPainter(
              oval: m.map(ScanSpec.faceBox),
              rois: showRois ? ScanSpec.roisInFrame.map(m.map).toList() : const [],
              recording: recording,
              progress: progress,
            ),
          );
        },
      );

  /// Screen-space oval rect, for positioning text below it.
  static Rect ovalRect(Size screen, double frameAspect) =>
      FrameToScreen(screen, frameAspect).map(ScanSpec.faceBox);
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.oval,
    required this.rois,
    required this.recording,
    required this.progress,
  });

  final Rect oval;
  final List<Rect> rois;
  final bool recording;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(dim, Paint()..color = const Color(0x9E06080C));

    if (!recording) {
      _dashedOval(canvas, Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
    } else {
      canvas.drawOval(
          oval,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5);
      final ring = Path()..addOval(oval);
      final metric = ring.computeMetrics().first;
      // Start at the top of the oval.
      final start = metric.length * 0.75;
      final len = metric.length * progress.clamp(0.0, 1.0);
      final arc = Path();
      if (start + len <= metric.length) {
        arc.addPath(metric.extractPath(start, start + len), Offset.zero);
      } else {
        arc.addPath(metric.extractPath(start, metric.length), Offset.zero);
        arc.addPath(metric.extractPath(0, start + len - metric.length), Offset.zero);
      }
      canvas.drawPath(
          arc,
          Paint()
            ..color = AppColors.cameraAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round);
    }

    final roiPaint = Paint()
      ..color = AppColors.cameraOk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final r in rois) {
      _dashedRRect(canvas, RRect.fromRectAndRadius(r, const Radius.circular(8)), roiPaint);
    }
  }

  void _dashedOval(Canvas canvas, Paint p) =>
      _dashed(canvas, Path()..addOval(oval), p, 10, 8);

  void _dashedRRect(Canvas canvas, RRect r, Paint p) =>
      _dashed(canvas, Path()..addRRect(r), p, 4, 3);

  void _dashed(Canvas canvas, Path path, Paint p, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), p);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.recording != recording || old.progress != progress || old.oval != oval ||
      old.rois.length != rois.length;
}
