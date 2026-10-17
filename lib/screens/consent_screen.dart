import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../config/api_config.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Shown once before the first scan: adults only, what is collected, where it
/// goes, and that this is screening, not diagnosis (architecture review).
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _adult = false;
  bool _agree = false;

  Future<void> _continue() async {
    await ApiConfig.setConsent(true);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              children: [
                const Align(alignment: Alignment.centerLeft, child: PulseLogo(size: 40)),
                const SizedBox(height: 18),
                const Text('Before your first scan', style: AppText.display),
                const SizedBox(height: 18),
                const AppCard(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Column(children: [
                    _Point(Icons.info_outline, 'A screening check, not a diagnosis',
                        "It can miss problems. It doesn't replace a doctor."),
                    _Point(Icons.crop_square, 'What we collect',
                        'Your age, sex and the average colour of your forehead and cheeks. '
                            'Never photos or video.'),
                    _Point(Icons.swap_vert, 'Where it goes',
                        'Sent encrypted to our server on IBM LinuxONE to work out your result.',
                        last: true),
                  ]),
                ),
                const SizedBox(height: 16),
                _Tick(
                    value: _adult,
                    label: "I'm 18 or older",
                    onChanged: (v) => setState(() => _adult = v)),
                const SizedBox(height: 4),
                _Tick(
                    value: _agree,
                    label: 'I agree to my data being used this way',
                    onChanged: (v) => setState(() => _agree = v)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(children: [
              FilledButton(
                  onPressed: _adult && _agree ? _continue : null, child: const Text('Continue')),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => showPrivacyNotice(context),
                child: const Text('Read the full privacy notice'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.title, this.body, {this.last = false});
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(icon, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: AppFonts.sans, fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              const SizedBox(height: 3),
              Text(body, style: AppText.body.copyWith(fontSize: 14)),
            ]),
          ),
        ]),
      );
}

class _Tick extends StatelessWidget {
  const _Tick({required this.value, required this.label, required this.onChanged});
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(label, style: AppText.label.copyWith(fontWeight: FontWeight.w400)),
      );
}

/// Plain-language privacy notice. Have it reviewed against Malaysia's PDPA
/// before any real-world use.
Future<void> showPrivacyNotice(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: const [
            Text('Privacy notice', style: AppText.display),
            SizedBox(height: 16),
            _Para('What this app does',
                'PulsePal estimates heart rate and breathing rate from small colour changes '
                    'in your face, using your phone\'s front camera. It is a screening check for '
                    'adults, not a medical device, and it does not diagnose anything.'),
            _Para('What we collect',
                'Your age and sex, and one average colour value per video frame from three '
                    'small areas of your face (forehead and both cheeks). Video and photos stay '
                    'on your phone and are never stored or sent.'),
            _Para('Why',
                'Only to calculate and show your result. We do not sell your data or use it '
                    'for advertising.'),
            _Para('Where it goes',
                'The data is sent over an encrypted connection to our server on IBM LinuxONE, '
                    'which keeps your scan result and an audit log.'),
            _Para('Your choices',
                'You can stop at any time. To have your scan data deleted, contact the '
                    'project team.'),
          ],
        ),
      ),
    );

class _Para extends StatelessWidget {
  const _Para(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppText.title.copyWith(fontSize: 16)),
          const SizedBox(height: 4),
          Text(body, style: AppText.body),
        ]),
      );
}
