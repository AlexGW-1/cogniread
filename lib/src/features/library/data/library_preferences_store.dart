import 'dart:convert';

import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LibraryPreferencesStore {
  static const String _boxName = 'library_prefs';
  static const String _viewModeKey = 'view_mode';
  static const String _deviceIdKey = 'device_id';
  static const String _syncProviderKey = 'sync_provider';
  static const String _syncOAuthConfigKey = 'sync_oauth_config';
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

  Future<String?> loadSyncProvider() async {
    return _requireBox.get(_syncProviderKey) as String?;
  }

  Future<void> saveSyncProvider(String provider) async {
    await _requireBox.put(_syncProviderKey, provider);
  }

  Future<Map<String, Object?>?> loadSyncOAuthConfig() async {
    final raw = _requireBox.get(_syncOAuthConfigKey);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
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
}
