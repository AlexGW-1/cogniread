import 'package:cogniread/src/core/utils/message_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizeUserMessage masks url userinfo and query/fragment', () {
    const input =
        'Ошибка: http://user:pass@example.com/path?token=abc&x=1#frag';
    final output = sanitizeUserMessage(input);
    expect(output, contains('http://example.com/path'));
    expect(output, contains('token: ***'));
    expect(output, isNot(contains('user:pass')));
    expect(output, isNot(contains('abc')));
  });

  test('sanitizeUserMessage masks common secret fields and auth schemes', () {
    const input =
        'token=abc123 secret: xyz Authorization: Basic QWxhZGRpbjpvcGVu';
    final output = sanitizeUserMessage(input);
    expect(output, isNot(contains('abc123')));
    expect(output, isNot(contains('xyz')));
    expect(output, contains('token: ***'));
    expect(output, contains('secret: ***'));
    expect(output, contains('authorization: ***'));
  });
}
