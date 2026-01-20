import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/data/event_log_store.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FreeNote {
  const FreeNote({
    required this.id,
    required this.text,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String text;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'text': text,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static FreeNote fromMap(Map<String, Object?> map) {
    final createdAt = _parseDate(map['createdAt']);
    final updatedAt = _parseDate(map['updatedAt'], fallback: createdAt);
    return FreeNote(
      id: map['id'] as String? ?? '',
      text: map['text'] as String? ?? '',
      color: map['color'] as String? ?? 'yellow',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class FreeNotesStore {
  static const String _boxName = 'free_notes';

  Box<dynamic>? _box;
  final EventLogStore _eventStore = EventLogStore();

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
    await _eventStore.init();
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('FreeNotesStore not initialized');
    }
    return box;
  }

  ValueListenable<Box<dynamic>> listenable() => _requireBox.listenable();

  Future<List<FreeNote>> loadAll() async {
    final box = _requireBox;
    return box.values
        .whereType<Map<Object?, Object?>>()
        .map((value) => FreeNote.fromMap(_coerceMap(value)))
        .toList();
  }

  Future<FreeNote?> getById(String id) async {
    final value = _requireBox.get(id);
    if (value == null) {
      return null;
    }
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return FreeNote.fromMap(_coerceMap(value));
  }

  Future<void> upsert(FreeNote note) async {
    await _requireBox.put(note.id, note.toMap());
  }

  Future<void> removeRaw(String id) async {
    await _requireBox.delete(id);
  }

  Future<void> add(FreeNote note) async {
    await upsert(note);
    await _logEvent(
      entityId: note.id,
      op: 'add',
      payload: note.toMap(),
    );
  }

  Future<void> update(FreeNote note) async {
    await upsert(note);
    await _logEvent(
      entityId: note.id,
      op: 'update',
      payload: note.toMap(),
    );
  }

  Future<void> remove(String id) async {
    await _requireBox.delete(id);
    await _logEvent(
      entityId: id,
      op: 'delete',
      payload: <String, Object?>{'id': id},
    );
  }

  Future<void> clear() async {
    await _requireBox.clear();
  }

  Future<void> _logEvent({
    required String entityId,
    required String op,
    required Map<String, Object?> payload,
  }) async {
    try {
      await _eventStore.addEvent(
        EventLogEntry(
          id: _makeEventId(),
          entityType: 'free_note',
          entityId: entityId,
          op: op,
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      Log.d('FreeNote event log write failed: $e');
    }
  }
}

Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value));
}

DateTime _parseDate(Object? value, {DateTime? fallback}) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {}
  }
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String _makeEventId() {
  return 'evt-${DateTime.now().microsecondsSinceEpoch}';
}

