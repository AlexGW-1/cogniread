import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/reader/presentation/reader_screen.dart';
import 'package:flutter/material.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<String> _books = <String>[];

  void _importStub() {
    // Next step: replace with File Picker + ImportEpub usecase.
    Log.d('Import EPUB pressed (stub).');
    setState(() {
      _books.add('Imported book (stub) — ${DateTime.now()}');
    });
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(title: _books[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: _books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Пока нет импортированных книг.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _importStub,
                      child: const Text('Импортировать EPUB (заглушка)'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _books.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                return ListTile(
                  title: Text(_books[i]),
                  onTap: () => _open(i),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importStub,
        child: const Icon(Icons.add),
      ),
    );
  }
}
