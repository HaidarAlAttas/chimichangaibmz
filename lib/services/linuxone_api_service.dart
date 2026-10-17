import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/patient_input.dart';
import '../models/vital_results.dart';

/// ============================================================================
/// 🚀 LINUXONE API SERVICE
/// ============================================================================
/// This service handles the HTTPS/REST Egress (Step 1 -> Step 2 in Architecture).
/// 
/// It sends:
///   1. Patient metadata (Age, Sex, User ID)
///   2. Raw rPPG signal time-series extracted from the camera
///
/// To the IBM LinuxONE backend running FastAPI on s390x.
/// ============================================================================

class LinuxOneApiService {
  
  /// Ping the LinuxONE server health endpoint
  Future<bool> checkConnection() async {
    try {
      final baseUrl = await ApiConfig.getBaseUrl();
      final uri = Uri.parse('$baseUrl${ApiConfig.healthEndpoint}');
      
      developer.log("Connecting to LinuxONE health: $uri", name: "LinuxOneApi");
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      
      return response.statusCode == 200;
    } catch (e) {
      developer.log("LinuxONE health check failed: $e", name: "LinuxOneApi");
      return false;
    }
  }

  /// 🚨 MAIN LINUXONE INGESTION API CALL
  /// Sends the raw PPG frames (red channel intensity over time) + patient info.
  Future<VitalResults> analyzeRppgSignal({
    required PatientInput patient,
    required List<double> rawSignal,
  }) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final isMock = await ApiConfig.isMockModeEnabled();
    final uri = Uri.parse('$baseUrl${ApiConfig.analyzeEndpoint}');

    // Construct the payload matching the LinuxONE FastAPI schema
    final payload = {
      'user_id': patient.userId,
      'age': patient.age,
      'sex': patient.sex,
      'timestamp': patient.timestamp.toIso8601String(),
      'signal': rawSignal, // 450 floats for 15s @ 30fps
      'signal_length': rawSignal.length,
      'sampling_rate': 30, // 30 FPS video ingestion
    };

    developer.log("📡 Sending ${rawSignal.length} frames to LinuxONE ($uri)...", name: "LinuxOneApi");

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Optional: Add Auth / Enclave tokens here
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        developer.log("✅ LinuxONE inference received successfully!", name: "LinuxOneApi");
        return VitalResults.fromJson(data);
      } else {
        developer.log("⚠️ LinuxONE returned status ${response.statusCode}: ${response.body}", name: "LinuxOneApi");
        if (isMock) {
          return VitalResults.mock(age: patient.age, sex: patient.sex);
        }
        throw Exception("LinuxONE error: ${response.statusCode}");
      }
    } catch (e) {
      developer.log("❌ Could not connect to LinuxONE: $e", name: "LinuxOneApi");
      
      // If mock fallback is enabled, return realistic values so demo doesn't crash
      if (isMock) {
        developer.log("🔄 Fallback: Serving realistic local mock response for pitch presentation.", name: "LinuxOneApi");
        await Future.delayed(const Duration(milliseconds: 1200)); // Simulate network latency
        return VitalResults.mock(age: patient.age, sex: patient.sex);
      }
      rethrow;
    }
  }
}
