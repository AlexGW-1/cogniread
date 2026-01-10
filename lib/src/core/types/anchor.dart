class Anchor {
  const Anchor({
    required this.chapterHref,
    required this.offset,
    this.fragment,
  });

  final String chapterHref;
  final int offset;
  final String? fragment;

  static Anchor? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parts = _split(raw);
    if (parts == null || parts.length < 2 || parts.length > 3) {
      return null;
    }
    final chapter = _unescape(parts[0]);
    if (chapter.isEmpty) {
      return null;
    }
    final offsetRaw = parts[1];
    final offset = int.tryParse(offsetRaw);
    if (offset == null || offset < 0) {
      return null;
    }
    String? fragment;
    if (parts.length == 3) {
      final rawFragment = _unescape(parts[2]);
      fragment = rawFragment.isEmpty ? null : rawFragment;
    }
    return Anchor(
      chapterHref: chapter,
      offset: offset,
      fragment: fragment,
    );
  }

  static bool isValid(String? raw) => parse(raw) != null;

  @override
  String toString() {
    final encodedChapter = _escape(chapterHref);
    final encodedOffset = offset.toString();
    if (fragment == null || fragment!.isEmpty) {
      return '$encodedChapter|$encodedOffset';
    }
    final encodedFragment = _escape(fragment!);
    return '$encodedChapter|$encodedOffset|$encodedFragment';
  }

  static List<String>? _split(String input) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        buffer.write(char);
        continue;
      }
      if (char == '|') {
        parts.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    if (escaped) {
      return null;
    }
    parts.add(buffer.toString());
    return parts;
  }

  static String _escape(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (char == '|' || char == r'\') {
        buffer.write(r'\');
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  static String _unescape(String input) {
    final buffer = StringBuffer();
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}
