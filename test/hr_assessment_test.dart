import 'package:chimichangaibmz/models/scan_result.dart';
import 'package:chimichangaibmz/services/hr_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NEWS2 pulse points match the 2017 chart', () {
    const cases = {40: 3, 41: 1, 50: 1, 51: 0, 90: 0, 91: 1, 110: 1, 111: 2, 130: 2, 131: 3};
    cases.forEach((bpm, pts) => expect(HrAssessment.heartRatePoints(bpm.toDouble()), pts,
        reason: '$bpm bpm'));
  });

  test('result built from the PulseNet heart rate', () {
    final ok = HrAssessment.fromHeartRate(72);
    expect(ok.assessment.level, FlagLevel.noUrgentFlags);
    expect(ok.assessment.checksUsed, 1);
    expect(ok.isDemo, isFalse);
    expect(HrAssessment.fromHeartRate(98).assessment.level, FlagLevel.watch);
    expect(HrAssessment.fromHeartRate(140).assessment.level, FlagLevel.seekAdvice);
  });
}
