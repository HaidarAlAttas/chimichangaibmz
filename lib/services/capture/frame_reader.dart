import 'dart:typed_data';
import 'dart:ui';

/// Camera-agnostic view of one frame, so the maths here can be unit tested
/// without a camera. Built from a CameraImage in capture_controller.dart.
enum PixelLayout {
  /// Android NV21 in one plane: Y (height rows) then interleaved V,U.
  nv21,

  /// Android YUV_420_888 in three planes (Y, U, V) with strides.
  yuv420,

  /// iOS BGRA8888 in one plane.
  bgra8888,
}

class FramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
  const FramePlane(this.bytes, this.bytesPerRow, [this.bytesPerPixel = 1]);
}

class Frame {
  final int width;
  final int height;
  final PixelLayout layout;
  final List<FramePlane> planes;

  /// Clockwise rotation (0/90/180/270) that makes the raw buffer upright.
  final int rotation;

  const Frame({
    required this.width,
    required this.height,
    required this.layout,
    required this.planes,
    this.rotation = 0,
  });

  bool get _swaps => rotation == 90 || rotation == 270;
  int get uprightWidth => _swaps ? height : width;
  int get uprightHeight => _swaps ? width : height;
}

class RgbMean {
  final double r;
  final double g;
  final double b;
  final int pixels;
  const RgbMean(this.r, this.g, this.b, this.pixels);

  double get brightness => (r + g + b) / 3;
}

/// Maps a rect in normalised UPRIGHT coordinates to raw-buffer pixel bounds.
Rect uprightToRaw(Rect n, int rotation, int rawW, int rawH) {
  final swap = rotation == 90 || rotation == 270;
  final uw = (swap ? rawH : rawW).toDouble();
  final uh = (swap ? rawW : rawH).toDouble();
  Offset map(double u, double v) {
    switch (rotation) {
      case 90:
        return Offset(v, rawH - u);
      case 180:
        return Offset(rawW - u, rawH - v);
      case 270:
        return Offset(rawW - v, u);
      default:
        return Offset(u, v);
    }
  }

  final a = map(n.left * uw, n.top * uh);
  final b = map(n.right * uw, n.bottom * uh);
  return Rect.fromPoints(a, b).intersect(
      Rect.fromLTWH(0, 0, rawW.toDouble(), rawH.toDouble()));
}

/// Mean colour over the given normalised upright rects, pooled by pixel.
/// [step] skips pixels for speed (2 = every other pixel in x and y).
///
/// For YUV the Y/U/V means are accumulated and converted once (BT.601, full
/// range); the conversion is linear so this equals the mean of per-pixel RGB
/// without clamping bias.
RgbMean? meanRgb(Frame f, List<Rect> normalisedUprightRects, {int step = 2}) {
  double s0 = 0, s1 = 0, s2 = 0;
  var n = 0;

  for (final nr in normalisedUprightRects) {
    final r = uprightToRaw(nr, f.rotation, f.width, f.height);
    final x0 = r.left.floor(), x1 = r.right.ceil();
    final y0 = r.top.floor(), y1 = r.bottom.ceil();

    switch (f.layout) {
      case PixelLayout.bgra8888:
        final p = f.planes[0];
        for (var y = y0; y < y1; y += step) {
          final row = y * p.bytesPerRow;
          for (var x = x0; x < x1; x += step) {
            final i = row + x * 4;
            if (i + 2 >= p.bytes.length) continue;
            s2 += p.bytes[i]; // B
            s1 += p.bytes[i + 1]; // G
            s0 += p.bytes[i + 2]; // R
            n++;
          }
        }
        break;

      case PixelLayout.nv21:
        final p = f.planes[0];
        final ySize = p.bytesPerRow * f.height;
        for (var y = y0; y < y1; y += step) {
          final yRow = y * p.bytesPerRow;
          final uvRow = ySize + (y >> 1) * p.bytesPerRow;
          for (var x = x0; x < x1; x += step) {
            final uv = uvRow + (x >> 1) * 2;
            if (uv + 1 >= p.bytes.length) continue;
            s0 += p.bytes[yRow + x]; // Y
            s2 += p.bytes[uv]; // V
            s1 += p.bytes[uv + 1]; // U
            n++;
          }
        }
        break;

      case PixelLayout.yuv420:
        final yp = f.planes[0], up = f.planes[1], vp = f.planes[2];
        for (var y = y0; y < y1; y += step) {
          final yRow = y * yp.bytesPerRow;
          final uRow = (y >> 1) * up.bytesPerRow;
          final vRow = (y >> 1) * vp.bytesPerRow;
          for (var x = x0; x < x1; x += step) {
            final ui = uRow + (x >> 1) * up.bytesPerPixel;
            final vi = vRow + (x >> 1) * vp.bytesPerPixel;
            if (ui >= up.bytes.length || vi >= vp.bytes.length) continue;
            s0 += yp.bytes[yRow + x];
            s1 += up.bytes[ui];
            s2 += vp.bytes[vi];
            n++;
          }
        }
        break;
    }
  }

  if (n == 0) return null;
  final a = s0 / n, b = s1 / n, c = s2 / n;
  if (f.layout == PixelLayout.bgra8888) return RgbMean(a, b, c, n);

  // a = Y, b = U, c = V
  double clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v);
  return RgbMean(
    clamp(a + 1.402 * (c - 128)),
    clamp(a - 0.344136 * (b - 128) - 0.714136 * (c - 128)),
    clamp(a + 1.772 * (b - 128)),
    n,
  );
}

/// Packs any supported frame as NV21 bytes for ML Kit on Android.
Uint8List toNv21(Frame f) {
  if (f.layout == PixelLayout.nv21) return f.planes[0].bytes;
  final w = f.width, h = f.height;
  final out = Uint8List(w * h + 2 * (w >> 1) * (h >> 1));
  final yp = f.planes[0], up = f.planes[1], vp = f.planes[2];
  var o = 0;
  for (var y = 0; y < h; y++) {
    out.setRange(o, o + w, yp.bytes, y * yp.bytesPerRow);
    o += w;
  }
  for (var y = 0; y < h >> 1; y++) {
    for (var x = 0; x < w >> 1; x++) {
      out[o++] = vp.bytes[y * vp.bytesPerRow + x * vp.bytesPerPixel];
      out[o++] = up.bytes[y * up.bytesPerRow + x * up.bytesPerPixel];
    }
  }
  return out;
}
