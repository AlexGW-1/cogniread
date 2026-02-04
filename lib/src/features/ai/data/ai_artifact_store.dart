import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AiArtifactStore {
  static const String _boxName = 'ai_artifacts';

  Box<dynamic>? _box;

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('AiArtifactStore not initialized');
    }
    return box;
  }

  Future<void> upsert(AiArtifact artifact) async {
    await _requireBox.put(artifact.id, artifact.toMap());
  }

  Future<void> remove(String id) async {
    await _requireBox.delete(id);
  }

  Future<List<AiArtifact>> loadAll() async {
    return _requireBox.values
        .whereType<Map<Object?, Object?>>()
        .map((value) => AiArtifact.fromMap(_coerceMap(value)))
        .toList();
  }

  Future<List<AiArtifact>> loadForScope({
    required AiScopeType scopeType,
    required String scopeId,
    AiKind? kind,
  }) async {
    final artifacts = await loadAll();
    return artifacts
        .where(
          (item) =>
              item.scopeType == scopeType &&
              item.scopeId == scopeId &&
              (kind == null || item.kind == kind),
        )
        .toList();
  }

  Future<AiArtifact?> findCached({
    required AiKind kind,
    required AiScopeType scopeType,
    required String scopeId,
    required String inputHash,
  }) async {
    final artifacts = await loadForScope(
      scopeType: scopeType,
      scopeId: scopeId,
      kind: kind,
    );
    final filtered =
        artifacts
            .where(
              (item) =>
                  item.inputHash == inputHash && item.status == AiStatus.ready,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (filtered.isEmpty) {
      return null;
    }
    return filtered.first;
  }
}

Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value));
}
