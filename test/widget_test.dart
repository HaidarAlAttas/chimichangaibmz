import 'package:chimichangaibmz/main.dart';
import 'package:chimichangaibmz/models/scan_result.dart';
import 'package:chimichangaibmz/screens/results_screen.dart';
import 'package:chimichangaibmz/models/patient_input.dart';
import 'package:chimichangaibmz/services/demo_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch shows consent and blocks Continue until both ticks',
      (tester) async {
    await tester.pumpWidget(const PulsePalApp(consented: false));
    expect(find.text('Before your first scan'), findsOneWidget);

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);

    await tester.tap(find.text("I'm 18 or older"));
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.tap(find.text('I agree to my data being used this way'));
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('demo results are labelled and never show an SpO2 number', (tester) async {
    // Tall surface so the whole (lazy) results list is built.
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ResultsScreen(
          patient: const PatientInput(age: 30, sex: Sex.female), result: DemoData.result()),
    ));
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.text('No urgent flags'), findsOneWidget);
    expect(find.text('Not measured'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('onfidence'), findsNothing);
  });

  test('parses the server contract', () {
    final s = ScanState.fromJson({
      'scan_id': 'abc',
      'status': 'done',
      'stage': 'complete',
      'result': {
        'sqi': 0.81,
        'quality': 'good',
        'vitals': {
          'heart_rate_bpm': 98.0,
          'respiratory_rate_bpm': 22.0,
          'heart_rate_range': {'low': 51, 'high': 90},
          'respiratory_rate_range': {'low': 12, 'high': 20},
          'respiratory_rate_experimental': true,
          'spo2_pct': null,
          'spo2_source': 'not_measured',
          'method': 'baseline-spectral',
        },
        'assessment': {
          'level': 'watch',
          'partial_news2': 3,
          'checks_used': 2,
          'checks_total': 7,
          'items': [
            {'key': 'heart_rate', 'label': 'Heart rate', 'value': 98, 'unit': 'bpm', 'points': 1},
            {'key': 'respiratory_rate', 'label': 'Breathing rate', 'value': 22, 'unit': '/min',
              'points': 2},
          ],
          'not_checked': ['Blood oxygen'],
          'method': 'news2-partial',
        },
        'reasoning': {
          'summary': 's', 'factors': ['f'], 'suggestion': 'x', 'disclaimer': 'd',
          'method': 'template',
        },
        'is_demo': false,
      },
    });
    expect(s.isTerminal, isTrue);
    expect(s.result!.assessment.level, FlagLevel.watch);
    expect(s.result!.assessment.items.last.points, 2);
    expect(s.result!.vitals.spo2Pct, isNull);
    expect(s.result!.isDemo, isFalse);
  });
}
