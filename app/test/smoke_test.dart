import 'package:cogniread_app/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const CogniReadApp());
    expect(find.text('Library'), findsOneWidget);
  });
}
