import 'dart:convert';

import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

String _wrapFb2(String body) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<FictionBook>
  <description>
    <title-info>
      $body
    </title-info>
  </description>
</FictionBook>
''';
}

void main() {
  test('fb2 metadata reads title and author from title-info', () {
    final xml = _wrapFb2('''
<book-title>Test Title</book-title>
<author>
  <first-name>Иван</first-name>
  <last-name>Петров</last-name>
</author>
''');
    final metadata = readFb2MetadataForTest(utf8.encode(xml), 'Fallback');

    expect(metadata.title, 'Test Title');
    expect(metadata.author, 'Иван Петров');
  });

  test('fb2 metadata falls back when title missing', () {
    final xml = _wrapFb2('<author><last-name>Solo</last-name></author>');
    final metadata = readFb2MetadataForTest(utf8.encode(xml), 'Fallback');

    expect(metadata.title, 'Fallback');
    expect(metadata.author, 'Solo');
  });

  test('fb2 cover extracts base64 binary', () {
    final bytes = <int>[1, 2, 3, 4];
    final xml = _wrapFb2('''
<coverpage>
  <image href="#cover.jpg"/>
</coverpage>
<binary id="cover.jpg" content-type="image/jpeg">${base64.encode(bytes)}</binary>
''');

    final cover = readFb2CoverForTest(utf8.encode(xml));

    expect(cover, isNotNull);
    expect(cover!.extension, '.jpg');
    expect(cover.bytes, bytes);
  });
}
