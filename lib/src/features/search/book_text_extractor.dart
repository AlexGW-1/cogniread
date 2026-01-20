import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/reader/presentation/reader_controller.dart';

class ExtractedChapter {
  const ExtractedChapter({
    required this.title,
    required this.href,
    required this.paragraphs,
  });

  final String title;
  final String href;
  final List<String> paragraphs;
}

abstract class BookTextExtractor {
  Future<List<ExtractedChapter>> extract(LibraryEntry entry);
}

class ReaderBookTextExtractor implements BookTextExtractor {
  ReaderBookTextExtractor({LibraryStore? store}) : _store = store ?? LibraryStore();

  final LibraryStore _store;

  @override
  Future<List<ExtractedChapter>> extract(LibraryEntry entry) async {
    final controller = ReaderController(store: _store, perfLogsEnabled: false);
    try {
      await controller.load(entry.id);
      if (controller.state != ReaderLoadState.content) {
        return const <ExtractedChapter>[];
      }
      final chapters = <ExtractedChapter>[];
      for (var i = 0; i < controller.chapters.length; i += 1) {
        final chapter = controller.chapters[i];
        final href = chapter.href ?? 'index:$i';
        chapters.add(
          ExtractedChapter(
            title: chapter.title,
            href: href,
            paragraphs: chapter.paragraphs,
          ),
        );
      }
      return chapters;
    } finally {
      controller.dispose();
    }
  }
}

