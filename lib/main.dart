import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/theme.dart';
import 'config/api_config.dart';
import 'screens/consent_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final consented = await ApiConfig.hasConsent();
  runApp(PulsePalApp(consented: consented));
}

class PulsePalApp extends StatelessWidget {
  const PulsePalApp({super.key, this.consented = false});

  final bool consented;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PulsePal',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: consented ? const HomeScreen() : const ConsentScreen(),
      );
}
