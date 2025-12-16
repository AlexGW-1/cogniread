import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../data/library_repository.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(libraryBooksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            onPressed: () {
              // TODO (1.3): file picker → импорт книги
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('TODO: Import book')),
              );
            },
            icon: const Icon(Icons.add),
            tooltip: 'Import',
          ),
        ],
      ),
      body: booksAsync.when(
        data: (books) {
          if (books.isEmpty) {
            return const Center(child: Text('No books yet. Tap + to import.'));
          }
          return ListView.separated(
            itemCount: books.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = books[i];
              return ListTile(
                title: Text(b.title),
                subtitle: Text(b.author ?? 'Unknown author'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('${AppRoutes.reader}/${b.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
