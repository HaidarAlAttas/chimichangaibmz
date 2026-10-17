import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../models/patient_input.dart';
import '../models/scan_result.dart';
import '../widgets/common.dart';
import 'scan_screen.dart';

/// Architecture box 3: the health dashboard, opened as a full-screen pop-up.
///
/// Per the architecture review: partial NEWS2 flags instead of a 0-100 score,
/// signal quality shown on its own (never as "confidence"), breathing marked
/// experimental, SpO2 a placeholder because a camera can't measure it.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.patient, required this.result});

  final PatientInput patient;
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final v = result.vitals;
    final a = result.assessment;
    final when = DateFormat('d MMM, HH:mm').format(result.receivedAt);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your results',
                      style: TextStyle(fontFamily: AppFonts.sans, fontSize: 24,
                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                  Text('$when · ${patient.sex.label}, ${patient.age}',
                      style: AppText.small.copyWith(fontSize: 14)),
                ]),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                style: IconButton.styleFrom(backgroundColor: AppColors.muted),
                icon: const Icon(Icons.close, color: AppColors.ink2, size: 20),
              ),
            ]),
            if (result.isDemo) ...[const SizedBox(height: 14), const DemoBanner()],
            const SizedBox(height: 18),
            _StatusCard(assessment: a),
            const SizedBox(height: 10),
            _QualityRow(result: result),
            const SizedBox(height: 16),
            _VitalCard(
              icon: Icons.favorite,
              color: const Color(0xFFD9474F),
              title: 'Heart rate',
              value: v.heartRateBpm,
              unit: 'bpm',
              band: v.heartRateRange,
              min: 35,
              max: 140,
              points: _points(a, 'heart_rate'),
            ),
            const SizedBox(height: 10),
            _VitalCard(
              icon: Icons.air,
              color: const Color(0xFF6E4BD8),
              title: 'Breathing rate',
              tag: v.respiratoryRateExperimental ? 'Experimental' : null,
              value: v.respiratoryRateBpm,
              unit: '/ min',
              band: v.respiratoryRateRange,
              min: 5,
              max: 30,
              points: _points(a, 'respiratory_rate'),
            ),
            const SizedBox(height: 10),
            const _OxygenPlaceholder(),
            const SizedBox(height: 16),
            _WhyCard(result: result),
            const SizedBox(height: 14),
            Text(result.reasoning.disclaimer, style: AppText.small.copyWith(fontSize: 12.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                flex: 5,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => ScanScreen(patient: patient))),
                  child: const Text('Scan again'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 7,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static int? _points(Assessment a, String key) {
    for (final i in a.items) {
      if (i.key == key) return i.points;
    }
    return null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.assessment});
  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    final (title, body, bg, line, ink, mark, icon) = switch (assessment.level) {
      FlagLevel.noUrgentFlags => (
          'No urgent flags',
          'Your heart rate and breathing are within the ranges used by NEWS2, a standard '
              'early-warning score.',
          AppColors.normalSoft,
          AppColors.normalLine,
          AppColors.normalInk,
          AppColors.normal,
          Icons.check,
        ),
      FlagLevel.watch => (
          'Worth a re-check',
          'At least one reading is outside the NEWS2 normal band. Rest and scan again.',
          AppColors.watchSoft,
          const Color(0xFFF2DE9C),
          const Color(0xFF5C4300),
          AppColors.watchFill,
          Icons.priority_high,
        ),
      FlagLevel.seekAdvice => (
          'Seek medical advice',
          'A reading is well outside the NEWS2 normal band. Contact a doctor, especially if '
              'you feel unwell.',
          AppColors.actSoft,
          const Color(0xFFF4C7CB),
          const Color(0xFF7A1119),
          AppColors.act,
          Icons.priority_high,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 26,
                    fontWeight: FontWeight.w600, color: ink)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body,
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, height: 1.45,
                color: ink.withValues(alpha: 0.85))),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: line),
        ),
        Row(children: [
          Text('Partial NEWS2 score',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                  color: ink.withValues(alpha: 0.85))),
          const Spacer(),
          Text('${assessment.partialNews2}',
              style: TextStyle(fontFamily: AppFonts.mono, fontSize: 17,
                  fontWeight: FontWeight.w500, color: ink)),
          Text('  ·  ${assessment.checksUsed} of ${assessment.checksTotal} checks',
              style: TextStyle(fontFamily: AppFonts.mono, fontSize: 13,
                  color: ink.withValues(alpha: 0.85))),
        ]),
      ]),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final good = result.quality == SignalQuality.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line)),
      child: Row(children: [
        SignalBars(
            lit: good ? 4 : 3,
            on: good ? AppColors.normal : AppColors.watchFill,
            off: AppColors.line),
        const SizedBox(width: 8),
        const Text('Signal quality', style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
            color: AppColors.ink)),
        const Spacer(),
        Text(good ? 'Good' : 'Fair',
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                fontWeight: FontWeight.w600, color: good ? AppColors.normal : AppColors.watch)),
      ]),
    );
  }
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.unit,
    required this.band,
    required this.min,
    required this.max,
    this.points,
    this.tag,
  });

  final IconData icon;
  final Color color;
  final String title;
  final double value;
  final String unit;
  final RangeBand band;
  final double min;
  final double max;
  final int? points;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final inBand = band.contains(value.roundToDouble());
    final pts = points ?? 0;
    final statusColor = pts == 0 ? AppColors.normal : pts >= 3 ? AppColors.act : AppColors.watch;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        Row(children: [
          IconTile(icon, color: color, background: color.withValues(alpha: 0.08), size: 30),
          const SizedBox(width: 10),
          Text(title, style: AppText.label),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Pill(label: tag!, foreground: AppColors.ink2, background: AppColors.paper,
                height: 22, fontSize: 11),
          ],
          const Spacer(),
          Text(value.toStringAsFixed(0), style: AppText.number),
          const SizedBox(width: 4),
          Text(unit, style: AppText.small),
        ]),
        const SizedBox(height: 12),
        RangeBar(min: min, max: max, bandLow: band.low, bandHigh: band.high, value: value),
        const SizedBox(height: 7),
        Row(children: [
          Text('NEWS2 0 points: ${band.low.toStringAsFixed(0)}–${band.high.toStringAsFixed(0)}',
              style: AppText.small.copyWith(fontSize: 12)),
          const Spacer(),
          Text(inBand ? 'In range' : '$pts point${pts == 1 ? '' : 's'}',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 12,
                  fontWeight: FontWeight.w500, color: statusColor)),
        ]),
      ]),
    );
  }
}

class _OxygenPlaceholder extends StatelessWidget {
  const _OxygenPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconTile(Icons.water_drop_outlined, color: AppColors.ink3,
                background: AppColors.muted, size: 30),
            const SizedBox(width: 10),
            Text('Blood oxygen', style: AppText.label.copyWith(color: AppColors.ink2)),
            const Spacer(),
            const Text('Not measured', style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                color: AppColors.ink3)),
          ]),
          const SizedBox(height: 8),
          const Text(
              "A phone camera can't measure oxygen reliably. Use a finger oximeter if you "
              'need this reading.',
              style: AppText.small),
        ]),
      );
}

class _WhyCard extends StatelessWidget {
  const _WhyCard({required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.reasoning;
    final a = result.assessment;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Why this result', style: AppText.title),
          const Spacer(),
          Pill(
            label: r.isGranite ? 'Granite 3' : (result.isDemo ? 'Sample' : 'Template'),
            foreground: r.isGranite ? AppColors.accentDark : AppColors.ink2,
            background: r.isGranite ? AppColors.accentSoft : AppColors.paper,
            height: 24,
            fontSize: 12,
          ),
        ]),
        const SizedBox(height: 10),
        Text(r.summary, style: AppText.body),
        const SizedBox(height: 16),
        const Eyebrow('What was checked'),
        const SizedBox(height: 6),
        for (final i in a.items)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(children: [
              Text(i.label, style: AppText.label.copyWith(fontWeight: FontWeight.w400,
                  fontSize: 14)),
              const Spacer(),
              Text('${i.value.toStringAsFixed(0)} ${i.unit}',
                  style: AppText.mono.copyWith(color: AppColors.ink2, fontSize: 13)),
              const SizedBox(width: 8),
              Pill(
                label: '${i.points} pt${i.points == 1 ? '' : 's'}',
                foreground: i.points == 0
                    ? AppColors.normal
                    : i.points >= 3
                        ? AppColors.act
                        : AppColors.watch,
                background: i.points == 0
                    ? AppColors.normalSoft
                    : i.points >= 3
                        ? AppColors.actSoft
                        : AppColors.watchSoft,
                height: 22,
                fontSize: 12,
              ),
            ]),
          ),
        if (a.notChecked.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Not checked: ${a.notChecked.map((s) => s.toLowerCase()).join(', ')}.',
              style: AppText.small),
        ],
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration:
              BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Suggestion',
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                    fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(r.suggestion, style: AppText.body.copyWith(fontSize: 14)),
          ]),
        ),
      ]),
    );
  }
}
