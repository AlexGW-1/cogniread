import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/core/utils/logger.dart';

class YandexDiskApiFile {
  const YandexDiskApiFile({
    required this.path,
    required this.name,
    this.modifiedTime,
    this.size,
  });

  final String path;
  final String name;
  final DateTime? modifiedTime;
  final int? size;
}

abstract class YandexDiskApiClient {
  Future<List<YandexDiskApiFile>> listFolder(String path);

  Future<YandexDiskApiFile?> getMetadata(String path);

  Future<List<int>> download(String path);

  Future<void> createFolder(String path);

  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  });

  Future<void> delete(String path);
}

class HttpYandexDiskApiClient implements YandexDiskApiClient {
  HttpYandexDiskApiClient({
    required this.tokenProvider,
    HttpClient? httpClient,
    Duration requestTimeout = const Duration(seconds: 20),
    Duration transferTimeout = const Duration(minutes: 2),
  })  : _httpClient = httpClient ?? HttpClient(),
        _requestTimeout = requestTimeout,
        _transferTimeout = transferTimeout;

  final OAuthTokenProvider tokenProvider;
  final HttpClient _httpClient;
  final Duration _requestTimeout;
  final Duration _transferTimeout;

  static const _apiHost = 'cloud-api.yandex.net';

  @override
  Future<List<YandexDiskApiFile>> listFolder(String path) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    Map<String, Object?> json;
    try {
      json = await _requestJson(uri, allowNotFound: true);
    } on SyncAdapterException catch (error) {
      if (error.code == 'yandex_404') {
        return const <YandexDiskApiFile>[];
      }
      rethrow;
    }
    final embedded = json['_embedded'];
    final items = embedded is Map ? embedded['items'] : null;
    if (items is! List) {
      return const <YandexDiskApiFile>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map((raw) => _parseFile(_coerceMap(raw)))
        .toList();
  }

  @override
  Future<YandexDiskApiFile?> getMetadata(String path) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    Map<String, Object?> json;
    try {
      json = await _requestJson(uri, allowNotFound: true);
    } on SyncAdapterException catch (error) {
      if (error.code == 'yandex_404') {
        return null;
      }
      rethrow;
    }
    if (json.isEmpty) {
      return null;
    }
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<List<int>> download(String path) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources/download',
      <String, String>{'path': path},
    );
    final json = await _requestJson(uri);
    final href = json['href'] as String?;
    if (href == null || href.isEmpty) {
      return <int>[];
    }
    final downloadUri = Uri.parse(href);
    return _requestBytes(downloadUri, includeAuth: false);
  }

  @override
  Future<void> createFolder(String path) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    final response = await _requestRaw(uri, method: 'PUT');
    if (response.statusCode < 400 || response.statusCode == 201) {
      return;
    }
    if (response.statusCode == 409) {
      final details = _extractErrorDetails(response.bytes) ?? '';
      // When the directory already exists, Yandex responds with 409:
      // DiskPathPointsToExistentDirectoryError. This is safe to ignore.
      if (details.contains('DiskPathPointsToExistentDirectoryError')) {
        return;
      }
    }
    final details = _extractErrorDetails(response.bytes);
    final suffix = details == null ? '' : ': $details';
    throw SyncAdapterException(
      'Yandex Disk API error ${response.statusCode}$suffix',
      code: 'yandex_${response.statusCode}',
    );
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources/upload',
      <String, String>{
        'path': path,
        'overwrite': overwrite ? 'true' : 'false',
      },
    );
    final json = await _requestJson(uri);
    final href = json['href'] as String?;
    if (href == null || href.isEmpty) {
      throw SyncAdapterException('Yandex upload URL missing');
    }
    final uploadUri = Uri.parse(href);
    await _requestBytes(
      uploadUri,
      method: 'PUT',
      body: bytes,
      includeAuth: false,
    );
  }

  @override
  Future<void> delete(String path) async {
    final uri = Uri.https(
      _apiHost,
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    final response = await _requestRaw(uri, method: 'DELETE');
    if (response.statusCode < 400) {
      return;
    }
    if (response.statusCode == 404) {
      return;
    }
    final details = _extractErrorDetails(response.bytes);
    final suffix = details == null ? '' : ': $details';
    throw SyncAdapterException(
      'Yandex Disk API error ${response.statusCode}$suffix',
      code: 'yandex_${response.statusCode}',
    );
  }

  Future<Map<String, Object?>> _requestJson(
    Uri uri, {
    bool allowNotFound = false,
  }) async {
    final bytes = await _requestBytes(uri, allowNotFound: allowNotFound);
    if (bytes.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return _coerceMap(decoded.cast());
    }
    return const <String, Object?>{};
  }

  Future<_YandexRawResponse> _requestRaw(
    Uri uri, {
    String method = 'GET',
    List<int>? body,
    bool includeAuth = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final safeUri = _safeUriForLogs(uri);
    final effectiveTimeout = uri.host == _apiHost ? _requestTimeout : _transferTimeout;
    Log.d('Yandex Disk request: $method $safeUri');
    try {
      final request =
          await _httpClient.openUrl(method, uri).timeout(effectiveTimeout);
      if (includeAuth) {
        final token = await tokenProvider.getToken();
        final valid = requireValidToken(token);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          // Yandex APIs expect `Authorization: OAuth <token>` regardless of
          // `token_type` in the token response.
          'OAuth ${valid.accessToken}',
        );
      }
      if (body != null) {
        request.add(body);
      }
      final response = await request.close().timeout(effectiveTimeout);
      final bytes = await response
          .fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          )
          .timeout(effectiveTimeout);
      Log.d(
        'Yandex Disk response: $method $safeUri -> ${response.statusCode} '
        '(${bytes.length} bytes, ${stopwatch.elapsedMilliseconds} ms)',
      );
      return _YandexRawResponse(
        statusCode: response.statusCode,
        bytes: bytes,
      );
    } on TimeoutException {
      Log.d(
        'Yandex Disk timeout: $method $safeUri after ${effectiveTimeout.inSeconds}s',
      );
      throw SyncAdapterException(
        'Yandex Disk timeout',
        code: 'yandex_timeout',
      );
    } on HandshakeException catch (error) {
      Log.d('Yandex Disk SSL error: $method $safeUri -> $error');
      throw SyncAdapterException(
        'Yandex Disk SSL error',
        code: 'yandex_ssl',
      );
    } on SocketException catch (error) {
      Log.d('Yandex Disk network error: $method $safeUri -> $error');
      throw SyncAdapterException(
        'Yandex Disk network error: ${error.message}',
        code: 'yandex_socket',
      );
    } on HttpException catch (error) {
      Log.d('Yandex Disk HTTP error: $method $safeUri -> $error');
      throw SyncAdapterException(
        'Yandex Disk HTTP error: ${error.message}',
        code: 'yandex_http',
      );
    }
  }

  Future<List<int>> _requestBytes(
    Uri uri, {
    String method = 'GET',
    List<int>? body,
    bool includeAuth = true,
    bool allowNotFound = false,
  }) async {
    final response = await _requestRaw(
      uri,
      method: method,
      body: body,
      includeAuth: includeAuth,
    );
    if (allowNotFound && response.statusCode == 404) {
      return <int>[];
    }
    if (response.statusCode >= 400) {
      final details = _extractErrorDetails(response.bytes);
      final suffix = details == null ? '' : ': $details';
      throw SyncAdapterException(
        'Yandex Disk API error ${response.statusCode}$suffix',
        code: 'yandex_${response.statusCode}',
      );
    }
    return response.bytes;
  }

  YandexDiskApiFile _parseFile(Map<String, Object?> map) {
    final modified = map['modified'];
    final size = map['size'];
    return YandexDiskApiFile(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      modifiedTime:
          modified is String ? DateTime.tryParse(modified) : null,
      size: size is num ? size.toInt() : null,
    );
  }

  Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
    return source.map(
      (key, value) => MapEntry(key?.toString() ?? '', value),
    );
  }

  static String _safeUriForLogs(Uri uri) {
    // Never log query params for non-API hosts: pre-signed upload/download URLs
    // can contain sensitive signatures/tokens in the query string.
    if (uri.host != _apiHost) {
      return '${uri.scheme}://${uri.host}${uri.path}';
    }
    return uri.toString();
  }

  static String? _extractErrorDetails(List<int> bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    String raw;
    try {
      raw = utf8.decode(bytes);
    } catch (_) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final error = decoded['error'];
        final description = decoded['error_description'] ??
            decoded['description'] ??
            decoded['message'];
        final parts = <String>[];
        if (error is String && error.isNotEmpty) {
          parts.add(error);
        }
        if (description is String && description.isNotEmpty) {
          parts.add(description);
        }
        final joined = parts.join(': ');
        if (joined.isNotEmpty) {
          return joined;
        }
      }
    } catch (_) {
      // Ignore JSON parsing errors and fall back to raw text.
    }
    if (trimmed.length > 300) {
      return '${trimmed.substring(0, 300)}…';
    }
    return trimmed;
  }
}

class _YandexRawResponse {
  const _YandexRawResponse({
    required this.statusCode,
    required this.bytes,
  });

  final int statusCode;
  final List<int> bytes;
}
