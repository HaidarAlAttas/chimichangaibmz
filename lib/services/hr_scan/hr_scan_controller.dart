import 'dart:async';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../config/scan_api_config.dart';
import 'frame_encoder.dart';
import 'hr_api_client.dart';

enum HrScanPhase { starting, ready, scanning, finishing, done, error }

/// Server-side heart-rate scan: opens the front camera, streams small JPEG
/// frames to the FastAPI backend (one request in flight, extra frames are
/// dropped), exposes the returned face box and the final bpm.
class HrScanController extends ChangeNotifier {
  HrScanController({HrApiClient? api}) : _api = api ?? HrApiClient();

  static const _frameGapMs = 1000 ~/ ScanApiConfig.targetFps - 6;
  static const _missesBeforeHint = 5;
  static const _maxExtensions = 2;
  static const _smoothing = 0.4;

  final HrApiClient _api;

  CameraController? camera;
  HrScanPhase phase = HrScanPhase.starting;
  String? errorMessage;
  double? hr;

  /// Smoothed face box in fractions of the upright, UNmirrored frame.
  Rect? box;
  bool faceHint = false;
  double progress = 0;
  double fps = 0;

  int _rotation = 0;
  String? _scanId;
  bool _disposed = false;
  bool _inFlight = false;
  bool _finishing = false;
  int _misses = 0;
  int _netFailures = 0;
  int _extensions = 0;
  int _targetMs = ScanApiConfig.scanSeconds * 1000;
  int _lastSentMs = -1000;
  int _sentCount = 0;
  Stopwatch _clock = Stopwatch();
  int _firstFrameAt = -1;

  /// Upright frame aspect (width / height) for laying out the preview.
  double get frameAspect {
    final c = camera;
    if (c == null || !c.value.isInitialized) return 3 / 4;
    final ar = c.value.aspectRatio;
    return ar > 1 ? 1 / ar : ar;
  }

  Future<void> init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return _fail('No camera found on this device.');
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cams.first);
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      _rotation = isIos ? 0 : front.sensorOrientation % 360;
      final c = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: isIos ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (_disposed) return c.dispose();
      camera = c;
      phase = HrScanPhase.ready;
      notifyListeners();
    } on CameraException catch (e) {
      final denied = e.code.contains('Access') || e.code.contains('Permission');
      _fail(denied
          ? 'Camera access is off. Allow it in Settings to scan.'
          : 'Could not open the camera (${e.code}).');
    } catch (e) {
      _fail('Could not open the camera: $e');
    }
  }

  Future<void> start() async {
    if (phase != HrScanPhase.ready && phase != HrScanPhase.error) return;
    final c = camera;
    if (c == null || !c.value.isInitialized) return;
    _resetRun();
    phase = HrScanPhase.scanning;
    errorMessage = null;
    notifyListeners();
    try {
      // Lock exposure/focus so auto-exposure doesn't add fake "pulses".
      try {
        await c.setExposureMode(ExposureMode.locked);
        await c.setFocusMode(FocusMode.locked);
      } catch (_) {}
      final s = await _api.startScan();
      if (_disposed) return;
      _scanId = s.scanId;
      await c.startImageStream(_onImage);
    } on ScanNetworkException catch (e) {
      _fail(e.message);
    } on ScanApiException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not start the scan: $e');
    }
  }

  void _resetRun() {
    _scanId = null;
    hr = null;
    box = null;
    faceHint = false;
    progress = 0;
    fps = 0;
    _misses = 0;
    _netFailures = 0;
    _extensions = 0;
    _targetMs = ScanApiConfig.scanSeconds * 1000;
    _lastSentMs = -1000;
    _sentCount = 0;
    _finishing = false;
    _inFlight = false;
    _firstFrameAt = -1;
    _clock = Stopwatch();
  }

  void _onImage(CameraImage img) {
    if (_disposed || phase != HrScanPhase.scanning || _inFlight) return;
    if (_firstFrameAt < 0) {
      _firstFrameAt = 0;
      _clock.start();
    }
    final t = _clock.elapsedMilliseconds;
    if (t - _lastSentMs < _frameGapMs && _sentCount > 0) return; // ~15 fps cap
    final id = _scanId;
    if (id == null) return;
    if (t >= _targetMs) {
      _finishScan();
      return;
    }
    _inFlight = true;
    _lastSentMs = t;
    _sendOne(id, img, t);
  }

  Future<void> _sendOne(String id, CameraImage img, int t) async {
    try {
      final jpg = await encodeCameraImage(img, _rotation);
      if (jpg == null || _disposed || phase != HrScanPhase.scanning) return;
      final st = await _api.sendFrame(id, t, jpg);
      if (_disposed || phase != HrScanPhase.scanning) return;
      _netFailures = 0;
      _sentCount++;
      fps = _sentCount * 1000 / (t == 0 ? 1 : t);
      _applyStatus(st);
    } on ScanApiException catch (e) {
      if (e.isExpired || ++_netFailures >= 5) _fail(e.message);
    } on ScanNetworkException catch (e) {
      if (++_netFailures >= 5) _fail(e.message); // a late/lost frame is just dropped
    } catch (e) {
      if (++_netFailures >= 5) _fail('Scan failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  void _applyStatus(FaceStatus st) {
    progress = (st.elapsedS / ScanApiConfig.scanSeconds).clamp(0.0, 1.0);
    final b = st.box?.rect;
    if (st.face && b != null) {
      _misses = 0;
      faceHint = false;
      final cur = box;
      box = cur == null
          ? b
          : Rect.fromLTWH(
              cur.left + (b.left - cur.left) * _smoothing,
              cur.top + (b.top - cur.top) * _smoothing,
              cur.width + (b.width - cur.width) * _smoothing,
              cur.height + (b.height - cur.height) * _smoothing);
    } else if (++_misses >= _missesBeforeHint) {
      faceHint = true;
      box = null;
    } // fewer misses: keep the last box
    notifyListeners();
  }

  Future<void> _finishScan() async {
    if (_finishing) return;
    _finishing = true;
    final id = _scanId;
    final c = camera;
    phase = HrScanPhase.finishing;
    notifyListeners();
    try {
      if (c?.value.isStreamingImages ?? false) await c!.stopImageStream();
      while (_inFlight && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (_disposed || id == null) return;
      final r = await _api.finish(id);
      if (_disposed) return;
      hr = r.hr;
      phase = HrScanPhase.done;
      notifyListeners();
    } on ScanApiException catch (e) {
      if (e.isTooShort && _extensions < _maxExtensions && !_disposed && c != null) {
        // The scan is kept server-side: collect 10 s more and ask again.
        _extensions++;
        _targetMs = _clock.elapsedMilliseconds + 10000;
        _finishing = false;
        phase = HrScanPhase.scanning;
        notifyListeners();
        try {
          await c.startImageStream(_onImage);
        } catch (e2) {
          _fail('Could not resume the camera: $e2');
        }
      } else {
        _fail(e.message);
      }
    } on ScanNetworkException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Scan failed: $e');
    }
  }

  Future<void> _stopStream() async {
    final c = camera;
    try {
      if (c?.value.isStreamingImages ?? false) await c!.stopImageStream();
    } catch (_) {}
  }

  void _fail(String message) {
    if (_disposed) return;
    errorMessage = message;
    phase = HrScanPhase.error;
    _stopStream();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true; // also drops the scan: the server expires it after 120 s
    final c = camera;
    camera = null;
    () async {
      try {
        if (c?.value.isStreamingImages ?? false) await c!.stopImageStream();
      } catch (_) {}
      await c?.dispose();
    }();
    _api.close();
    super.dispose();
  }
}
