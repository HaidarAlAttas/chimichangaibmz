import '../models/scan_result.dart';

/// Sample result used only in demo mode. Always flagged isDemo so the UI shows
/// the DEMO label; never presented as the user's own reading.
class DemoData {
  DemoData._();

  static ScanResult result() => ScanResult(
        sqi: 0.9,
        quality: SignalQuality.good,
        isDemo: true,
        vitals: const Vitals(
          heartRateBpm: 74,
          respiratoryRateBpm: 16,
          heartRateRange: RangeBand(51, 90),
          respiratoryRateRange: RangeBand(12, 20),
          method: 'demo',
        ),
        assessment: const Assessment(
          level: FlagLevel.noUrgentFlags,
          partialNews2: 0,
          checksUsed: 2,
          checksTotal: 7,
          items: [
            News2Item('heart_rate', 'Heart rate', 74, 'bpm', 0),
            News2Item('respiratory_rate', 'Breathing rate', 16, '/min', 0),
          ],
          notChecked: [
            'Blood oxygen', 'Blood pressure', 'Temperature', 'Alertness', 'Oxygen therapy'
          ],
        ),
        reasoning: const Reasoning(
          summary: 'Sample result: the server could not be reached, so these are example '
              'numbers, not your reading.',
          factors: ['Heart rate: 0 points', 'Breathing rate: 0 points'],
          suggestion: 'Connect to the LinuxONE server and scan again for a real result.',
          disclaimer: 'This is sample data for demonstration only. It is not a measurement '
              'of you and not a medical diagnosis.',
          method: 'demo',
        ),
      );
}
