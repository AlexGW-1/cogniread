import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:hive_flutter/hive_flutter.dart';

class EventLogEntry {
  const EventLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String op;
  final Map<String, Object?> payload;
  final DateTime createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'op': op,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };

  static EventLogEntry fromMap(Map<String, Object?> map) {
    return EventLogEntry(
      id: map['id'] as String? ?? '',
      entityType: map['entityType'] as String? ?? '',
      entityId: map['entityId'] as String? ?? '',
      op: map['op'] as String? ?? '',
      payload: _coercePayload(map['payload']),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class EventLogStore {
  static const String _boxName = 'event_log';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('EventLogStore not initialized');
    }
    return box;
  }

  Future<void> addEvent(EventLogEntry entry) async {
    await _requireBox.add(entry.toMap());
  }

  List<EventLogEntry> listEvents({int? limit}) {
    final entries = _requireBox.values
        .whereType<Map<Object?, Object?>>()
        .map((value) => EventLogEntry.fromMap(_coerceMap(value)))
        .toList();
    if (limit == null || limit >= entries.length) {
      return entries;
    }
    return entries.sublist(entries.length - limit);
  }

  Future<int> purgeEvents({required DateTime olderThan}) async {
    final box = _requireBox;
    final toDelete = <dynamic>[];
    for (final entry in box.toMap().entries) {
      final value = entry.value;
      if (value is! Map<Object?, Object?>) {
        continue;
      }
      final map = _coerceMap(value);
      final createdAtRaw = map['createdAt'];
      if (createdAtRaw is! String) {
        continue;
      }
      final createdAt = DateTime.tryParse(createdAtRaw);
      if (createdAt == null) {
        continue;
      }
      if (createdAt.isBefore(olderThan)) {
        toDelete.add(entry.key);
      }
    }
    for (final key in toDelete) {
      await box.delete(key);
    }
    return toDelete.length;
  }

  Future<void> clear() async {
    await _requireBox.clear();
  }
}

Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
  return source.map(
    (key, value) => MapEntry(key?.toString() ?? '', value),
  );
}

Map<String, Object?> _coercePayload(Object? payload) {
  if (payload is Map<Object?, Object?>) {
    return _coerceMap(payload);
  }
  if (payload is Map<String, Object?>) {
    return payload;
  }
  return const <String, Object?>{};
}
