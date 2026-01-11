import 'dart:io';

import 'package:cogniread/src/features/sync/data/event_log_store.dart';
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
  late EventLogStore store;

  setUpAll(() async {
    originalPlatform = PathProviderPlatform.instance;
    supportDir = await Directory.systemTemp.createTemp('cogniread_event_log_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(supportDir.path);
    store = EventLogStore();
    await store.init();
    await store.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPlatform;
    await supportDir.delete(recursive: true);
  });

  test('addEvent preserves insertion order', () async {
    final base = DateTime(2026, 1, 12, 10, 0);
    final first = EventLogEntry(
      id: 'evt-1',
      entityType: 'note',
      entityId: 'note-1',
      op: 'add',
      payload: const <String, Object?>{'value': 'one'},
      createdAt: base,
    );
    final second = EventLogEntry(
      id: 'evt-2',
      entityType: 'note',
      entityId: 'note-2',
      op: 'update',
      payload: const <String, Object?>{'value': 'two'},
      createdAt: base.add(const Duration(seconds: 1)),
    );
    final third = EventLogEntry(
      id: 'evt-3',
      entityType: 'bookmark',
      entityId: 'book-1',
      op: 'toggle',
      payload: const <String, Object?>{'value': 'three'},
      createdAt: base.add(const Duration(seconds: 2)),
    );

    await store.addEvent(first);
    await store.addEvent(second);
    await store.addEvent(third);

    final all = store.listEvents();

    expect(all.map((entry) => entry.id), ['evt-1', 'evt-2', 'evt-3']);
  });

  test('listEvents respects limit', () async {
    final limited = store.listEvents(limit: 2);
    expect(limited.map((entry) => entry.id), ['evt-2', 'evt-3']);
  });
}
