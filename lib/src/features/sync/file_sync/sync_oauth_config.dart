import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/dropbox_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/google_drive_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/onedrive_oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_provider.dart';
import 'package:cogniread/src/features/sync/file_sync/yandex_disk_oauth.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SyncOAuthConfig {
  const SyncOAuthConfig({
    this.googleDrive,
    this.dropbox,
    this.oneDrive,
    this.yandexDisk,
  });

  final GoogleDriveOAuthConfig? googleDrive;
  final DropboxOAuthConfig? dropbox;
  final OneDriveOAuthConfig? oneDrive;
  final YandexDiskOAuthConfig? yandexDisk;

  static SyncOAuthConfig? fromMap(Map<String, Object?> raw) {
    return SyncOAuthConfig(
      googleDrive: _parseGoogle(raw['googleDrive']),
      dropbox: _parseDropbox(raw['dropbox']),
      oneDrive: _parseOneDrive(raw['oneDrive']),
      yandexDisk: _parseYandex(raw['yandexDisk']),
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{};
    if (googleDrive != null) {
      map['googleDrive'] = _encodeGoogle(googleDrive!);
    }
    if (dropbox != null) {
      map['dropbox'] = _encodeDropbox(dropbox!);
    }
    if (oneDrive != null) {
      map['oneDrive'] = _encodeOneDrive(oneDrive!);
    }
    if (yandexDisk != null) {
      map['yandexDisk'] = _encodeYandex(yandexDisk!);
    }
    return map;
  }

  static Future<SyncOAuthConfig?> load() async {
    final builtinConfig = _loadFromBuiltIn();
    if (builtinConfig != null) {
      return builtinConfig;
    }
    final envConfig = _loadFromEnvironment();
    if (envConfig != null) {
      return envConfig;
    }
    return loadFromFile();
  }

  static SyncOAuthConfig? _loadFromBuiltIn() {
    const googleClientId = String.fromEnvironment(
      'SYNC_OAUTH_GOOGLE_CLIENT_ID',
      defaultValue: '',
    );
    const googleClientSecret = String.fromEnvironment(
      'SYNC_OAUTH_GOOGLE_CLIENT_SECRET',
      defaultValue: '',
    );
    const googleRedirectUri = String.fromEnvironment(
      'SYNC_OAUTH_GOOGLE_REDIRECT_URI',
      defaultValue: 'cogniread://oauth',
    );
    const dropboxClientId = String.fromEnvironment(
      'SYNC_OAUTH_DROPBOX_CLIENT_ID',
      defaultValue: '',
    );
    const dropboxClientSecret = String.fromEnvironment(
      'SYNC_OAUTH_DROPBOX_CLIENT_SECRET',
      defaultValue: '',
    );
    const dropboxRedirectUri = String.fromEnvironment(
      'SYNC_OAUTH_DROPBOX_REDIRECT_URI',
      defaultValue: 'cogniread://oauth',
    );
    const oneDriveClientId = String.fromEnvironment(
      'SYNC_OAUTH_ONEDRIVE_CLIENT_ID',
      defaultValue: '',
    );
    const oneDriveClientSecret = String.fromEnvironment(
      'SYNC_OAUTH_ONEDRIVE_CLIENT_SECRET',
      defaultValue: '',
    );
    const oneDriveRedirectUri = String.fromEnvironment(
      'SYNC_OAUTH_ONEDRIVE_REDIRECT_URI',
      defaultValue: 'cogniread://oauth',
    );
    const oneDriveTenant = String.fromEnvironment(
      'SYNC_OAUTH_ONEDRIVE_TENANT',
      defaultValue: '',
    );
    const yandexClientId = String.fromEnvironment(
      'SYNC_OAUTH_YANDEX_CLIENT_ID',
      defaultValue: '',
    );
    const yandexClientSecret = String.fromEnvironment(
      'SYNC_OAUTH_YANDEX_CLIENT_SECRET',
      defaultValue: '',
    );
    const yandexRedirectUri = String.fromEnvironment(
      'SYNC_OAUTH_YANDEX_REDIRECT_URI',
      defaultValue: 'cogniread://oauth',
    );

    final google = (googleClientId.isEmpty ||
            googleClientSecret.isEmpty ||
            googleRedirectUri.isEmpty)
        ? null
        : GoogleDriveOAuthConfig(
            clientId: googleClientId,
            clientSecret: googleClientSecret,
            redirectUri: googleRedirectUri,
          );
    final dropbox = (dropboxClientId.isEmpty ||
            dropboxClientSecret.isEmpty ||
            dropboxRedirectUri.isEmpty)
        ? null
        : DropboxOAuthConfig(
            clientId: dropboxClientId,
            clientSecret: dropboxClientSecret,
            redirectUri: dropboxRedirectUri,
          );
    final oneDrive = (oneDriveClientId.isEmpty ||
            oneDriveClientSecret.isEmpty ||
            oneDriveRedirectUri.isEmpty)
        ? null
        : OneDriveOAuthConfig(
            clientId: oneDriveClientId,
            clientSecret: oneDriveClientSecret,
            redirectUri: oneDriveRedirectUri,
            tenant: oneDriveTenant.isEmpty ? 'common' : oneDriveTenant,
          );
    final yandex = (yandexClientId.isEmpty ||
            yandexClientSecret.isEmpty ||
            yandexRedirectUri.isEmpty)
        ? null
        : YandexDiskOAuthConfig(
            clientId: yandexClientId,
            clientSecret: yandexClientSecret,
            redirectUri: yandexRedirectUri,
          );

    if (google == null && dropbox == null && oneDrive == null && yandex == null) {
      return null;
    }
    return SyncOAuthConfig(
      googleDrive: google,
      dropbox: dropbox,
      oneDrive: oneDrive,
      yandexDisk: yandex,
    );
  }

  static Future<SyncOAuthConfig?> loadFromFile({
    String fileName = 'sync_oauth.json',
  }) async {
    final candidates = <File>[];
    final envPath = Platform.environment['COGNIREAD_OAUTH_PATH'];
    if (envPath != null && envPath.trim().isNotEmpty) {
      candidates.add(File(envPath.trim()));
    }
    final homeDir = _homeDir();
    if (homeDir != null && homeDir.isNotEmpty) {
      candidates.add(
        File(p.join(homeDir, '.cogniread', fileName)),
      );
    }
    candidates.add(File(fileName));
    try {
      final appDir = await getApplicationDocumentsDirectory();
      candidates.add(File(p.join(appDir.path, fileName)));
    } catch (_) {}
    File? resolved;
    for (final file in candidates) {
      final exists = await file.exists();
      Log.d('Sync OAuth candidate: ${file.path} (exists=$exists)');
      if (exists) {
        resolved = file;
        break;
      }
    }
    if (resolved == null) {
      Log.d('Sync OAuth config not found');
      return null;
    }
    final raw = await resolved.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      Log.d('Sync OAuth config invalid JSON');
      return null;
    }
    final map = _coerceMap(decoded);
    final config = SyncOAuthConfig(
      googleDrive: _parseGoogle(map['googleDrive']),
      dropbox: _parseDropbox(map['dropbox']),
      oneDrive: _parseOneDrive(map['oneDrive']),
      yandexDisk: _parseYandex(map['yandexDisk']),
    );
    Log.d('Sync OAuth config loaded from ${resolved.path}');
    return config;
  }

  static String? _homeDir() {
    final env = Platform.environment;
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }
    final userProfile = env['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    return null;
  }

  static SyncOAuthConfig? _loadFromEnvironment() {
    const raw = String.fromEnvironment('SYNC_OAUTH_JSON');
    if (raw.trim().isEmpty) {
      return null;
    }
    return _decodeConfig(raw);
  }

  static SyncOAuthConfig? _decodeConfig(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final map = _coerceMap(decoded);
    return SyncOAuthConfig(
      googleDrive: _parseGoogle(map['googleDrive']),
      dropbox: _parseDropbox(map['dropbox']),
      oneDrive: _parseOneDrive(map['oneDrive']),
      yandexDisk: _parseYandex(map['yandexDisk']),
    );
  }

  bool isConfigured(SyncProvider provider) {
    switch (provider) {
      case SyncProvider.googleDrive:
        return googleDrive != null;
      case SyncProvider.dropbox:
        return dropbox != null;
      case SyncProvider.oneDrive:
        return oneDrive != null;
      case SyncProvider.yandexDisk:
        return yandexDisk != null;
      case SyncProvider.webDav:
      case SyncProvider.synologyDrive:
      case SyncProvider.smb:
        return true;
    }
  }

  static GoogleDriveOAuthConfig? _parseGoogle(Object? raw) {
    final map = _mapOrNull(raw);
    if (map == null) {
      return null;
    }
    final clientId = _string(map, 'clientId');
    final clientSecret = _string(map, 'clientSecret');
    final redirectUri = _string(map, 'redirectUri');
    if (clientId == null || clientSecret == null || redirectUri == null) {
      return null;
    }
    return GoogleDriveOAuthConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
    );
  }

  static DropboxOAuthConfig? _parseDropbox(Object? raw) {
    final map = _mapOrNull(raw);
    if (map == null) {
      return null;
    }
    final clientId = _string(map, 'clientId');
    final clientSecret = _string(map, 'clientSecret');
    final redirectUri = _string(map, 'redirectUri');
    if (clientId == null || clientSecret == null || redirectUri == null) {
      return null;
    }
    return DropboxOAuthConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
    );
  }

  static OneDriveOAuthConfig? _parseOneDrive(Object? raw) {
    final map = _mapOrNull(raw);
    if (map == null) {
      return null;
    }
    final clientId = _string(map, 'clientId');
    final clientSecret = _string(map, 'clientSecret');
    final redirectUri = _string(map, 'redirectUri');
    if (clientId == null || clientSecret == null || redirectUri == null) {
      return null;
    }
    final tenant = _string(map, 'tenant') ?? 'common';
    return OneDriveOAuthConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      tenant: tenant,
    );
  }

  static YandexDiskOAuthConfig? _parseYandex(Object? raw) {
    final map = _mapOrNull(raw);
    if (map == null) {
      return null;
    }
    final clientId = _string(map, 'clientId');
    final clientSecret = _string(map, 'clientSecret');
    final redirectUri = _string(map, 'redirectUri');
    if (clientId == null || clientSecret == null || redirectUri == null) {
      return null;
    }
    return YandexDiskOAuthConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
    );
  }

  static Map<String, Object?>? _mapOrNull(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return _coerceMap(raw);
  }

  static Map<String, Object?> _coerceMap(Map<dynamic, dynamic> raw) {
    return raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static Map<String, Object?> _encodeGoogle(GoogleDriveOAuthConfig config) {
    return <String, Object?>{
      'clientId': config.clientId,
      'clientSecret': config.clientSecret,
      'redirectUri': config.redirectUri,
    };
  }

  static Map<String, Object?> _encodeDropbox(DropboxOAuthConfig config) {
    return <String, Object?>{
      'clientId': config.clientId,
      'clientSecret': config.clientSecret,
      'redirectUri': config.redirectUri,
    };
  }

  static Map<String, Object?> _encodeOneDrive(OneDriveOAuthConfig config) {
    return <String, Object?>{
      'clientId': config.clientId,
      'clientSecret': config.clientSecret,
      'redirectUri': config.redirectUri,
      'tenant': config.tenant,
    };
  }

  static Map<String, Object?> _encodeYandex(YandexDiskOAuthConfig config) {
    return <String, Object?>{
      'clientId': config.clientId,
      'clientSecret': config.clientSecret,
      'redirectUri': config.redirectUri,
    };
  }

  static String? _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      if (_looksLikePlaceholder(trimmed)) {
        return null;
      }
      return value;
    }
    return null;
  }

  static bool _looksLikePlaceholder(String value) {
    return value.startsWith('YOUR_') || value.startsWith('REPLACE_');
  }
}
