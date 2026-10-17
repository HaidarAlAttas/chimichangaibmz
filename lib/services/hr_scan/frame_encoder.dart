import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../config/scan_api_config.dart';

/// Plain-data copy of one camera frame so it can cross into an isolate.
class EncodeJob {
  final int width, height, rotation;
  final bool bgra;
  final List<Uint8List> planes;
  final List<int> rowStrides, pixelStrides;
  const EncodeJob(this.width, this.height, this.rotation, this.bgra, this.planes,
      this.rowStrides, this.pixelStrides);
}

/// Copies the planes (they are only valid during the stream callback) and
/// encodes in a background isolate. Returns upright, UNmirrored JPEG bytes.
/// [rotation] = clockwise degrees that make the raw buffer upright.
Future<Uint8List?> encodeCameraImage(CameraImage image, int rotation) {
  final bgra = image.format.group == ImageFormatGroup.bgra8888;
  if (!bgra && image.planes.length < 3) return Future.value(null);
  final job = EncodeJob(
    image.width,
    image.height,
    rotation,
    bgra,
    [for (final p in image.planes) Uint8List.fromList(p.bytes)],
    [for (final p in image.planes) p.bytesPerRow],
    [for (final p in image.planes) p.bytesPerPixel ?? 1],
  );
  return compute(_encode, job);
}

Uint8List _encode(EncodeJob j) {
  final swap = j.rotation == 90 || j.rotation == 270;
  final uw = swap ? j.height : j.width;
  final uh = swap ? j.width : j.height;
  final ow = uw < ScanApiConfig.frameWidth ? uw : ScanApiConfig.frameWidth;
  final oh = (uh * ow / uw).round().clamp(2, 4096);
  final rgb = Uint8List(ow * oh * 3);

  final p0 = j.planes[0];
  final rs0 = j.rowStrides[0];
  final yp = p0, up = j.bgra ? p0 : j.planes[1], vp = j.bgra ? p0 : j.planes[2];
  final uvRs = j.bgra ? 0 : j.rowStrides[1];
  final uvPs = j.bgra ? 0 : j.pixelStrides[1];

  var o = 0;
  for (var oy = 0; oy < oh; oy++) {
    final v = (oy * uh / oh).floor();
    for (var ox = 0; ox < ow; ox++) {
      final u = (ox * uw / ow).floor();
      final int x, y;
      switch (j.rotation) {
        case 90:
          x = v;
          y = j.height - 1 - u;
        case 180:
          x = j.width - 1 - u;
          y = j.height - 1 - v;
        case 270:
          x = j.width - 1 - v;
          y = u;
        default:
          x = u;
          y = v;
      }
      int r, g, b;
      if (j.bgra) {
        final i = y * rs0 + x * 4;
        b = yp[i];
        g = yp[i + 1];
        r = yp[i + 2];
      } else {
        final yy = yp[y * rs0 + x];
        final ci = (y >> 1) * uvRs + (x >> 1) * uvPs;
        final uu = up[ci] - 128, vv = vp[ci] - 128;
        r = (yy + 1.402 * vv).round();
        g = (yy - 0.344136 * uu - 0.714136 * vv).round();
        b = (yy + 1.772 * uu).round();
        r = r < 0 ? 0 : (r > 255 ? 255 : r);
        g = g < 0 ? 0 : (g > 255 ? 255 : g);
        b = b < 0 ? 0 : (b > 255 ? 255 : b);
      }
      rgb[o++] = r;
      rgb[o++] = g;
      rgb[o++] = b;
    }
  }
  final image = img.Image.fromBytes(
      width: ow, height: oh, bytes: rgb.buffer, numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(image, quality: ScanApiConfig.jpegQuality));
}
