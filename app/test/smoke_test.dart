import 'package:cogniread_app/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const CogniReadApp());
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('Library to Reader navigation', (tester) async {
    await tester.pumpWidget(const CogniReadApp());
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.text('Импортировать EPUB (заглушка)'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Imported book (stub)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Imported book (stub)'), findsOneWidget);
    expect(find.textContaining('Reader UI stub'), findsOneWidget);
  });
}
