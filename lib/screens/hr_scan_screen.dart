import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../config/scan_api_config.dart';
import '../models/patient_input.dart';
import '../services/hr_assessment.dart';
import '../services/hr_scan/hr_scan_controller.dart';
import 'results_screen.dart';

/// Live heart-rate scan against the FastAPI backend: front camera, JPEG frames
/// to the server, face box drawn from each response, bpm at the end.
class HrScanScreen extends StatefulWidget {
  const HrScanScreen({super.key, this.patient = const PatientInput(age: 28, sex: Sex.male)});

  final PatientInput patient;

  @override
  State<HrScanScreen> createState() => _HrScanScreenState();
}

class _HrScanScreenState extends State<HrScanScreen> {
  final _c = HrScanController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.init();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose(); // stops the camera + stream and drops the scan
    super.dispose();
  }

  bool _shownResult = false;

  void _onChange() {
    if (!mounted) return;
    final hr = _c.hr;
    if (_c.phase == HrScanPhase.done && hr != null && !_shownResult) {
      _shownResult = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            ResultsScreen(patient: widget.patient, result: HrAssessment.fromHeartRate(hr)),
      ));
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.camera,
      body: Stack(fit: StackFit.expand, children: [
        _preview(),
        SafeArea(
          child: Column(children: [
            _topBar(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _sheet(),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _preview() {
    final cam = _c.camera;
    if (cam == null || !cam.value.isInitialized) {
      return const ColoredBox(color: AppColors.camera);
    }
    final w = MediaQuery.sizeOf(context).width;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: w,
          height: w / _c.frameAspect,
          // The overlay shares the preview's coordinate space, so box
          // fractions map straight onto it.
          child: Stack(fit: StackFit.expand, children: [
            CameraPreview(cam),
            if (_c.box != null && _c.phase == HrScanPhase.scanning)
              CustomPaint(painter: _BoxPainter(_c.box!)),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
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
            const Text('Heart-rate scan',
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 17,
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      );

  Widget _sheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cameraSheet,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: switch (_c.phase) {
        HrScanPhase.starting => _loading('Opening camera…'),
        HrScanPhase.ready => _readyBody(),
        HrScanPhase.scanning => _scanningBody(),
        HrScanPhase.finishing => _loading('Calculating your heart rate…'),
        HrScanPhase.done => _doneBody(),
        HrScanPhase.error => _errorBody(),
      },
    );
  }

  Widget _loading(String text) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
        const SizedBox(width: 14),
        Text(text, style: _body),
      ]);

  Widget _readyBody() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ready when you are', style: _title),
          const SizedBox(height: 8),
          Text(
              'Face the light, keep your face centred and sit still for '
              '${ScanApiConfig.scanSeconds} seconds.',
              style: _body),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _c.start, child: Text('Start ${ScanApiConfig.scanSeconds}-second scan')),
        ],
      );

  Widget _scanningBody() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('Scanning…', style: _title),
          const Spacer(),
          Text('${(_c.progress * ScanApiConfig.scanSeconds).round()} / ${ScanApiConfig.scanSeconds} s',
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13,
                  color: AppColors.cameraText2)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: _c.progress, minHeight: 6, color: AppColors.cameraAccent,
              backgroundColor: const Color(0x33FFFFFF)),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(14)),
          child: Text(
              _c.faceHint
                  ? 'Move your face into view and face the light'
                  : 'Breathe normally. Try not to talk or move.',
              style: _body.copyWith(
                  color: _c.faceHint ? const Color(0xFFFFD666) : const Color(0xFFD6DAE2))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.cameraText2),
          child: const Text('Cancel'),
        ),
      ]);

  Widget _doneBody() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            Text('${_c.hr?.round() ?? '--'}',
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 56,
                    fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(width: 8),
            const Text('bpm', style: _title),
          ]),
          const SizedBox(height: 6),
          const Text('Estimated from the camera. Screening aid only, not a diagnosis.',
              style: _body),
          const SizedBox(height: 16),
          FilledButton(onPressed: _c.start, child: const Text('Scan again')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.cameraText2),
            child: const Text('Done'),
          ),
        ],
      );

  Widget _errorBody() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Scan failed', style: _title),
          const SizedBox(height: 8),
          Text(_c.errorMessage ?? 'Something went wrong.', style: _body),
          const SizedBox(height: 16),
          FilledButton(
              // No camera at all (permission/hardware): retry means reopening it.
              onPressed: _c.camera == null ? _c.init : _c.start,
              child: const Text('Retry')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.cameraText2),
            child: const Text('Back'),
          ),
        ],
      );

  static const _title = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white);
  static const _body =
      TextStyle(fontFamily: AppFonts.sans, fontSize: 14, color: AppColors.cameraText2);
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.box);

  /// Fractions of the upright, unmirrored frame.
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    // The front-camera preview is mirrored on screen, the frames we send are
    // not: mirror x.
    final x = 1 - (box.left + box.width);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(x * size.width, box.top * size.height, box.width * size.width,
          box.height * size.height),
      const Radius.circular(12),
    );
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.cameraOk);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.box != box;
}
