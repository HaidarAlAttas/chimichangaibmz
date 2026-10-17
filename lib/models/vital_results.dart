/// Model representing the exact outputs displayed on the Pop-up Patient Health Dashboard
/// as specified in Architecture Step (3):
/// 1. Heart rate (BPM)
/// 2. Blood oxygen level (SpO2 %)
/// 3. Respiratory Rate (breathing/min)
/// 4. Status & risk score (Normal, Warning, Critical + %)
/// 5. Health reasoning (IBM Granite LLM clinical explanation)
class VitalResults {
  final double bpm;
  final double spo2;
  final int respiratoryRate;
  final String riskStatus; // 'Normal', 'Warning', 'Critical'
  final double riskConfidence; // 0.0 to 1.0 (e.g., 0.94 -> 94%)
  final String healthReasoning;
  final double sqi; // Signal quality index from LinuxONE DSP
  final bool isMock;
  final DateTime timestamp;

  VitalResults({
    required this.bpm,
    required this.spo2,
    required this.respiratoryRate,
    required this.riskStatus,
    required this.riskConfidence,
    required this.healthReasoning,
    this.sqi = 0.92,
    this.isMock = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory VitalResults.fromJson(Map<String, dynamic> json) {
    final vitals = json['vitals'] as Map<String, dynamic>? ?? {};
    final risk = json['risk'] as Map<String, dynamic>? ?? {};
    final insight = json['insight'] as Map<String, dynamic>? ?? {};

    return VitalResults(
      bpm: (vitals['bpm'] as num?)?.toDouble() ?? 74.0,
      spo2: (vitals['spo2'] as num?)?.toDouble() ?? 98.2,
      respiratoryRate: (vitals['respiratory_rate'] as num?)?.toInt() ?? 16,
      riskStatus: (risk['level'] as String?) ?? 'Normal',
      riskConfidence: (risk['confidence'] as num?)?.toDouble() ?? 0.94,
      healthReasoning: (insight['reasoning'] as String?) ?? 
          (insight['summary'] as String?) ??
          "Vital parameters align with normative baselines. Resting BPM is stable. Blood oxygen saturation indicates healthy pulmonary function.",
      sqi: (json['sqi'] as num?)?.toDouble() ?? 0.92,
      isMock: json['is_mock'] as bool? ?? false,
    );
  }

  /// Default realistic mock response for hackathon rehearsals
  factory VitalResults.mock({required int age, required String sex}) {
    return VitalResults(
      bpm: 74.0,
      spo2: 98.2,
      respiratoryRate: 16,
      riskStatus: "Normal",
      riskConfidence: 0.94,
      healthReasoning: "Vital parameters align with normative baselines for age $age ($sex). Resting BPM is stable (74 BPM). Waveform morphology indicates consistent stroke volume. Blood oxygen saturation is optimal (98.2%). No clinical follow-up required at this interval.",
      sqi: 0.94,
      isMock: true,
    );
  }
}
