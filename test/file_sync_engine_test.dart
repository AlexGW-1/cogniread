import 'dart:io';

import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:cogniread/src/features/sync/file_sync/file_sync_engine.dart';
import 'package:cogniread/src/features/sync/file_sync/mock_sync_adapter.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_file_models.dart';
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
  late LibraryStore libraryStore;
  late EventLogStore eventLogStore;

  setUpAll(() async {
    originalPlatform = PathProviderPlatform.instance;
    supportDir = await Directory.systemTemp.createTemp('cogniread_sync_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(supportDir.path);
    libraryStore = LibraryStore();
    eventLogStore = EventLogStore();
    await libraryStore.init();
    await eventLogStore.init();
    await libraryStore.clear();
    await eventLogStore.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPlatform;
    await supportDir.delete(recursive: true);
  });

  test('sync merges remote events and remains idempotent', () async {
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
    await libraryStore.upsert(entry);

    final note = Note(
      id: 'note-1',
      bookId: entry.id,
      anchor: 'chapter|10',
      endOffset: 20,
      excerpt: 'Some text',
      noteText: 'Remote note',
      color: 'yellow',
      createdAt: DateTime(2026, 1, 12, 10),
      updatedAt: DateTime(2026, 1, 12, 10, 1),
    );
    final remoteEvent = EventLogEntry(
      id: 'evt-remote-1',
      entityType: 'note',
      entityId: note.id,
      op: 'add',
      payload: note.toMap(),
      createdAt: DateTime(2026, 1, 12, 10, 1),
    );
    final eventLogFile = SyncEventLogFile(
      schemaVersion: 1,
      deviceId: 'device-remote',
      generatedAt: DateTime(2026, 1, 12, 10, 2),
      cursor: remoteEvent.id,
      events: <EventLogEntry>[remoteEvent],
    );

    final adapter = MockSyncAdapter();
    adapter.seedFile('event_log.json', eventLogFile.toJsonBytes());

    final engine = FileSyncEngine(
      adapter: adapter,
      libraryStore: libraryStore,
      eventLogStore: eventLogStore,
      deviceId: 'device-local',
    );

    final first = await engine.sync();
    final updated = await libraryStore.getById(entry.id);
    expect(updated, isNotNull);
    expect(updated!.notes.length, 1);
    expect(updated.notes.first.noteText, 'Remote note');
    expect(eventLogStore.listEvents().length, 1);
    expect(first.appliedEvents, 1);

    final second = await engine.sync();
    final updatedSecond = await libraryStore.getById(entry.id);
    expect(updatedSecond, isNotNull);
    expect(updatedSecond!.notes.length, 1);
    expect(eventLogStore.listEvents().length, 1);
    expect(second.appliedEvents, 0);
  });
}
