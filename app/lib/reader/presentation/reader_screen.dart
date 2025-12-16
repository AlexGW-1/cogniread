import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ReaderScreen extends StatelessWidget {
  final String bookId;

  const ReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reader: $bookId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Text(
          'Reader shell ready.\n\nNext (1.3): EPUB/PDF rendering + save reading position.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
