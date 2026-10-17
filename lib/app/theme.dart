import 'package:flutter/material.dart';

/// Design tokens for PulsePal. Use these instead of hex codes in widgets.
class AppColors {
  AppColors._();

  static const ink = Color(0xFF15171C);
  static const ink2 = Color(0xFF525866);
  static const ink3 = Color(0xFF878C98);
  static const paper = Color(0xFFF5F4F0);
  static const card = Colors.white;
  static const line = Color(0xFFE5E2DA);
  static const muted = Color(0xFFECEAE4);

  static const accent = Color(0xFF0F62FE);
  static const accentDark = Color(0xFF0043CE);
  static const accentSoft = Color(0xFFEAF1FF);

  // Health status colours: use ONLY to communicate status.
  static const normal = Color(0xFF18794A);
  static const normalSoft = Color(0xFFE3F3E9);
  static const normalLine = Color(0xFFCBE8D5);
  static const normalInk = Color(0xFF0F4F2F);
  static const watch = Color(0xFF8A6400);
  static const watchFill = Color(0xFFC99A00);
  static const watchSoft = Color(0xFFFFF3CC);
  static const act = Color(0xFFC21E2B);
  static const actSoft = Color(0xFFFDECEC);

  // Camera screens
  static const camera = Color(0xFF0B0D12);
  static const cameraSheet = Color(0xDB14171E);
  static const cameraText2 = Color(0xFFA6ACB8);
  static const cameraOk = Color(0xFF7EE2A8);
  static const cameraAccent = Color(0xFF4589FF);
}

class AppFonts {
  AppFonts._();
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';
}

class AppText {
  AppText._();

  static const display = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 28, fontWeight: FontWeight.w600,
      height: 1.18, letterSpacing: -0.3, color: AppColors.ink);
  static const title = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const body = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 15, height: 1.45, color: AppColors.ink2);
  static const label = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink);
  static const small = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 13, height: 1.4, color: AppColors.ink3);
  static const eyebrow = TextStyle(
      fontFamily: AppFonts.sans, fontSize: 12, fontWeight: FontWeight.w600,
      letterSpacing: 0.7, color: AppColors.ink3);
  static const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 13, color: AppColors.ink3);
  static const number = TextStyle(
      fontFamily: AppFonts.mono, fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.ink);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppFonts.sans,
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.accent,
        surface: AppColors.paper,
        error: AppColors.act,
      ),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: AppFonts.sans, fontSize: 22, fontWeight: FontWeight.w600,
            color: AppColors.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF3A3F4A),
          disabledForegroundColor: const Color(0xFF9AA0AB),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: AppFonts.sans, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: AppFonts.sans, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink2,
          minimumSize: const Size.fromHeight(44),
          textStyle: const TextStyle(
              fontFamily: AppFonts.sans, fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.line),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
