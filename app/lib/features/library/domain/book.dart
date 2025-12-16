class Book {
  final String id;
  final String title;
  final String? author;

  const Book({
    required this.id,
    required this.title,
    this.author,
  });
}
