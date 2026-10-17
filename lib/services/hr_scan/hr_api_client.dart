import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:http/http.dart' as http;

import '../../config/scan_api_config.dart';

/// Face box as fractions (0..1) of the frame that was sent. x, y = top-left.
class FaceBox {
  final double x, y, w, h;
  const FaceBox(this.x, this.y, this.w, this.h);

  factory FaceBox.fromJson(Map<String, dynamic> j) => FaceBox(
      (j['x'] as num).toDouble(),
      (j['y'] as num).toDouble(),
      (j['w'] as num).toDouble(),
      (j['h'] as num).toDouble());

  Rect get rect => Rect.fromLTWH(x, y, w, h);
}

class FaceStatus {
  final bool face;
  final FaceBox? box;
  final double elapsedS;
  final int frames;
  const FaceStatus(
      {required this.face, this.box, required this.elapsedS, required this.frames});

  factory FaceStatus.fromJson(Map<String, dynamic> j) => FaceStatus(
        face: j['face'] == true,
        box: j['box'] is Map<String, dynamic>
            ? FaceBox.fromJson(j['box'] as Map<String, dynamic>)
            : null,
        elapsedS: (j['elapsed_s'] as num?)?.toDouble() ?? 0,
        frames: (j['frames'] as num?)?.toInt() ?? 0,
      );
}

class ScanSession {
  final String scanId;
  final int minSeconds;
  final int targetFps;
  const ScanSession(this.scanId, this.minSeconds, this.targetFps);
}

class HrResult {
  final double hr;
  const HrResult(this.hr);
}

/// The server answered with an error status ({"error": "..."}).
class ScanApiException implements Exception {
  final int statusCode;
  final String message;
  const ScanApiException(this.statusCode, this.message);

  bool get isExpired => statusCode == 404;
  bool get isTooShort => message.toLowerCase().contains('too short');

  @override
  String toString() => message;
}

/// Network failure or timeout (no usable answer from the server).
class ScanNetworkException implements Exception {
  final String message;
  const ScanNetworkException(this.message);

  @override
  String toString() => message;
}

class HrApiClient {
  HrApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? ScanApiConfig.baseUrl;

  final http.Client _client;
  final String _base;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  Future<ScanSession> startScan() async {
    final j = await _send(() => _client.post(_uri('/scan/start')));
    return ScanSession(j['scan_id'] as String, (j['min_seconds'] as num?)?.toInt() ?? 20,
        (j['target_fps'] as num?)?.toInt() ?? ScanApiConfig.targetFps);
  }

  Future<FaceStatus> sendFrame(String scanId, int tMs, Uint8List jpegBytes) async {
    final j = await _send(() => _client.post(
          _uri('/scan/$scanId/frame', {'t_ms': '$tMs'}),
          headers: const {'Content-Type': 'image/jpeg'},
          body: jpegBytes,
        ));
    return FaceStatus.fromJson(j);
  }

  Future<HrResult> finish(String scanId) async {
    final j = await _send(() => _client.post(_uri('/scan/$scanId/finish')));
    return HrResult((j['hr'] as num).toDouble());
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(ScanApiConfig.requestTimeout);
    } on TimeoutException {
      throw const ScanNetworkException('Timed out reaching the server');
    } catch (_) {
      throw const ScanNetworkException(
          'Could not reach the server. Check your network and that the backend is running.');
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode != 200) {
      throw ScanApiException(
          res.statusCode, body?['error']?.toString() ?? 'Server error ${res.statusCode}');
    }
    if (body == null) throw const ScanApiException(500, 'Unexpected server response');
    return body;
  }

  void close() => _client.close();
}
