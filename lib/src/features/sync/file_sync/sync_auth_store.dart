import 'package:cogniread/src/core/services/hive_bootstrap.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/smb_credentials.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:cogniread/src/features/sync/file_sync/webdav_credentials.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SyncAuthStore {
  static const String _boxName = 'sync_auth';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box = await HiveBootstrap.openBoxSafe<dynamic>(_boxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('SyncAuthStore not initialized');
    }
    return box;
  }

  Future<OAuthToken?> loadToken(SyncProvider provider) async {
    final raw = _requireBox.get(_tokenKey(provider));
    if (raw is! Map) {
      return null;
    }
    final map = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final accessToken = map['accessToken'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    final refreshToken = map['refreshToken'] as String?;
    final tokenType = map['tokenType'] as String? ?? 'Bearer';
    final expiresRaw = map['expiresAt'] as String?;
    final expiresAt =
        expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    return OAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      tokenType: tokenType,
    );
  }

  Future<void> saveToken(SyncProvider provider, OAuthToken token) async {
    final payload = <String, Object?>{
      'accessToken': token.accessToken,
      'refreshToken': token.refreshToken,
      'tokenType': token.tokenType,
      'expiresAt': token.expiresAt?.toIso8601String(),
    };
    await _requireBox.put(_tokenKey(provider), payload);
  }

  Future<void> clearToken(SyncProvider provider) async {
    await _requireBox.delete(_tokenKey(provider));
  }

  Future<WebDavCredentials?> loadWebDavCredentials() async {
    final raw = _requireBox.get(_webDavKey());
    if (raw is! Map) {
      return null;
    }
    final map = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final baseUrl = map['baseUrl'] as String?;
    final username = map['username'] as String?;
    final password = map['password'] as String?;
    final allowInsecure = map['allowInsecure'] as bool? ?? false;
    final syncPath = map['syncPath'] as String? ?? 'cogniread';
    if (baseUrl == null || username == null || password == null) {
      return null;
    }
    if (baseUrl.trim().isEmpty || username.trim().isEmpty) {
      return null;
    }
    return WebDavCredentials(
      baseUrl: baseUrl,
      username: username,
      password: password,
      allowInsecure: allowInsecure,
      syncPath: syncPath,
    );
  }

  Future<void> saveWebDavCredentials(WebDavCredentials credentials) async {
    final payload = <String, Object?>{
      'baseUrl': credentials.baseUrl,
      'username': credentials.username,
      'password': credentials.password,
      'allowInsecure': credentials.allowInsecure,
      'syncPath': credentials.syncPath,
    };
    await _requireBox.put(_webDavKey(), payload);
  }

  Future<void> clearWebDavCredentials() async {
    await _requireBox.delete(_webDavKey());
  }

  Future<WebDavCredentials?> loadSynologyCredentials() async {
    final raw = _requireBox.get(_synologyKey());
    if (raw is! Map) {
      return null;
    }
    final map = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final baseUrl = map['baseUrl'] as String?;
    final username = map['username'] as String?;
    final password = map['password'] as String?;
    final allowInsecure = map['allowInsecure'] as bool? ?? false;
    final syncPath = map['syncPath'] as String? ?? 'cogniread';
    if (baseUrl == null || username == null || password == null) {
      return null;
    }
    if (baseUrl.trim().isEmpty || username.trim().isEmpty) {
      return null;
    }
    return WebDavCredentials(
      baseUrl: baseUrl,
      username: username,
      password: password,
      allowInsecure: allowInsecure,
      syncPath: syncPath,
    );
  }

  Future<void> saveSynologyCredentials(WebDavCredentials credentials) async {
    final payload = <String, Object?>{
      'baseUrl': credentials.baseUrl,
      'username': credentials.username,
      'password': credentials.password,
      'allowInsecure': credentials.allowInsecure,
      'syncPath': credentials.syncPath,
    };
    await _requireBox.put(_synologyKey(), payload);
  }

  Future<void> clearSynologyCredentials() async {
    await _requireBox.delete(_synologyKey());
  }

  Future<SmbCredentials?> loadSmbCredentials() async {
    final raw = _requireBox.get(_smbKey());
    if (raw is! Map) {
      return null;
    }
    final map = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final mountPath = map['mountPath'] as String?;
    if (mountPath == null || mountPath.trim().isEmpty) {
      return null;
    }
    return SmbCredentials(mountPath: mountPath);
  }

  Future<void> saveSmbCredentials(SmbCredentials credentials) async {
    final payload = <String, Object?>{
      'mountPath': credentials.mountPath,
    };
    await _requireBox.put(_smbKey(), payload);
  }

  Future<void> clearSmbCredentials() async {
    await _requireBox.delete(_smbKey());
  }

  Future<void> clearAll() async {
    for (final provider in SyncProvider.values) {
      await clearToken(provider);
    }
    await clearWebDavCredentials();
    await clearSynologyCredentials();
    await clearSmbCredentials();
  }

  String _tokenKey(SyncProvider provider) => 'token_${provider.name}';

  String _webDavKey() => 'webdav_credentials';

  String _synologyKey() => 'synology_credentials';

  String _smbKey() => 'smb_credentials';
}
