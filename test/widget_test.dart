import 'package:flutter_test/flutter_test.dart';
import 'package:chimichangaibmz/main.dart';

void main() {
  testWidgets('PulsePal smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PulsePalApp());
    expect(find.text('PulsePal AI'), findsOneWidget);
  });
}
