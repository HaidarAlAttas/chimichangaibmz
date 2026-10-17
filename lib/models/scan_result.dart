/// Mirrors linuxone_server/schemas.py. Keep the two in sync.
library;

enum ScanStatus { queued, processing, done, rejected, failed }

enum PipelineStage { ingest, dsp, vitals, risk, reasoning, complete }

enum FlagLevel {
  noUrgentFlags('no_urgent_flags'),
  watch('watch'),
  seekAdvice('seek_advice');

  const FlagLevel(this.wire);
  final String wire;

  static FlagLevel parse(String? s) =>
      FlagLevel.values.firstWhere((v) => v.wire == s, orElse: () => FlagLevel.watch);
}

enum SignalQuality { good, fair }

T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

double _d(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;

class RangeBand {
  final double low;
  final double high;
  const RangeBand(this.low, this.high);

  factory RangeBand.fromJson(Map<String, dynamic>? j) =>
      RangeBand(_d(j?['low']), _d(j?['high']));

  bool contains(double v) => v >= low && v <= high;
}

class Vitals {
  final double heartRateBpm;
  final double respiratoryRateBpm;
  final RangeBand heartRateRange;
  final RangeBand respiratoryRateRange;
  final bool respiratoryRateExperimental;

  /// Always null for now: a phone camera can't measure SpO2 reliably.
  final double? spo2Pct;
  final String method;

  const Vitals({
    required this.heartRateBpm,
    required this.respiratoryRateBpm,
    required this.heartRateRange,
    required this.respiratoryRateRange,
    this.respiratoryRateExperimental = true,
    this.spo2Pct,
    required this.method,
  });

  factory Vitals.fromJson(Map<String, dynamic> j) => Vitals(
        heartRateBpm: _d(j['heart_rate_bpm']),
        respiratoryRateBpm: _d(j['respiratory_rate_bpm']),
        heartRateRange: RangeBand.fromJson(j['heart_rate_range'] as Map<String, dynamic>?),
        respiratoryRateRange:
            RangeBand.fromJson(j['respiratory_rate_range'] as Map<String, dynamic>?),
        respiratoryRateExperimental: j['respiratory_rate_experimental'] as bool? ?? true,
        spo2Pct: (j['spo2_pct'] as num?)?.toDouble(),
        method: j['method'] as String? ?? 'unknown',
      );
}

class News2Item {
  final String key;
  final String label;
  final double value;
  final String unit;
  final int points;

  const News2Item(this.key, this.label, this.value, this.unit, this.points);

  factory News2Item.fromJson(Map<String, dynamic> j) => News2Item(
        j['key'] as String? ?? '',
        j['label'] as String? ?? '',
        _d(j['value']),
        j['unit'] as String? ?? '',
        (j['points'] as num?)?.toInt() ?? 0,
      );
}

class Assessment {
  final FlagLevel level;
  final int partialNews2;
  final int checksUsed;
  final int checksTotal;
  final List<News2Item> items;
  final List<String> notChecked;

  const Assessment({
    required this.level,
    required this.partialNews2,
    required this.checksUsed,
    required this.checksTotal,
    required this.items,
    required this.notChecked,
  });

  factory Assessment.fromJson(Map<String, dynamic> j) => Assessment(
        level: FlagLevel.parse(j['level'] as String?),
        partialNews2: (j['partial_news2'] as num?)?.toInt() ?? 0,
        checksUsed: (j['checks_used'] as num?)?.toInt() ?? 0,
        checksTotal: (j['checks_total'] as num?)?.toInt() ?? 7,
        items: [
          for (final i in (j['items'] as List? ?? const []))
            News2Item.fromJson(i as Map<String, dynamic>)
        ],
        notChecked: [for (final s in (j['not_checked'] as List? ?? const [])) s.toString()],
      );
}

class Reasoning {
  final String summary;
  final List<String> factors;
  final String suggestion;
  final String disclaimer;
  final String method;

  const Reasoning({
    required this.summary,
    required this.factors,
    required this.suggestion,
    required this.disclaimer,
    required this.method,
  });

  bool get isGranite => method.startsWith('granite');

  factory Reasoning.fromJson(Map<String, dynamic> j) => Reasoning(
        summary: j['summary'] as String? ?? '',
        factors: [for (final s in (j['factors'] as List? ?? const [])) s.toString()],
        suggestion: j['suggestion'] as String? ?? '',
        disclaimer: j['disclaimer'] as String? ?? '',
        method: j['method'] as String? ?? 'template',
      );
}

class ScanResult {
  final double sqi;
  final SignalQuality quality;
  final Vitals vitals;
  final Assessment assessment;
  final Reasoning reasoning;

  /// True for sample data (demo mode or simulated capture). The UI must show
  /// a DEMO label whenever this is set.
  final bool isDemo;
  final DateTime receivedAt;

  ScanResult({
    required this.sqi,
    required this.quality,
    required this.vitals,
    required this.assessment,
    required this.reasoning,
    required this.isDemo,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        sqi: _d(j['sqi']),
        quality: _enum(SignalQuality.values, j['quality'] as String?, SignalQuality.fair),
        vitals: Vitals.fromJson(j['vitals'] as Map<String, dynamic>),
        assessment: Assessment.fromJson(j['assessment'] as Map<String, dynamic>),
        reasoning: Reasoning.fromJson(j['reasoning'] as Map<String, dynamic>),
        isDemo: j['is_demo'] as bool? ?? false,
      );
}

/// Why a scan produced no numbers. Reasons: motion, lighting, face_lost,
/// too_short, no_pulse.
class Rejection {
  final double sqi;
  final List<String> reasons;
  final String message;

  const Rejection({required this.sqi, required this.reasons, required this.message});

  factory Rejection.fromJson(Map<String, dynamic> j) => Rejection(
        sqi: _d(j['sqi']),
        reasons: [for (final s in (j['reasons'] as List? ?? const [])) s.toString()],
        message: j['message'] as String? ?? '',
      );
}

class ScanState {
  final String scanId;
  final ScanStatus status;
  final PipelineStage stage;
  final ScanResult? result;
  final Rejection? rejection;
  final String? error;

  const ScanState({
    required this.scanId,
    required this.status,
    required this.stage,
    this.result,
    this.rejection,
    this.error,
  });

  bool get isTerminal =>
      status == ScanStatus.done || status == ScanStatus.rejected || status == ScanStatus.failed;

  factory ScanState.fromJson(Map<String, dynamic> j) => ScanState(
        scanId: j['scan_id'] as String? ?? '',
        status: _enum(ScanStatus.values, j['status'] as String?, ScanStatus.failed),
        stage: _enum(PipelineStage.values, j['stage'] as String?, PipelineStage.ingest),
        result: j['result'] == null
            ? null
            : ScanResult.fromJson(j['result'] as Map<String, dynamic>),
        rejection: j['rejection'] == null
            ? null
            : Rejection.fromJson(j['rejection'] as Map<String, dynamic>),
        error: j['error'] as String?,
      );
}
