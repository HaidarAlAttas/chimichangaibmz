import 'package:flutter/foundation.dart';

enum ScanEnv { dev, prod }

/// Base URL of the FastAPI heart-rate backend (app.py, port 5000).
///
/// Change [env] or [prodBaseUrl] here, or override at run time without editing
/// code:  flutter run --dart-define=SCAN_API_URL=http://192.168.1.20:5000
///
/// Dev defaults by platform:
///   Android emulator            http://10.0.2.2:5000
///   Physical phone over USB     `adb reverse tcp:5000 tcp:5000`, then run with
///                               --dart-define=SCAN_API_URL=http://localhost:5000
///   Windows / iOS sim / web     http://localhost:5000
///
/// Plain http is for development only. Use https:// in production.
class ScanApiConfig {
  ScanApiConfig._();

  static const ScanEnv env = ScanEnv.dev;
  static const String prodBaseUrl = 'https://your-server.example.com';

  static const String _override = String.fromEnvironment('SCAN_API_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (env == ScanEnv.prod) return prodBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  static const Duration requestTimeout = Duration(seconds: 10);
  static const int scanSeconds = 30;
  static const int targetFps = 15;
  static const int jpegQuality = 90; // never below 85: the pulse is a tiny colour change
  static const int frameWidth = 480;
}
