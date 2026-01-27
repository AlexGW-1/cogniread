import 'dart:convert';

import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LibraryPreferencesStore {
  static const String _boxName = 'library_prefs';
  static const String _viewModeKey = 'view_mode';
  static const String _deviceIdKey = 'device_id';
  static const String _syncProviderKey = 'sync_provider';
  static const String _syncOAuthConfigKey = 'sync_oauth_config';
  static const String _syncStatusKey = 'sync_status';
  static const String _syncMetricsKey = 'sync_metrics';
  static const String _searchHistoryKey = 'search_history';
  static const String _favoriteIdsKey = 'favorite_ids';
  static const String _toReadIdsKey = 'to_read_ids';
  static const String _aiBaseUrlKey = 'ai_base_url';
  static const String _aiApiKeyKey = 'ai_api_key';
  static const String _aiModelKey = 'ai_model';
  static const String _aiEmbeddingModelKey = 'ai_embedding_model';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LibraryPreferencesStore not initialized');
    }
    return box;
  }

  Future<String?> loadViewMode() async {
    return _requireBox.get(_viewModeKey) as String?;
  }

  Future<void> saveViewMode(String mode) async {
    await _requireBox.put(_viewModeKey, mode);
  }

  Future<String?> loadDeviceId() async {
    return _requireBox.get(_deviceIdKey) as String?;
  }

  Future<void> saveDeviceId(String deviceId) async {
    await _requireBox.put(_deviceIdKey, deviceId);
  }

  Future<void> clearDeviceId() async {
    await _requireBox.delete(_deviceIdKey);
  }

  Future<String?> loadSyncProvider() async {
    return _requireBox.get(_syncProviderKey) as String?;
  }

  Future<void> saveSyncProvider(String provider) async {
    await _requireBox.put(_syncProviderKey, provider);
  }

  Future<void> clearSyncProvider() async {
    await _requireBox.delete(_syncProviderKey);
  }

  Future<Map<String, Object?>?> loadSyncOAuthConfig() async {
    final raw = _requireBox.get(_syncOAuthConfigKey);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return null;
  }

  Future<void> saveSyncOAuthConfig(Map<String, Object?>? config) async {
    if (config == null || config.isEmpty) {
      await _requireBox.delete(_syncOAuthConfigKey);
      return;
    }
    await _requireBox.put(_syncOAuthConfigKey, jsonEncode(config));
  }

  Future<void> clearSyncOAuthConfig() async {
    await _requireBox.delete(_syncOAuthConfigKey);
  }

  Future<SyncStatusSnapshot?> loadSyncStatus() async {
    final raw = _requireBox.get(_syncStatusKey);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return SyncStatusSnapshot.fromMap(map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveSyncStatus(SyncStatusSnapshot? snapshot) async {
    if (snapshot == null) {
      await _requireBox.delete(_syncStatusKey);
      return;
    }
    await _requireBox.put(_syncStatusKey, jsonEncode(snapshot.toMap()));
  }

  Future<void> clearSyncStatus() async {
    await _requireBox.delete(_syncStatusKey);
  }

  Future<SyncMetricsSnapshot?> loadSyncMetrics() async {
    final raw = _requireBox.get(_syncMetricsKey);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = decoded.map((key, value) => MapEntry(key.toString(), value));
        return SyncMetricsSnapshot.fromMap(map);
      }
    }
    return null;
  }

  Future<void> saveSyncMetrics(SyncMetricsSnapshot? snapshot) async {
    if (snapshot == null) {
      await _requireBox.delete(_syncMetricsKey);
      return;
    }
    await _requireBox.put(_syncMetricsKey, jsonEncode(snapshot.toMap()));
  }

  Future<void> clearSyncMetrics() async {
    await _requireBox.delete(_syncMetricsKey);
  }

  Future<List<String>> loadSearchHistory() async {
    final raw = _requireBox.get(_searchHistoryKey);
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((v) => v.isNotEmpty)
          .toList();
    }
    if (raw is! String || raw.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((value) => value.toString())
            .where((v) => v.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> saveSearchHistory(List<String> history) async {
    final normalized = history
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    await _requireBox.put(_searchHistoryKey, jsonEncode(normalized));
  }

  Future<void> clearSearchHistory() async {
    await _requireBox.delete(_searchHistoryKey);
  }

  Future<List<String>> loadFavoriteIds() async {
    return _loadStringList(_favoriteIdsKey);
  }

  Future<void> saveFavoriteIds(Iterable<String> ids) async {
    await _saveStringList(_favoriteIdsKey, ids);
  }

  Future<List<String>> loadToReadIds() async {
    return _loadStringList(_toReadIdsKey);
  }

  Future<void> saveToReadIds(Iterable<String> ids) async {
    await _saveStringList(_toReadIdsKey, ids);
  }

  Future<AiConfig> loadAiConfig() async {
    final baseUrl = _requireBox.get(_aiBaseUrlKey) as String?;
    final apiKey = _requireBox.get(_aiApiKeyKey) as String?;
    final model = _requireBox.get(_aiModelKey) as String?;
    final embeddingModel = _requireBox.get(_aiEmbeddingModelKey) as String?;
    return AiConfig(
      baseUrl: baseUrl?.trim().isEmpty == true ? null : baseUrl?.trim(),
      apiKey: apiKey?.trim().isEmpty == true ? null : apiKey?.trim(),
      model: model?.trim().isEmpty == true ? null : model?.trim(),
      embeddingModel:
          embeddingModel?.trim().isEmpty == true
              ? null
              : embeddingModel?.trim(),
    );
  }

  Future<void> saveAiConfig(AiConfig config) async {
    final baseUrl = config.baseUrl?.trim() ?? '';
    if (baseUrl.isEmpty) {
      await _requireBox.delete(_aiBaseUrlKey);
      await _requireBox.delete(_aiApiKeyKey);
      await _requireBox.delete(_aiModelKey);
      await _requireBox.delete(_aiEmbeddingModelKey);
      return;
    }
    await _requireBox.put(_aiBaseUrlKey, baseUrl);
    if (config.apiKey != null && config.apiKey!.trim().isNotEmpty) {
      await _requireBox.put(_aiApiKeyKey, config.apiKey!.trim());
    } else {
      await _requireBox.delete(_aiApiKeyKey);
    }
    if (config.model != null && config.model!.trim().isNotEmpty) {
      await _requireBox.put(_aiModelKey, config.model!.trim());
    } else {
      await _requireBox.delete(_aiModelKey);
    }
    if (config.embeddingModel != null &&
        config.embeddingModel!.trim().isNotEmpty) {
      await _requireBox.put(
        _aiEmbeddingModelKey,
        config.embeddingModel!.trim(),
      );
    } else {
      await _requireBox.delete(_aiEmbeddingModelKey);
    }
  }

  Future<List<String>> _loadStringList(String key) async {
    final raw = _requireBox.get(key);
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList();
    }
    if (raw is! String || raw.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> _saveStringList(String key, Iterable<String> values) async {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    await _requireBox.put(key, jsonEncode(normalized));
  }
}

enum SyncStatusState {
  success,
  error,
  paused;

  static SyncStatusState? fromStored(Object? raw) {
    if (raw is String) {
      for (final state in SyncStatusState.values) {
        if (state.name == raw) {
          return state;
        }
      }
    }
    return null;
  }
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.at,
    required this.state,
    required this.summary,
  });

  final DateTime at;
  final SyncStatusState state;
  final String summary;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'at': at.toIso8601String(),
      'state': state.name,
      'summary': summary,
    };
  }

  static SyncStatusSnapshot? fromMap(Map<String, Object?> map) {
    final atRaw = map['at'];
    final stateRaw = map['state'];
    final summaryRaw = map['summary'];
    if (atRaw is! String || summaryRaw is! String) {
      return null;
    }
    final at = DateTime.tryParse(atRaw);
    if (at == null) {
      return null;
    }
    final state = SyncStatusState.fromStored(stateRaw) ??
        (map['ok'] is bool
            ? ((map['ok'] as bool)
                  ? SyncStatusState.success
                  : SyncStatusState.error)
            : null);
    if (state == null) {
      return null;
    }
    return SyncStatusSnapshot(at: at, state: state, summary: summaryRaw);
  }
}

class SyncMetricsSnapshot {
  const SyncMetricsSnapshot({
    required this.at,
    required this.durationMs,
    required this.bytesUploaded,
    required this.bytesDownloaded,
    required this.filesUploaded,
    required this.filesDownloaded,
    required this.appliedEvents,
    required this.appliedState,
    required this.uploadedEvents,
    required this.booksUploaded,
    required this.booksDownloaded,
    required this.errorCountTotal,
    required this.errorCountConsecutive,
    this.errorCode,
  });

  final DateTime at;
  final int durationMs;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int filesUploaded;
  final int filesDownloaded;
  final int appliedEvents;
  final int appliedState;
  final int uploadedEvents;
  final int booksUploaded;
  final int booksDownloaded;
  final int errorCountTotal;
  final int errorCountConsecutive;
  final String? errorCode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'at': at.toIso8601String(),
      'durationMs': durationMs,
      'bytesUploaded': bytesUploaded,
      'bytesDownloaded': bytesDownloaded,
      'filesUploaded': filesUploaded,
      'filesDownloaded': filesDownloaded,
      'appliedEvents': appliedEvents,
      'appliedState': appliedState,
      'uploadedEvents': uploadedEvents,
      'booksUploaded': booksUploaded,
      'booksDownloaded': booksDownloaded,
      'errorCountTotal': errorCountTotal,
      'errorCountConsecutive': errorCountConsecutive,
      if (errorCode != null) 'errorCode': errorCode,
    };
  }

  static SyncMetricsSnapshot? fromMap(Map<String, Object?> map) {
    final atRaw = map['at'];
    if (atRaw is! String) {
      return null;
    }
    final at = DateTime.tryParse(atRaw);
    if (at == null) {
      return null;
    }
    int readInt(Object? value) => (value as num?)?.toInt() ?? 0;
    return SyncMetricsSnapshot(
      at: at,
      durationMs: readInt(map['durationMs']),
      bytesUploaded: readInt(map['bytesUploaded']),
      bytesDownloaded: readInt(map['bytesDownloaded']),
      filesUploaded: readInt(map['filesUploaded']),
      filesDownloaded: readInt(map['filesDownloaded']),
      appliedEvents: readInt(map['appliedEvents']),
      appliedState: readInt(map['appliedState']),
      uploadedEvents: readInt(map['uploadedEvents']),
      booksUploaded: readInt(map['booksUploaded']),
      booksDownloaded: readInt(map['booksDownloaded']),
      errorCountTotal: readInt(map['errorCountTotal']),
      errorCountConsecutive: readInt(map['errorCountConsecutive']),
      errorCode: map['errorCode'] as String?,
    );
  }
}
