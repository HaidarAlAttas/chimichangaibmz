import '../models/scan_result.dart';

/// Turns the heart rate from the LinuxONE PulseNet backend into the full
/// result shown on the dashboard: partial NEWS2 points (heart rate only, as
/// the camera scan gives no other vital), level, and a fixed-template
/// explanation. Same rules as linuxone_server/pipeline/risk.py.
class HrAssessment {
  HrAssessment._();

  static const RangeBand hrBand = RangeBand(51, 90); // NEWS2 0-point band
  static const RangeBand rrBand = RangeBand(12, 20);

  /// NEWS2 2017 pulse points.
  static int heartRatePoints(double bpm) {
    final v = bpm.round();
    if (v <= 40) return 3;
    if (v <= 50) return 1;
    if (v <= 90) return 0;
    if (v <= 110) return 1;
    if (v <= 130) return 2;
    return 3;
  }

  static const _suggestion = {
    FlagLevel.noUrgentFlags:
        "Re-check after resting if you've just exercised or had caffeine. Otherwise, no action needed.",
    FlagLevel.watch:
        "Rest for five minutes and scan again. If it's still flagged or you feel unwell, talk to a doctor.",
    FlagLevel.seekAdvice: 'Please contact a doctor or clinic soon, especially if you feel unwell.',
  };

  static ScanResult fromHeartRate(double bpm) {
    final pts = heartRatePoints(bpm);
    final level = pts == 3
        ? FlagLevel.seekAdvice
        : pts >= 1
            ? FlagLevel.watch
            : FlagLevel.noUrgentFlags;
    final hr = bpm.toStringAsFixed(0);
    final where = pts == 0 ? 'inside' : (bpm > hrBand.high ? 'above' : 'below');
    final summary = pts == 0
        ? 'Your heart rate ($hr bpm) is inside the NEWS2 normal band of 51-90 and scored 0 points, '
            'so nothing here needs urgent attention.'
        : 'Your heart rate ($hr bpm) is $where the NEWS2 normal band of 51-90 and scored '
            '$pts point${pts == 1 ? '' : 's'}.';

    return ScanResult(
      sqi: 1,
      quality: SignalQuality.good, // the backend rejects weak signals before returning a rate
      isDemo: false,
      vitals: Vitals(
        heartRateBpm: bpm,
        respiratoryRateBpm: 0,
        heartRateRange: hrBand,
        respiratoryRateRange: rrBand,
        method: 'pulsenet-linuxone',
      ),
      assessment: Assessment(
        level: level,
        partialNews2: pts,
        checksUsed: 1,
        checksTotal: 7,
        items: [News2Item('heart_rate', 'Heart rate', bpm, 'bpm', pts)],
        notChecked: const [
          'Breathing rate', 'Blood oxygen', 'Blood pressure', 'Temperature', 'Alertness',
          'Oxygen therapy'
        ],
      ),
      reasoning: Reasoning(
        summary: summary,
        factors: ['Heart rate: $pts point${pts == 1 ? '' : 's'}'],
        suggestion: _suggestion[level]!,
        disclaimer: 'This is a screening check from a phone camera, not a medical diagnosis, '
            'and it can miss problems. If you feel unwell, or have chest pain or trouble '
            'breathing, contact a doctor or emergency services.',
        method: 'template',
      ),
    );
  }
}
