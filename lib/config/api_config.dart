import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// 🌐 LINUXONE API CONFIGURATION — HIGHLIGHTED CONNECTION POINT
/// ============================================================================
/// 
/// Set your LinuxONE backend instance IP / domain below.
/// You can also change this dynamically in the app via the Settings screen.
///
/// If your LinuxONE instance is running FastAPI:
///   Default port is typically 8000.
///   Example local network: http://192.168.1.100:8000
///   Example public LinuxONE: http://148.100.xx.xx:8000
/// ============================================================================

class ApiConfig {
  // 🚨 CHANGE THIS TO YOUR LINUXONE SERVER IP / HOSTNAME
  static const String defaultLinuxOneHost = "http://10.0.2.2:8000"; // 10.0.2.2 for Android Emulator, change to IP for real phone

  // API Endpoints on LinuxONE
  static const String analyzeEndpoint = "/api/v1/analyze";
  static const String healthEndpoint = "/api/v1/health";

  // Shared preferences key for dynamic IP configuration
  static const String _prefHostKey = "linuxone_api_host";
  static const String _prefMockModeKey = "linuxone_mock_mode";

  /// Gets the currently configured LinuxONE base URL
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefHostKey) ?? defaultLinuxOneHost;
  }

  /// Sets a new LinuxONE base URL
  static Future<void> setBaseUrl(String newHost) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHostKey, newHost.trim());
  }

  /// Whether to use simulated mock response when LinuxONE is unreachable
  static Future<bool> isMockModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefMockModeKey) ?? true; // Default true so hackathon demo never fails
  }

  /// Toggle mock fallback mode
  static Future<void> setMockMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefMockModeKey, enabled);
  }
}
