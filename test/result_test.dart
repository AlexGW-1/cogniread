import 'package:cogniread/src/core/types/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ok holds value', () {
    const result = Ok<int>(42);
    expect(result, isA<Ok<int>>());
    expect(result.value, 42);
  });

  test('Err holds message', () {
    const result = Err<int>('boom');
    expect(result, isA<Err<int>>());
    expect(result.message, 'boom');
  });
}
