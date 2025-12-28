class Book {
  const Book({
    required this.id,
    required this.title,
    required this.sourcePath,
    this.author,
  });

  final String id;
  final String title;
  final String sourcePath; // where the EPUB was imported from
  final String? author;
}
