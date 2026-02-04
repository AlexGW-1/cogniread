import 'package:cogniread/src/features/search/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SearchIndexQuery.tokenize extracts unicode tokens', () {
    expect(
      SearchIndexQuery.tokenize('  Hello, мир!!  '),
      equals(<String>['hello', 'мир']),
    );
  });

  test('SearchIndexQuery.parse produces FTS match expression', () {
    final query = SearchIndexQuery.parse('foo bar');
    expect(query.toFtsMatchExpression(), equals('foo* AND bar*'));
  });

  test('SearchIndexQuery.parse ignores empty input', () {
    final query = SearchIndexQuery.parse('   ');
    expect(query.isEmpty, isTrue);
    expect(query.toFtsMatchExpression(), isEmpty);
  });
}

