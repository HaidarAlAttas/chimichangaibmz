import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../config/scan_spec.dart';
import '../../models/rgb_trace.dart';
import 'face_detector_service.dart';
import 'frame_reader.dart';
import 'quality_gate.dart';

enum CapturePhase { starting, positioning, recording, finished, error }

/// Outcome of a 30 s capture, handed to the analysing or retake screen.
class CaptureOutcome {
  final RgbTrace trace;
  final double deviceSqi;
  final List<String> failureReasons;
  final bool simulated;
  const CaptureOutcome(this.trace, this.deviceSqi, this.failureReasons, this.simulated);

  bool get passedGate => deviceSqi >= ScanSpec.minDeviceSqi && trace.durationSeconds >= 10;
}

/// Architecture steps 1.2-1.4: camera capture, rPPG extraction (fixed ROIs ->
/// mean RGB per frame) and the on-device quality gate.
///
/// Falls back to a simulated signal when no camera is available (desktop,
/// simulator) or when the caller asks for it. Simulated scans are always
/// marked as demo data downstream.
class CaptureController extends ChangeNotifier {
  CaptureController({this.forceSimulated = false});

  final bool forceSimulated;

  CameraController? camera;
  CapturePhase phase = CapturePhase.starting;
  String? errorMessage;
  bool simulated = false;

  GateSnapshot gate = const GateSnapshot(
    Check(CheckState.pending, 'Checking…'),
    Check(CheckState.pending, 'Looking…'),
    Check(CheckState.pending, 'Waiting…'),
    false,
  );
  int liveBars = 0;
  double progress = 0;
  int secondsLeft = ScanSpec.durationSeconds;
  CaptureOutcome? outcome;

  /// Recent green-channel values for the live pulse trace (detrended in UI).
  final ListQueue<double> liveGreen = ListQueue<double>();

  final _clock = Stopwatch();
  late QualityGate _gate;
  FaceDetectorService? _faces;
  RecordingQuality? _quality;
  final List<RgbSample> _samples = [];
  int _recordStartMs = 0;
  int _frameCount = 0;
  int _rotation = 0;
  Timer? _simTimer;
  bool _disposed = false;

  /// Upright frame aspect (width / height) for laying out the overlay.
  double get frameAspect {
    final c = camera;
    if (c == null || !c.value.isInitialized) return 3 / 4;
    final ar = c.value.aspectRatio; // landscape w/h
    return ar > 1 ? 1 / ar : ar;
  }

  Future<void> start() async {
    _clock.start();
    if (!forceSimulated) {
      try {
        final cams = await availableCameras();
        if (cams.isNotEmpty) {
          await _startCamera(cams);
          return;
        }
      } on CameraException catch (e) {
        if (e.code.contains('Access') || e.code.contains('Permission')) {
          _fail('Camera access is off. Allow it in Settings to scan.');
          return;
        }
      } catch (_) {
        // No camera plugin on this platform: fall through to simulation.
      }
    }
    _startSimulation();
  }

  Future<void> _startCamera(List<CameraDescription> cams) async {
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    // iOS buffers arrive upright in portrait; Android needs the sensor angle.
    _rotation = isIos ? 0 : front.sensorOrientation % 360;

    final c = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: isIos ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );
    await c.initialize();
    if (_disposed) {
      await c.dispose();
      return;
    }
    camera = c;
    _faces = FaceDetectorService();
    _gate = QualityGate(faceDetectionAvailable: _faces!.available);
    phase = CapturePhase.positioning;
    notifyListeners();
    await c.startImageStream(_onImage);
  }

  void _onImage(CameraImage img) {
    if (_disposed) return;
    final frame = _toFrame(img);
    if (frame == null) return;
    final t = _clock.elapsedMilliseconds;

    final rgb = meanRgb(frame, ScanSpec.roisInFrame);
    if (rgb == null) return;

    // Face detection on every 4th frame is plenty for the gate.
    if (_frameCount++ % 4 == 0) {
      final pending = _faces?.detect(frame, t);
      pending?.then((obs) => _gate.addFace(obs, t)).catchError((_) {});
    }
    _onSample(rgb.r, rgb.g, rgb.b, t);
  }

  Frame? _toFrame(CameraImage img) {
    final planes = [
      for (final p in img.planes) FramePlane(p.bytes, p.bytesPerRow, p.bytesPerPixel ?? 1)
    ];
    final PixelLayout layout;
    if (img.format.group == ImageFormatGroup.bgra8888) {
      layout = PixelLayout.bgra8888;
    } else if (planes.length == 1) {
      layout = PixelLayout.nv21;
    } else if (planes.length >= 3) {
      layout = PixelLayout.yuv420;
    } else {
      return null;
    }
    return Frame(
        width: img.width, height: img.height, layout: layout, planes: planes, rotation: _rotation);
  }

  void _onSample(double r, double g, double b, int t) {
    final brightness = (r + g + b) / 3;
    gate = _gate.update(brightness, t);

    liveGreen.add(g);
    while (liveGreen.length > 150) {
      liveGreen.removeFirst();
    }

    if (phase == CapturePhase.recording) {
      _samples.add(RgbSample(t, r, g, b));
      _quality!.add(gate);
      liveBars = _quality!.liveBars;
      final elapsed = t - _recordStartMs;
      progress = (elapsed / (ScanSpec.durationSeconds * 1000)).clamp(0.0, 1.0);
      secondsLeft = math.max(0, ScanSpec.durationSeconds - elapsed ~/ 1000);
      if (elapsed >= ScanSpec.durationSeconds * 1000) {
        _finish();
        return;
      }
    }
    notifyListeners();
  }

  /// Called from the Start button once [gate.ready] is true.
  Future<void> beginRecording() async {
    if (phase != CapturePhase.positioning) return;
    // Review: lock exposure/focus so auto-exposure doesn't add fake "pulses".
    final c = camera;
    if (c != null) {
      try {
        await c.setExposureMode(ExposureMode.locked);
        await c.setFocusMode(FocusMode.locked);
      } catch (_) {
        // Not supported on every device; the DSP tolerates slow drift.
      }
    }
    _samples.clear();
    _quality = RecordingQuality();
    _recordStartMs = _clock.elapsedMilliseconds;
    progress = 0;
    secondsLeft = ScanSpec.durationSeconds;
    phase = CapturePhase.recording;
    notifyListeners();
  }

  Future<void> _finish() async {
    if (phase != CapturePhase.recording) return;
    phase = CapturePhase.finished;
    _simTimer?.cancel();
    final q = _quality!;
    outcome = CaptureOutcome(RgbTrace(List.of(_samples)), q.deviceSqi, q.reasons, simulated);
    notifyListeners();
    try {
      if (camera?.value.isStreamingImages ?? false) await camera!.stopImageStream();
    } catch (_) {}
  }

  void _fail(String message) {
    errorMessage = message;
    phase = CapturePhase.error;
    notifyListeners();
  }

  // --- Simulation -----------------------------------------------------------

  void _startSimulation() {
    simulated = true;
    _gate = QualityGate(faceDetectionAvailable: true);
    phase = CapturePhase.positioning;
    notifyListeners();

    final rnd = math.Random();
    const bpm = 72.0, brpm = 15.0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_disposed) return;
      final t = _clock.elapsedMilliseconds;
      final s = t / 1000.0;
      // Scripted gate: face appears after 0.8 s, already centred and still.
      if (t > 800) {
        _gate.addFace(
            FaceObservation(ScanSpec.faceBox.deflate(0.005 * math.sin(s)), t), t);
      }
      final pulse = math.sin(2 * math.pi * bpm / 60 * s) +
          0.3 * math.sin(4 * math.pi * bpm / 60 * s + 0.7);
      final breath = math.sin(2 * math.pi * brpm / 60 * s);
      double ch(double base, double amp) =>
          base * (1 + amp * pulse + 0.003 * breath) + (rnd.nextDouble() - 0.5) * 0.4;
      _onSample(ch(150, 0.0015), ch(110, 0.004), ch(90, 0.002), t);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _simTimer?.cancel();
    final c = camera;
    camera = null;
    () async {
      try {
        if (c?.value.isStreamingImages ?? false) await c!.stopImageStream();
      } catch (_) {}
      await c?.dispose();
      await _faces?.dispose();
    }();
    super.dispose();
  }
}
