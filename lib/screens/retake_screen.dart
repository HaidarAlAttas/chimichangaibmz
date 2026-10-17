import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../config/scan_spec.dart';
import '../models/patient_input.dart';
import '../widgets/common.dart';
import 'scan_screen.dart';

/// Shown when signal quality is too low. No numbers, no explanation:
/// just what went wrong and how to fix it.
class RetakeScreen extends StatelessWidget {
  const RetakeScreen({
    super.key,
    required this.patient,
    required this.reasons,
    required this.sqi,
    this.fromDevice = false,
  });

  final PatientInput patient;

  /// motion | lighting | face_lost | too_short | no_pulse
  final List<String> reasons;

  /// On-device share of good frames, or the server SQI.
  final double sqi;

  /// True when the phone's own gate stopped the upload.
  final bool fromDevice;

  static const _copy = <String, (IconData, String, String)>{
    'motion': (Icons.open_with, 'Too much movement',
        'Rest your phone on a table or against something, and keep your head still.'),
    'lighting': (Icons.wb_sunny_outlined, 'Light was uneven',
        'Face a window or lamp so your whole face is evenly lit.'),
    'face_lost': (Icons.face_outlined, 'Your face left the oval',
        'Keep your whole face inside the oval for the full 30 seconds.'),
    'too_short': (Icons.timer_outlined, 'The scan was too short',
        'Keep going until the ring around the oval is complete.'),
    'no_pulse': (Icons.monitor_heart_outlined, 'No clear pulse found',
        'Try brighter, steadier light and remove anything covering your forehead.'),
  };

  @override
  Widget build(BuildContext context) {
    final threshold = fromDevice ? ScanSpec.minDeviceSqi : 0.45;
    final items = [for (final r in reasons) if (_copy.containsKey(r)) _copy[r]!];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: AppColors.watchSoft, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.watch, size: 32),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("We couldn't get a\nclear reading", style: AppText.display),
                const SizedBox(height: 8),
                Text(
                    "We haven't shown any numbers because they wouldn't be reliable. "
                    'This usually takes one retry.',
                    style: AppText.body.copyWith(fontSize: 16)),
                const SizedBox(height: 22),
                if (items.isNotEmpty)
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    child: Column(children: [
                      for (var i = 0; i < items.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                              border: i == items.length - 1
                                  ? null
                                  : const Border(bottom: BorderSide(color: AppColors.line))),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            IconTile(items[i].$1, size: 34),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(items[i].$2, style: AppText.label.copyWith(
                                        fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(items[i].$3, style: AppText.body.copyWith(fontSize: 14)),
                                  ]),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                const SizedBox(height: 14),
                Row(children: [
                  const Text('Signal quality', style: AppText.small),
                  const Spacer(),
                  Text('${(sqi * 100).round()}%',
                      style: AppText.mono.copyWith(
                          color: AppColors.watch, fontWeight: FontWeight.w500)),
                  Text('  ·  needs ${(threshold * 100).round()}%+', style: AppText.mono),
                ]),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth;
                  return SizedBox(
                    height: 14,
                    child: Stack(children: [
                      Positioned(
                        left: 0, right: 0, top: 4,
                        child: Container(height: 6, decoration: BoxDecoration(
                            color: AppColors.line, borderRadius: BorderRadius.circular(3))),
                      ),
                      Positioned(
                        left: 0, top: 4, width: w * sqi.clamp(0.0, 1.0),
                        child: Container(height: 6, decoration: BoxDecoration(
                            color: AppColors.watchFill, borderRadius: BorderRadius.circular(3))),
                      ),
                      Positioned(
                        left: w * threshold - 1, top: 0,
                        child: Container(width: 2, height: 14, color: AppColors.ink3),
                      ),
                    ]),
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(children: [
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => ScanScreen(patient: patient))),
                child: const Text('Try again'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to start'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
