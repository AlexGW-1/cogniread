import 'dart:io';

import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPlatform;
  late Directory supportDir;
  late LibraryStore store;

  setUpAll(() async {
    originalPlatform = PathProviderPlatform.instance;
    supportDir = await Directory.systemTemp.createTemp('cogniread_notes_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(supportDir.path);
    store = LibraryStore();
    await store.init();
    await store.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPlatform;
    await supportDir.delete(recursive: true);
  });

  test('addNote persists note data', () async {
    final entry = LibraryEntry(
      id: 'book-1',
      title: 'Title',
      author: 'Author',
      localPath: '/tmp/book.epub',
      coverPath: null,
      addedAt: DateTime(2026, 1, 11),
      fingerprint: 'hash',
      sourcePath: '/tmp/book.epub',
      readingPosition: const ReadingPosition(
        chapterHref: null,
        anchor: null,
        offset: null,
        updatedAt: null,
      ),
      progress: const ReadingProgress(
        percent: null,
        chapterIndex: null,
        totalChapters: null,
        updatedAt: null,
      ),
      lastOpenedAt: null,
      notes: const <Note>[],
      highlights: const <Highlight>[],
      bookmarks: const <Bookmark>[],
      tocOfficial: const <TocNode>[],
      tocGenerated: const <TocNode>[],
      tocMode: TocMode.official,
    );
    await store.upsert(entry);

    final note = Note(
      id: 'note-1',
      bookId: entry.id,
      anchor: 'chapter|10',
      endOffset: 24,
      excerpt: 'Some text',
      noteText: 'My note',
      color: 'pink',
      createdAt: DateTime(2026, 1, 11, 10),
      updatedAt: DateTime(2026, 1, 11, 10, 1),
    );

    await store.addNote(entry.id, note);
    final updated = await store.getById(entry.id);

    expect(updated, isNotNull);
    expect(updated!.notes.length, 1);
    final stored = updated.notes.first;
    expect(stored.id, note.id);
    expect(stored.bookId, note.bookId);
    expect(stored.anchor, note.anchor);
    expect(stored.endOffset, note.endOffset);
    expect(stored.excerpt, note.excerpt);
    expect(stored.noteText, note.noteText);
    expect(stored.color, note.color);
    expect(stored.createdAt, note.createdAt);
    expect(stored.updatedAt, note.updatedAt);
  });
}
