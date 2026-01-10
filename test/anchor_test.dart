import 'package:cogniread/src/core/types/anchor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Anchor roundtrip without fragment', () {
    const anchor = Anchor(chapterHref: 'chapter1.xhtml', offset: 120);
    final encoded = anchor.toString();
    final parsed = Anchor.parse(encoded);

    expect(parsed, isNotNull);
    expect(parsed!.chapterHref, anchor.chapterHref);
    expect(parsed.offset, anchor.offset);
    expect(parsed.fragment, isNull);
  });

  test('Anchor roundtrip with fragment and escaping', () {
    const anchor = Anchor(
      chapterHref: r'chap|ter\name.xhtml',
      offset: 5,
      fragment: r'frag|ment\id',
    );
    final encoded = anchor.toString();
    final parsed = Anchor.parse(encoded);

    expect(encoded, r'chap\|ter\\name.xhtml|5|frag\|ment\\id');
    expect(parsed, isNotNull);
    expect(parsed!.chapterHref, anchor.chapterHref);
    expect(parsed.offset, anchor.offset);
    expect(parsed.fragment, anchor.fragment);
  });

  test('Anchor.parse rejects invalid inputs', () {
    expect(Anchor.parse(null), isNull);
    expect(Anchor.parse(''), isNull);
    expect(Anchor.parse('chapterOnly'), isNull);
    expect(Anchor.parse('chapter|'), isNull);
    expect(Anchor.parse('|10'), isNull);
    expect(Anchor.parse('chapter|-1'), isNull);
    expect(Anchor.parse('chapter|abc'), isNull);
    expect(Anchor.parse('a|1|b|c'), isNull);
    expect(Anchor.parse(r'chapter|10\'), isNull);
  });

  test('Anchor.isValid mirrors parse', () {
    expect(Anchor.isValid('chapter|0'), isTrue);
    expect(Anchor.isValid('chapter|abc'), isFalse);
  });
}
