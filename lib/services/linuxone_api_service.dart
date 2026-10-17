import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/patient_input.dart';
import '../models/rgb_trace.dart';
import '../models/scan_result.dart';
import 'demo_data.dart';

/// The single API seam between the phone and the LinuxONE core.
///
///   POST /api/v1/scans        upload RGB traces  -> 202 {scan_id}
///   GET  /api/v1/scans/{id}   poll until done / rejected / failed
///
/// Contract: linuxone_server/schemas.py <-> lib/models/scan_result.dart.

class ScanUpload {
  final PatientInput patient;
  final RgbTrace trace;
  final double deviceSqi;
  final bool simulated;
  final String appVersion;

  const ScanUpload({
    required this.patient,
    required this.trace,
    required this.deviceSqi,
    required this.simulated,
    this.appVersion = '1.1.0',
  });

  Map<String, dynamic> toJson() => {
        'age': patient.age,
        'sex': patient.sex.apiValue,
        'fps': 30,
        'duration_s': double.parse(trace.durationSeconds.toStringAsFixed(2)),
        'traces': trace.toJson(),
        'device_sqi': double.parse(deviceSqi.toStringAsFixed(3)),
        'source': simulated ? 'simulated' : 'camera',
        'app_version': appVersion,
      };
}

class ServerInfo {
  final bool online;
  final String? arch;
  final String? apiVersion;
  final int? latencyMs;
  final String? error;

  const ServerInfo.online({this.arch, this.apiVersion, this.latencyMs})
      : online = true,
        error = null;

  const ServerInfo.offline(this.error)
      : online = false,
        arch = null,
        apiVersion = null,
        latencyMs = null;
}

/// The server answered with an error status (not a network failure).
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'Server error $statusCode: $message';
}

class LinuxOneApiService {
  LinuxOneApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final key = await ApiConfig.getApiKey();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
    };
  }

  Future<Uri> _uri(String path) async => Uri.parse('${await ApiConfig.getHost()}$path');

  Future<ServerInfo> checkHealth() async {
    final sw = Stopwatch()..start();
    try {
      final res = await _client
          .get(await _uri(ApiConfig.healthPath))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return ServerInfo.offline('HTTP ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return ServerInfo.online(
        arch: j['arch'] as String?,
        apiVersion: j['api_version'] as String?,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      return ServerInfo.offline(_describe(e));
    }
  }

  Future<String> submitScan(ScanUpload upload) async {
    final res = await _client
        .post(await _uri(ApiConfig.scansPath),
            headers: await _headers(), body: jsonEncode(upload.toJson()))
        .timeout(ApiConfig.requestTimeout);
    if (res.statusCode != 202 && res.statusCode != 200) {
      throw ApiException(res.statusCode, _detail(res.body));
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['scan_id'] as String;
  }

  Future<ScanState> getScan(String scanId) async {
    final res = await _client
        .get(await _uri('${ApiConfig.scansPath}/$scanId'), headers: await _headers())
        .timeout(ApiConfig.requestTimeout);
    if (res.statusCode != 200) throw ApiException(res.statusCode, _detail(res.body));
    return ScanState.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Uploads and polls, emitting each state until a terminal one.
  ///
  /// If the server can't be reached and demo mode is on, emits a scripted run
  /// ending in [DemoData.result] (isDemo = true). Server-side errors such as
  /// 401 or 422 are never masked by demo data.
  Stream<ScanState> runScan(ScanUpload upload) async* {
    String scanId;
    try {
      scanId = await submitScan(upload);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log('Upload failed: $e', name: 'LinuxOneApi');
      if (await ApiConfig.isDemoMode()) {
        yield* _demoRun();
        return;
      }
      throw Exception(_describe(e));
    }

    yield ScanState(scanId: scanId, status: ScanStatus.queued, stage: PipelineStage.ingest);
    final deadline = DateTime.now().add(ApiConfig.analysisTimeout);
    var networkErrors = 0;
    while (true) {
      await Future<void>.delayed(ApiConfig.pollInterval);
      try {
        final s = await getScan(scanId);
        networkErrors = 0;
        yield s;
        if (s.isTerminal) return;
      } on ApiException {
        rethrow;
      } catch (e) {
        if (++networkErrors >= 5) throw Exception(_describe(e));
      }
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('The server took too long to respond.');
      }
    }
  }

  Stream<ScanState> _demoRun() async* {
    const id = 'demo';
    for (final stage in [
      PipelineStage.ingest,
      PipelineStage.dsp,
      PipelineStage.vitals,
      PipelineStage.risk,
      PipelineStage.reasoning,
    ]) {
      yield ScanState(scanId: id, status: ScanStatus.processing, stage: stage);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    yield ScanState(
        scanId: id,
        status: ScanStatus.done,
        stage: PipelineStage.complete,
        result: DemoData.result());
  }

  static String _detail(String body) {
    try {
      final d = (jsonDecode(body) as Map<String, dynamic>)['detail'];
      return d is String ? d : jsonEncode(d);
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  static String _describe(Object e) {
    if (e is TimeoutException) return 'Timed out reaching the server';
    if (e is http.ClientException) return 'Could not reach the server';
    return e.toString();
  }

  void close() => _client.close();
}
