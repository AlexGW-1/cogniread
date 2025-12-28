import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text(
          'Reader UI stub\n\nNext: render EPUB (pagination + TOC + highlights).',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
