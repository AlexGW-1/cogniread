class Book {
  const Book({
    required this.id,
    required this.title,
    required this.sourcePath,
    required this.fingerprint,
    this.author,
  });

  final String id;
  final String title;
  final String sourcePath; // where the EPUB was imported from
  final String fingerprint;
  final String? author;
}
