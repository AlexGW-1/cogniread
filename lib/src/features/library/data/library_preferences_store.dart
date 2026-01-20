import 'dart:convert';

import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LibraryPreferencesStore {
  static const String _boxName = 'library_prefs';
  static const String _viewModeKey = 'view_mode';
  static const String _deviceIdKey = 'device_id';
  static const String _syncProviderKey = 'sync_provider';
  static const String _syncOAuthConfigKey = 'sync_oauth_config';
  static const String _syncStatusKey = 'sync_status';
  static const String _searchHistoryKey = 'search_history';
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
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.at,
    required this.ok,
    required this.summary,
  });

  final DateTime at;
  final bool ok;
  final String summary;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'at': at.toIso8601String(),
      'ok': ok,
      'summary': summary,
    };
  }

  static SyncStatusSnapshot? fromMap(Map<String, Object?> map) {
    final atRaw = map['at'];
    final okRaw = map['ok'];
    final summaryRaw = map['summary'];
    if (atRaw is! String || summaryRaw is! String) {
      return null;
    }
    final at = DateTime.tryParse(atRaw);
    if (at == null) {
      return null;
    }
    final ok = okRaw is bool ? okRaw : false;
    return SyncStatusSnapshot(at: at, ok: ok, summary: summaryRaw);
  }
}
