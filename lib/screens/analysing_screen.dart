import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/patient_input.dart';
import '../models/scan_result.dart';
import '../services/linuxone_api_service.dart';
import '../widgets/common.dart';
import 'results_screen.dart';
import 'retake_screen.dart';
import 'scan_screen.dart';

/// Uploads the scan and shows real pipeline progress from GET /scans/{id}.
class AnalysingScreen extends StatefulWidget {
  const AnalysingScreen({super.key, required this.patient, required this.upload});

  final PatientInput patient;
  final ScanUpload upload;

  @override
  State<AnalysingScreen> createState() => _AnalysingScreenState();
}

class _Step {
  final PipelineStage stage;
  final String title;
  final String tech;
  const _Step(this.stage, this.title, this.tech);
}

const _steps = [
  _Step(PipelineStage.ingest, 'Sent securely', 'POST /api/v1/scans · TLS'),
  _Step(PipelineStage.dsp, 'Cleaned the signal', 'detrend · POS · cardiac + breathing bands'),
  _Step(PipelineStage.vitals, 'Estimating heart rate and breathing', 'vitals model'),
  _Step(PipelineStage.risk, 'Checking early-warning flags', 'NEWS2 thresholds · adults'),
  _Step(PipelineStage.reasoning, 'Writing your summary', 'Granite 3 if available · else template'),
];

class _AnalysingScreenState extends State<AnalysingScreen> {
  final _api = LinuxOneApiService();
  StreamSubscription<ScanState>? _sub;
  PipelineStage _stage = PipelineStage.ingest;
  bool _uploaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _api.close();
    super.dispose();
  }

  void _run() {
    setState(() {
      _error = null;
      _uploaded = false;
      _stage = PipelineStage.ingest;
    });
    _sub?.cancel();
    _sub = _api.runScan(widget.upload).listen(
      (s) {
        if (!mounted) return;
        setState(() {
          _uploaded = true;
          _stage = s.stage;
        });
        if (s.status == ScanStatus.done && s.result != null) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ResultsScreen(patient: widget.patient, result: s.result!),
          ));
        } else if (s.status == ScanStatus.rejected) {
          final r = s.rejection;
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => RetakeScreen(
              patient: widget.patient,
              reasons: r?.reasons ?? const ['no_pulse'],
              sqi: r?.sqi ?? 0,
            ),
          ));
        } else if (s.status == ScanStatus.failed) {
          setState(() => _error = 'The server hit an error while analysing this scan.');
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = e is ApiException && e.statusCode == 401
            ? 'The server rejected the API key. Check it in Settings.'
            : e is ApiException
                ? e.toString()
                : 'Could not reach the LinuxONE server. Check your connection or turn on '
                    'demo mode in Settings.');
      },
    );
  }

  int _index(PipelineStage s) => switch (s) {
        PipelineStage.ingest => _uploaded ? 1 : 0,
        PipelineStage.dsp => 1,
        PipelineStage.vitals => 2,
        PipelineStage.risk => 3,
        PipelineStage.reasoning => 4,
        PipelineStage.complete => 5,
      };

  @override
  Widget build(BuildContext context) {
    final current = _index(_stage);
    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: _error == null ? AppColors.accentSoft : AppColors.actSoft,
                      borderRadius: BorderRadius.circular(20)),
                  child: Icon(_error == null ? Icons.monitor_heart_outlined : Icons.cloud_off,
                      color: _error == null ? AppColors.accent : AppColors.act, size: 32),
                ),
              ),
              const SizedBox(height: 20),
              Text(_error == null ? 'Analysing your scan' : "Couldn't finish the analysis",
                  style: AppText.display),
              const SizedBox(height: 6),
              Text(_error ?? 'Usually takes about 10 seconds.',
                  style: AppText.body.copyWith(fontSize: 16)),
              const SizedBox(height: 28),
              if (_error == null)
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Column(children: [
                    for (var i = 0; i < _steps.length; i++)
                      _StepRow(
                        step: _steps[i],
                        done: i < current,
                        active: i == current,
                        last: i == _steps.length - 1,
                      ),
                  ]),
                ),
              const Spacer(),
              if (_error != null) ...[
                FilledButton(onPressed: _run, child: const Text('Try again')),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                      builder: (_) => ScanScreen(patient: widget.patient))),
                  child: const Text('New scan'),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.muted, borderRadius: BorderRadius.circular(16)),
                  child: const Row(children: [
                    Icon(Icons.shield_outlined, color: AppColors.ink2, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Processed on IBM LinuxONE. Only colour data is sent; no face video '
                          'is stored.',
                          style: AppText.small),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow(
      {required this.step, required this.done, required this.active, required this.last});
  final _Step step;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final Widget dot = done
        ? Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 15, color: Colors.white))
        : active
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: AppColors.accent, backgroundColor: Color(0xFFD6E2FF)))
            : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line, width: 2)));
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          const SizedBox(height: 14),
          dot,
          if (!last)
            Expanded(
                child: Container(
                    width: 2, color: done ? AppColors.accent : AppColors.line)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title,
                  style: AppText.label.copyWith(
                      color: done || active ? AppColors.ink : AppColors.ink3, height: 1.3)),
              const SizedBox(height: 3),
              Text(step.tech, style: AppText.mono.copyWith(fontSize: 11.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}
