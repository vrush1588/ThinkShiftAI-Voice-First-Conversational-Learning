import 'package:flutter_test/flutter_test.dart';

import 'package:thinkshift/main.dart';

void main() {
  testWidgets('ThinkShift shows the start button', (WidgetTester tester) async {
    await tester.pumpWidget(const ThinkShiftApp());

    expect(find.text('ThinkShift'), findsWidgets);
    expect(find.text('Start Voice Chat'), findsOneWidget);
  });
}
