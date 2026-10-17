import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/patient_input.dart';
import '../services/capture/capture_controller.dart';
import '../services/capture/quality_gate.dart';
import '../services/linuxone_api_service.dart';
import '../widgets/common.dart';
import '../widgets/face_guide_overlay.dart';
import '../widgets/pulse_trace.dart';
import 'analysing_screen.dart';
import 'retake_screen.dart';

/// Steps 1.2-1.4: position + quality gate, then the 30 s recording.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.patient, this.forceSimulated = false});

  final PatientInput patient;
  final bool forceSimulated;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final CaptureController _c = CaptureController(forceSimulated: widget.forceSimulated);
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.start();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_c.phase == CapturePhase.finished && !_handedOff) {
      _handedOff = true;
      final o = _c.outcome!;
      final route = o.passedGate
          ? MaterialPageRoute<void>(
              builder: (_) => AnalysingScreen(
                    patient: widget.patient,
                    upload: ScanUpload(
                      patient: widget.patient,
                      trace: o.trace,
                      deviceSqi: o.deviceSqi,
                      simulated: o.simulated,
                    ),
                  ))
          : MaterialPageRoute<void>(
              builder: (_) => RetakeScreen(
                    patient: widget.patient,
                    reasons: o.failureReasons.isEmpty ? const ['motion'] : o.failureReasons,
                    sqi: o.deviceSqi,
                    fromDevice: true,
                  ));
      Navigator.of(context).pushReplacement(route);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recording = _c.phase == CapturePhase.recording;
    return Scaffold(
      backgroundColor: AppColors.camera,
      body: Stack(fit: StackFit.expand, children: [
        _preview(),
        if (_c.phase != CapturePhase.error)
          FaceGuideOverlay(
            frameAspect: _c.frameAspect,
            recording: recording,
            progress: _c.progress,
            showRois: recording,
          ),
        if (recording) _countdown(context),
        SafeArea(
          child: Column(children: [
            _topBar(recording),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _sheet(recording),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _preview() {
    final cam = _c.camera;
    if (cam != null && cam.value.isInitialized) {
      // Scale the preview to COVER the screen. FaceGuideOverlay uses the same
      // maths (FrameToScreen), so the oval sits on the sampled pixels.
      final w = MediaQuery.sizeOf(context).width;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: w, height: w / _c.frameAspect, child: CameraPreview(cam)),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [Color(0xFF2A2F3A), Color(0xFF12151C), AppColors.camera],
          stops: [0, 0.55, 1],
        ),
      ),
      child: _c.simulated
          ? const Align(
              alignment: Alignment(0, -0.18),
              child: Icon(Icons.face_outlined, size: 120, color: Color(0x33FFFFFF)),
            )
          : null,
    );
  }

  Widget _countdown(BuildContext context) {
    final oval = FaceGuideOverlay.ovalRect(MediaQuery.sizeOf(context), _c.frameAspect);
    return Positioned(
      left: 0,
      right: 0,
      top: oval.bottom + 14,
      child: Column(children: [
        Text('${_c.secondsLeft}',
            style: const TextStyle(
                fontFamily: AppFonts.mono, fontSize: 44, fontWeight: FontWeight.w500,
                color: Colors.white)),
        const Text('seconds left',
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                color: AppColors.cameraText2)),
      ]),
    );
  }

  Widget _topBar(bool recording) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(backgroundColor: const Color(0x24FFFFFF)),
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
            if (recording)
              Pill(
                label: 'Recording · 0:${_c.secondsLeft.toString().padLeft(2, '0')} left',
                foreground: Colors.white,
                background: const Color(0x1FFFFFFF),
                dot: const Color(0xFFFF4D5A),
                height: 34,
                fontSize: 14,
              )
            else
              const Text('Position your face',
                  style: TextStyle(fontFamily: AppFonts.sans, fontSize: 17,
                      fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      );

  Widget _sheet(bool recording) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cameraSheet,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: switch (_c.phase) {
        CapturePhase.error => _errorBody(),
        CapturePhase.recording => _recordingBody(),
        _ => _gateBody(),
      },
    );
  }

  Widget _gateBody() {
    final g = _c.gate;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      Row(children: [
        const Text('Getting ready',
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 18,
                fontWeight: FontWeight.w600, color: Colors.white)),
        const Spacer(),
        Text('${g.passed} of 3',
            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13,
                color: AppColors.cameraText2)),
      ]),
      if (_c.simulated) ...[
        const SizedBox(height: 10),
        const Text('No camera found. Using a simulated signal; results will be marked DEMO.',
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13, color: Color(0xFFFFD666))),
      ],
      const SizedBox(height: 14),
      _GateRow('Lighting', g.lighting),
      const SizedBox(height: 10),
      _GateRow('Face', g.face),
      const SizedBox(height: 10),
      _GateRow('Movement', g.movement),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: g.ready ? _c.beginRecording : null,
        child: Text(g.ready ? 'Start 30-second scan' : 'Waiting for checks'),
      ),
    ]);
  }

  Widget _recordingBody() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('Live pulse signal',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                  color: AppColors.cameraText2)),
          const Spacer(),
          SignalBars(lit: _c.liveBars, on: _barColor(), off: const Color(0x33FFFFFF)),
          const SizedBox(width: 6),
          Text(_signalLabel(),
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13, color: _barColor())),
        ]),
        const SizedBox(height: 10),
        PulseTrace(green: _c.liveGreen),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF9DB8FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _c.gate.allOk ? 'Breathe normally. Try not to talk or move.' : _hint(),
                style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                    color: Color(0xFFD6DAE2)),
              ),
            ),
          ]),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.cameraText2),
          child: const Text('Cancel'),
        ),
      ]);

  Widget _errorBody() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        const Text("Can't use the camera",
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 18,
                fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 8),
        Text(_c.errorMessage ?? 'Something went wrong starting the camera.',
            style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                color: AppColors.cameraText2)),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
              builder: (_) => ScanScreen(patient: widget.patient, forceSimulated: true))),
          style: TextButton.styleFrom(foregroundColor: AppColors.cameraText2),
          child: const Text('Use a simulated signal (demo)'),
        ),
      ]);

  String _hint() {
    final g = _c.gate;
    if (!g.face.ok) return '${g.face.message}. Keep your face inside the oval.';
    if (!g.lighting.ok) return '${g.lighting.message}. Face a steady light.';
    return 'Hold still.';
  }

  Color _barColor() => _c.liveBars >= 3
      ? AppColors.cameraOk
      : _c.liveBars == 2
          ? const Color(0xFFFFD666)
          : const Color(0xFFFF8A8A);

  String _signalLabel() =>
      _c.liveBars >= 3 ? 'Signal good' : _c.liveBars == 2 ? 'Signal fair' : 'Signal weak';
}

class _GateRow extends StatelessWidget {
  const _GateRow(this.title, this.check);
  final String title;
  final Check check;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (check.state) {
      CheckState.ok => Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: Color(0xFF1F8A52), shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 16, color: Colors.white)),
      CheckState.fail => Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: Color(0xFF8A2A31), shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 16, color: Colors.white)),
      CheckState.pending => const SizedBox(
          width: 28,
          height: 28,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
          )),
    };
    final color = switch (check.state) {
      CheckState.ok => AppColors.cameraOk,
      CheckState.fail => const Color(0xFFFF8A8A),
      CheckState.pending => AppColors.cameraText2,
    };
    return Semantics(
      label: '$title: ${check.message}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          icon,
          const SizedBox(width: 12),
          Text(title,
              style: const TextStyle(fontFamily: AppFonts.sans, fontSize: 15,
                  fontWeight: FontWeight.w500, color: Colors.white)),
          const Spacer(),
          Text(check.message,
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, color: color)),
        ]),
      ),
    );
  }
}
