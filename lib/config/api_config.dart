import 'package:shared_preferences/shared_preferences.dart';

/// Where the LinuxONE core lives, plus persisted user settings.
///
/// The server address can also be changed in the app (Settings), no rebuild.
/// Use https:// in production. Plain http:// only works on a dev network:
/// Android needs the cleartext flag in AndroidManifest.xml (already set for
/// demos) and iOS allows it only for local-network addresses.
class ApiConfig {
  ApiConfig._();

  /// 10.0.2.2 reaches the host machine from the Android emulator.
  static const String defaultHost = 'http://10.0.2.2:8000';

  static const String apiPrefix = '/api/v1';
  static const String healthPath = '$apiPrefix/health';
  static const String scansPath = '$apiPrefix/scans';

  static const Duration requestTimeout = Duration(seconds: 12);
  static const Duration pollInterval = Duration(milliseconds: 700);
  static const Duration analysisTimeout = Duration(seconds: 90);

  static const _kHost = 'linuxone_api_host';
  static const _kApiKey = 'linuxone_api_key';
  static const _kDemo = 'demo_mode';
  static const _kConsent = 'consent_v1_accepted';

  static Future<String> getHost() async =>
      (await SharedPreferences.getInstance()).getString(_kHost) ?? defaultHost;

  static Future<void> setHost(String host) async {
    var h = host.trim();
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    await (await SharedPreferences.getInstance()).setString(_kHost, h);
  }

  static Future<String> getApiKey() async =>
      (await SharedPreferences.getInstance()).getString(_kApiKey) ?? '';

  static Future<void> setApiKey(String key) async =>
      (await SharedPreferences.getInstance()).setString(_kApiKey, key.trim());

  /// Demo mode: when the server can't be reached, show sample results that are
  /// clearly marked DEMO. On by default so a venue Wi-Fi failure can't break
  /// the pitch.
  static Future<bool> isDemoMode() async =>
      (await SharedPreferences.getInstance()).getBool(_kDemo) ?? true;

  static Future<void> setDemoMode(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_kDemo, on);

  static Future<bool> hasConsent() async =>
      (await SharedPreferences.getInstance()).getBool(_kConsent) ?? false;

  static Future<void> setConsent(bool accepted) async =>
      (await SharedPreferences.getInstance()).setBool(_kConsent, accepted);
}
