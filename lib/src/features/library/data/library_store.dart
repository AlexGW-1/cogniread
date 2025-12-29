import 'package:hive_flutter/hive_flutter.dart';

class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.localPath,
    required this.addedAt,
    required this.fingerprint,
    required this.sourcePath,
  });

  final String id;
  final String title;
  final String? author;
  final String localPath;
  final DateTime addedAt;
  final String fingerprint;
  final String sourcePath;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'author': author,
        'localPath': localPath,
        'addedAt': addedAt.toIso8601String(),
        'fingerprint': fingerprint,
        'sourcePath': sourcePath,
      };

  static LibraryEntry fromMap(Map<String, Object?> map) {
    return LibraryEntry(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      localPath: map['localPath'] as String,
      addedAt: DateTime.parse(map['addedAt'] as String),
      fingerprint: map['fingerprint'] as String,
      sourcePath: map['sourcePath'] as String,
    );
  }
}

class LibraryStore {
  static const String _boxName = 'library_books';
  static bool _initialized = false;
  Box<Map>? _box;

  Future<void> init() async {
    if (!_initialized) {
      await Hive.initFlutter();
      _initialized = true;
    }
    _box = await Hive.openBox<Map>(_boxName);
  }

  Box<Map> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LibraryStore not initialized');
    }
    return box;
  }

  Future<List<LibraryEntry>> loadAll() async {
    final box = _requireBox;
    return box.values
        .map((value) => LibraryEntry.fromMap(Map<String, Object?>.from(value)))
        .toList();
  }

  Future<void> upsert(LibraryEntry entry) async {
    await _requireBox.put(entry.id, entry.toMap());
  }

  Future<void> remove(String id) async {
    await _requireBox.delete(id);
  }

  Future<void> clear() async {
    await _requireBox.clear();
  }

  Future<bool> existsByFingerprint(String fingerprint) async {
    return _requireBox.values.any((value) {
      final map = Map<String, Object?>.from(value);
      return map['fingerprint'] == fingerprint;
    });
  }
}
