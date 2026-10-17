import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PulsePalApp());
}

class PulsePalApp extends StatelessWidget {
  const PulsePalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulsePal AI — LinuxONE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060B14),
        primaryColor: const Color(0xFF0043CE),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0043CE),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0F172A),
          background: Color(0xFF060B14),
        ),

        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
