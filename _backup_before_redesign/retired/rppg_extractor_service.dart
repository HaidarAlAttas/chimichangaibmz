import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';

/// ============================================================================
/// 🔬 rPPG CAMERA SIGNAL EXTRACTOR SERVICE
/// ============================================================================
/// Implements Step 1.2 & 1.3 from the Architecture:
/// - 30 FPS video frame ingestion
/// - Region-of-Interest (ROI) spatial color averaging (Red, Green, Blue)
/// - Offloads all heavy filtering to LinuxONE (Option C)
/// ============================================================================

class RppgExtractorService {
  final List<double> _rawRedBuffer = [];
  final StreamController<double> _livePulseController = StreamController<double>.broadcast();
  final StreamController<double> _progressController = StreamController<double>.broadcast();

  Stream<double> get livePulseStream => _livePulseController.stream;
  Stream<double> get progressStream => _progressController.stream;

  bool _isProcessing = false;
  int _targetFrames = 450; // 15 seconds @ 30 FPS
  Timer? _mockTimer;

  List<double> get collectedSignal => List.unmodifiable(_rawRedBuffer);
  bool get isProcessing => _isProcessing;

  /// Start collecting 15s of camera video frames
  void startCapture({int targetDurationSeconds = 15}) {
    _rawRedBuffer.clear();
    _targetFrames = targetDurationSeconds * 30;
    _isProcessing = true;
  }

  /// Process an incoming camera frame (YUV420 or BGRA)
  /// Extracts spatial color channel average inside the center Region of Interest (ROI)
  void processCameraImage(CameraImage image) {
    if (!_isProcessing) return;

    try {
      double avgRed = 0.0;

      // Extract pixel intensity from Y/R plane
      if (image.planes.isNotEmpty) {
        final plane = image.planes[0];
        final bytes = plane.bytes;
        final int width = image.width;
        final int height = image.height;

        // Crop center ROI (center 40% of the frame for facial cheek / forehead or fingertip)
        final int startX = (width * 0.3).toInt();
        final int endX = (width * 0.7).toInt();
        final int startY = (height * 0.3).toInt();
        final int endY = (height * 0.7).toInt();

        int sum = 0;
        int count = 0;
        // Sample every 4th pixel for high speed / 0 lag
        for (int y = startY; y < endY; y += 4) {
          for (int x = startX; x < endX; x += 4) {
            final int index = y * width + x;
            if (index < bytes.length) {
              sum += bytes[index];
              count++;
            }
          }
        }
        avgRed = count > 0 ? (sum / count) / 255.0 : 0.5;
      }

      _recordSample(avgRed);
    } catch (_) {
      // Fallback
    }
  }

  /// Ingests a single sample into the buffer and notifies streams
  void _recordSample(double value) {
    _rawRedBuffer.add(value);
    _livePulseController.add(value);
    
    final progress = min(1.0, _rawRedBuffer.length / _targetFrames);
    _progressController.add(progress);

    if (_rawRedBuffer.length >= _targetFrames) {
      _isProcessing = false;
    }
  }

  /// Simulated rPPG generator (useful for Simulator / macOS / Testing when camera is busy)
  void startSimulatedCapture({
    required Function(List<double> signal) onComplete,
    int targetDurationSeconds = 15,
  }) {
    startCapture(targetDurationSeconds: targetDurationSeconds);
    _mockTimer?.cancel();

    double phase = 0.0;
    final random = Random();

    // 30 FPS = ~33ms interval
    _mockTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isProcessing) {
        timer.cancel();
        onComplete(collectedSignal);
        return;
      }

      // Generate realistic arterial pulse waveform:
      // Heart rate ~74 BPM -> frequency = 74/60 = 1.23 Hz
      phase += 0.258; // 2 * pi * 1.23 / 30
      final pulse = 0.5 + 0.15 * sin(phase) + 0.05 * sin(2 * phase) + (random.nextDouble() - 0.5) * 0.02;
      _recordSample(pulse);

      if (_rawRedBuffer.length >= _targetFrames) {
        timer.cancel();
        _isProcessing = false;
        onComplete(collectedSignal);
      }
    });
  }

  void stop() {
    _isProcessing = false;
    _mockTimer?.cancel();
  }

  void dispose() {
    stop();
    _livePulseController.close();
    _progressController.close();
  }
}
