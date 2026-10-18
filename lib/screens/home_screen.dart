import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app/theme.dart';
import '../config/api_config.dart';
import '../config/scan_api_config.dart';
import '../models/patient_input.dart';
import '../services/linuxone_api_service.dart';
import '../widgets/common.dart';
import 'hr_scan_screen.dart';
import 'settings_screen.dart';

/// Architecture step 1.1: patient input (age 18+, sex) and pre-scan tips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Server { checking, online, demo, offline }

class _HomeScreenState extends State<HomeScreen> {
  static const _minAge = 18;

  final _api = LinuxOneApiService();
  PatientInput _patient = const PatientInput(age: 28, sex: Sex.male);
  _Server _server = _Server.checking;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _checkServer() async {
    setState(() => _server = _Server.checking);
    // Any HTTP answer from the PulseNet backend (even 404 on '/') means it is up.
    var online = false;
    try {
      final res = await http
          .get(Uri.parse(ScanApiConfig.baseUrl))
          .timeout(const Duration(seconds: 4));
      online = res.statusCode < 500;
    } catch (_) {}
    final demo = await ApiConfig.isDemoMode();
    if (!mounted) return;
    setState(() => _server = online
        ? _Server.online
        : demo
            ? _Server.demo
            : _Server.offline);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    _checkServer();
  }

  void _setAge(int age) =>
      setState(() => _patient = _patient.copyWith(age: age.clamp(_minAge, PatientInput.maxAge)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Row(children: [
                  const PulseLogo(),
                  const SizedBox(width: 8),
                  const Text('PulsePal',
                      style: TextStyle(
                          fontFamily: AppFonts.sans, fontSize: 19, fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const Spacer(),
                  _serverChip(),
                ]),
                const SizedBox(height: 26),
                const Text('Check your vitals\nin 30 seconds', style: AppText.display),
                const SizedBox(height: 8),
                Text('Uses your front camera. No wearable needed.',
                    style: AppText.body.copyWith(fontSize: 16)),
                const SizedBox(height: 22),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Eyebrow('About you'),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Age', style: TextStyle(fontFamily: AppFonts.sans, fontSize: 16,
                          fontWeight: FontWeight.w500, color: AppColors.ink)),
                      const Spacer(),
                      _StepButton(
                          icon: Icons.remove,
                          label: 'Decrease age',
                          onTap: _patient.age > _minAge ? () => _setAge(_patient.age - 1) : null),
                      SizedBox(
                        width: 56,
                        child: Text('${_patient.age}',
                            textAlign: TextAlign.center, style: AppText.number),
                      ),
                      _StepButton(
                          icon: Icons.add,
                          label: 'Increase age',
                          onTap: _patient.age < PatientInput.maxAge
                              ? () => _setAge(_patient.age + 1)
                              : null),
                    ]),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: AppColors.line),
                    ),
                    const Text('Sex', style: TextStyle(fontFamily: AppFonts.sans, fontSize: 16,
                        fontWeight: FontWeight.w500, color: AppColors.ink)),
                    const SizedBox(height: 10),
                    _Segmented(
                      value: _patient.sex,
                      onChanged: (s) => setState(() => _patient = _patient.copyWith(sex: s)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                        'For adults 18 and over. Age and sex are used to read your results, '
                        'nothing else.',
                        style: AppText.small),
                  ]),
                ),
                const SizedBox(height: 14),
                const AppCard(
                  padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Eyebrow('Before you start'),
                    SizedBox(height: 6),
                    _Tip(Icons.wb_sunny_outlined, 'Face a window or bright light'),
                    _Tip(Icons.chair_outlined, 'Sit down and rest for a minute'),
                    _Tip(Icons.stay_current_portrait, 'Prop your phone up so it stays still',
                        last: true),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(children: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => HrScanScreen(patient: _patient))),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Start scan'),
              ),
              const SizedBox(height: 12),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.ink2),
                SizedBox(width: 6),
                Text('Frames go only to our LinuxONE server to measure your pulse.',
                    style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                        color: AppColors.ink2)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _serverChip() {
    switch (_server) {
      case _Server.checking:
        return Pill(
            label: 'Checking server…',
            foreground: AppColors.ink2,
            background: AppColors.muted,
            onTap: _openSettings);
      case _Server.online:
        return Pill(
            label: 'Server online',
            foreground: AppColors.normal,
            background: AppColors.normalSoft,
            dot: AppColors.normal,
            onTap: _openSettings);
      case _Server.demo:
        return Pill(
            label: 'Demo mode',
            foreground: AppColors.watch,
            background: AppColors.watchSoft,
            dot: AppColors.watchFill,
            onTap: _openSettings);
      case _Server.offline:
        return Pill(
            label: 'Server offline',
            foreground: AppColors.act,
            background: AppColors.actSoft,
            dot: AppColors.act,
            onTap: _openSettings);
    }
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon,
                  color: onTap == null ? AppColors.line : AppColors.ink2, size: 22),
            ),
          ),
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final Sex value;
  final ValueChanged<Sex> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration:
            BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final s in Sex.values)
            Expanded(
              child: Semantics(
                selected: s == value,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s == value ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: s == value
                          ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))]
                          : null,
                    ),
                    child: Text(s.label,
                        style: TextStyle(
                            fontFamily: AppFonts.sans,
                            fontSize: 15,
                            fontWeight: s == value ? FontWeight.w600 : FontWeight.w500,
                            color: s == value ? AppColors.ink : AppColors.ink2)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text, {this.last = false});
  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          IconTile(icon, color: AppColors.accent, background: AppColors.accentSoft),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppText.label.copyWith(fontWeight: FontWeight.w400))),
        ]),
      );
}
