import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/patient_input.dart';
import '../services/linuxone_api_service.dart';
import '../services/rppg_extractor_service.dart';
import '../widgets/camera_overlay_widget.dart';
import '../widgets/pulse_chart_widget.dart';
import '../widgets/health_dashboard_popup.dart';

class ScanScreen extends StatefulWidget {
  final PatientInput patient;

  const ScanScreen({super.key, required this.patient});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  final _rppgService = RppgExtractorService();
  final _apiService = LinuxOneApiService();

  bool _isCameraReady = false;
  bool _isScanning = false;
  bool _isAnalyzing = false;
  double _progress = 0.0;
  int _remainingSeconds = 15;
  Timer? _countdownTimer;

  final List<double> _recentSamples = [];
  StreamSubscription? _pulseSub;
  StreamSubscription? _progressSub;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _setupStreams();
  }

  void _setupStreams() {
    _pulseSub = _rppgService.livePulseStream.listen((sample) {
      if (!mounted) return;
      setState(() {
        _recentSamples.add(sample);
        if (_recentSamples.length > 50) {
          _recentSamples.removeAt(0);
        }
      });
    });

    _progressSub = _rppgService.progressStream.listen((prog) {
      if (!mounted) return;
      setState(() {
        _progress = prog;
      });
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        // No hardware camera found (e.g. simulator)
        setState(() => _isCameraReady = false);
        return;
      }

      // Prefer front-facing camera for facial rPPG
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      // Camera permissions or hardware unavailable
      setState(() => _isCameraReady = false);
    }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _isAnalyzing = false;
      _progress = 0.0;
      _remainingSeconds = 15;
      _recentSamples.clear();
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 1) {
          _remainingSeconds--;
        } else {
          timer.cancel();
        }
      });
    });

    if (_isCameraReady && _cameraController != null) {
      // Hardware camera stream
      _rppgService.startCapture(targetDurationSeconds: 15);
      _cameraController!.startImageStream((image) {
        _rppgService.processCameraImage(image);
        if (!_rppgService.isProcessing) {
          _cameraController?.stopImageStream();
          _onCaptureFinished(_rppgService.collectedSignal);
        }
      });
    } else {
      // Simulated rPPG generator (for Simulator or demo without webcam)
      _rppgService.startSimulatedCapture(
        targetDurationSeconds: 15,
        onComplete: (signal) {
          _onCaptureFinished(signal);
        },
      );
    }
  }

  Future<void> _onCaptureFinished(List<double> rawSignal) async {
    _countdownTimer?.cancel();
    setState(() {
      _isScanning = false;
      _isAnalyzing = true;
    });

    try {
      // Transmit to IBM LinuxONE (Step 1 -> Step 2)
      final results = await _apiService.analyzeRppgSignal(
        patient: widget.patient,
        rawSignal: rawSignal,
      );

      if (mounted) {
        setState(() => _isAnalyzing = false);
        // Display Pop-up Patient Health Dashboard (Step 3)
        HealthDashboardPopup.show(context, results);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Analysis failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseSub?.cancel();
    _progressSub?.cancel();
    _rppgService.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B14),
      body: Stack(
        children: [
          // Camera Preview or Dark Fallback
          Positioned.fill(
            child: _isCameraReady && _cameraController != null
                ? CameraPreview(_cameraController!)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF0F1E4A), Color(0xFF060B14)],
                        radius: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.face_retouching_natural, size: 100, color: const Color(0xFF38BDF8).withOpacity(0.4)),
                          const SizedBox(height: 16),
                          const Text(
                            "Facial rPPG Camera Simulation Mode",
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const Text(
                            "30 FPS Video Frames Ready",
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Alignment Overlay & Progress
          CameraOverlayWidget(
            progress: _progress,
            isScanning: _isScanning,
            remainingSeconds: _remainingSeconds,
          ),

          // Top Bar with Patient Info & Close Button
          Positioned(
            top: 48,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF38BDF8), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "${widget.patient.sex}, Age ${widget.patient.age}",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Controls & Live Pulse Waveform
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live Waveform Chart
                PulseChartWidget(recentSamples: _recentSamples),
                const SizedBox(height: 16),

                // Start / Stop Button
                if (!_isScanning && !_isAnalyzing)
                  ElevatedButton(
                    onPressed: _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0043CE),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 6,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, size: 22),
                        SizedBox(width: 8),
                        Text(
                          "START 15S VITALS SCAN",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Analyzing Loading Overlay
          if (_isAnalyzing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 20),
                      Text(
                        "Connecting to IBM LinuxONE...",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "1. Offloaded DSP Bandpass (0.7-3.5Hz) & SQI\n2. Telum AI CNN-LSTM Inference\n3. XGBoost Risk Stratification\n4. IBM Granite Clinical Synthesis",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
