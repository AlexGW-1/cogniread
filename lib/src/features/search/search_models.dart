enum SearchHitType {
  note,
  highlight,
}

class SearchHit {
  const SearchHit({
    required this.type,
    required this.bookId,
    required this.markId,
    required this.snippet,
    this.anchor,
  });

  final SearchHitType type;
  final String bookId;
  final String markId;
  final String snippet;
  final String? anchor;
}

class BookTextHit {
  const BookTextHit({
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.chapterTitle,
    required this.snippet,
    required this.anchor,
    required this.chapterHref,
    required this.chapterIndex,
    required this.paragraphIndex,
  });

  final String bookId;
  final String bookTitle;
  final String bookAuthor;
  final String chapterTitle;
  final String snippet;
  final String anchor;
  final String chapterHref;
  final int chapterIndex;
  final int paragraphIndex;
}

class SearchIndexStatus {
  const SearchIndexStatus({
    required this.schemaVersion,
    this.lastRebuildAt,
    this.lastRebuildMs,
    this.marksRows,
    this.booksRows,
    this.lastError,
    this.dbPath,
  });

  final int schemaVersion;
  final DateTime? lastRebuildAt;
  final int? lastRebuildMs;
  final int? marksRows;
  final int? booksRows;
  final String? lastError;
  final String? dbPath;
}

class SearchIndexQuery {
  const SearchIndexQuery._(this.tokens);

  final List<String> tokens;

  static SearchIndexQuery parse(String raw) {
    final tokens = tokenize(raw);
    return SearchIndexQuery._(tokens);
  }

  static List<String> tokenize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    final tokens = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(trimmed.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.isNotEmpty)
        .toList();
    return tokens;
  }

  bool get isEmpty => tokens.isEmpty;

  String toFtsMatchExpression() {
    if (tokens.isEmpty) {
      return '';
    }
    return tokens.map((token) => '${_escapeToken(token)}*').join(' AND ');
  }

  static String _escapeToken(String token) {
    return token.replaceAll("'", "''");
  }
}
