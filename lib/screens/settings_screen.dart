import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../config/api_config.dart';
import '../services/linuxone_api_service.dart';
import '../widgets/common.dart';
import 'consent_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _host = TextEditingController();
  final _key = TextEditingController();
  final _api = LinuxOneApiService();
  bool _demo = true;
  bool _testing = false;
  ServerInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _key.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    final host = await ApiConfig.getHost();
    final key = await ApiConfig.getApiKey();
    final demo = await ApiConfig.isDemoMode();
    if (!mounted) return;
    setState(() {
      _host.text = host;
      _key.text = key;
      _demo = demo;
    });
  }

  Future<void> _save() async {
    await ApiConfig.setHost(_host.text);
    await ApiConfig.setApiKey(_key.text);
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _info = null;
    });
    await _save();
    final info = await _api.checkHealth();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _info = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 0, 8), child: Eyebrow('LinuxONE server')),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Server address', style: AppText.small),
                const SizedBox(height: 8),
                TextField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 15,
                      color: AppColors.ink),
                  decoration: const InputDecoration(hintText: 'https://your-linuxone-host:8443'),
                ),
                const SizedBox(height: 12),
                const Text('API key (optional)', style: AppText.small),
                const SizedBox(height: 8),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 15,
                      color: AppColors.ink),
                  decoration: const InputDecoration(hintText: 'Matches PULSEPAL_API_KEY'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: Text(_testing ? 'Testing…' : 'Test connection',
                      style: const TextStyle(fontSize: 15)),
                ),
                if (_info != null) ...[const SizedBox(height: 12), _result(_info!)],
                if (_host.text.startsWith('http://')) ...[
                  const SizedBox(height: 10),
                  const Text(
                      'Plain http:// is for local testing only. Use https:// for anything '
                      'outside your own network.',
                      style: AppText.small),
                ],
              ]),
            ),
            const Padding(
                padding: EdgeInsets.fromLTRB(4, 20, 0, 8), child: Eyebrow('Demo')),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(
                      child: Text('Demo mode',
                          style: TextStyle(fontFamily: AppFonts.sans, fontSize: 16,
                              fontWeight: FontWeight.w500, color: AppColors.ink))),
                  Switch(
                    value: _demo,
                    onChanged: (v) async {
                      setState(() => _demo = v);
                      await ApiConfig.setDemoMode(v);
                    },
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                    "If the server can't be reached, show sample results instead of an error. "
                    'Sample results are always marked',
                    style: AppText.body.copyWith(fontSize: 13.5)),
                const SizedBox(height: 8),
                const Pill(
                    label: 'DEMO',
                    foreground: AppColors.watch,
                    background: AppColors.watchSoft,
                    height: 24,
                    fontSize: 12),
              ]),
            ),
            const Padding(
                padding: EdgeInsets.fromLTRB(4, 20, 0, 8), child: Eyebrow('About')),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(children: [
                const _Kv('App version', '1.1.0'),
                _Kv('Privacy notice', '›', onTap: () => showPrivacyNotice(context)),
                _Kv('Withdraw consent', '›', last: true, onTap: _withdraw),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _withdraw() async {
    await ApiConfig.setConsent(false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ConsentScreen()), (_) => false);
  }

  Widget _result(ServerInfo i) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: i.online ? AppColors.normalSoft : AppColors.actSoft,
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: i.online ? AppColors.normal : AppColors.act, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i.online
                  ? 'Connected · ${i.arch ?? 'unknown arch'} · API ${i.apiVersion ?? '?'} · '
                      '${i.latencyMs} ms'
                  : 'Not reachable: ${i.error}',
              style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 13,
                  height: 1.45,
                  color: i.online ? AppColors.normalInk : const Color(0xFF7A1119)),
            ),
          ),
        ]),
      );
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.last = false, this.onTap});
  final String k;
  final String v;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(children: [
            Text(k, style: AppText.label.copyWith(fontWeight: FontWeight.w400)),
            const Spacer(),
            Text(v, style: AppText.mono.copyWith(fontSize: 15)),
          ]),
        ),
      );
}
