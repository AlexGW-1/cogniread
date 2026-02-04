import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class DropboxApiFile {
  const DropboxApiFile({
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

abstract class DropboxApiClient {
  Future<List<DropboxApiFile>> listFolder(String path);

  Future<DropboxApiFile?> getMetadata(String path);

  Future<List<int>> download(String path);

  Future<DropboxApiFile> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  });

  Future<void> createFolder(String path);

  Future<void> delete(String path);
}

class HttpDropboxApiClient implements DropboxApiClient {
  HttpDropboxApiClient({
    required this.tokenProvider,
    Duration requestTimeout = const Duration(seconds: 20),
    Duration transferTimeout = const Duration(minutes: 2),
    HttpClient? httpClient,
  })  : _httpClient = httpClient ?? HttpClient(),
        _requestTimeout = requestTimeout,
        _transferTimeout = transferTimeout;

  final OAuthTokenProvider tokenProvider;
  final HttpClient _httpClient;
  final Duration _requestTimeout;
  final Duration _transferTimeout;

  @override
  Future<List<DropboxApiFile>> listFolder(String path) async {
    final uri = Uri.https('api.dropboxapi.com', '/2/files/list_folder');
    final body = jsonEncode(<String, Object?>{
      'path': path,
      'recursive': false,
      'include_media_info': false,
      'include_deleted': false,
      'include_has_explicit_shared_members': false,
    });
    Map<String, Object?> json;
    try {
      json = await _requestJson(
        uri,
        body: utf8.encode(body),
        contentType: 'application/json',
      );
    } on SyncAdapterException catch (error) {
      final code = error.code ?? '';
      final message = error.message;
      final isNotFound = code.startsWith('dropbox_409') &&
          (message.contains('path/not_found') ||
              error.toString().contains('path/not_found'));
      if (isNotFound) {
        if (path.isEmpty) {
          // Корень App Folder недоступен/не создан — вернём пустой список.
          return const <DropboxApiFile>[];
        }
        await createFolder(path);
        json = await _requestJson(
          uri,
          body: utf8.encode(body),
          contentType: 'application/json',
        );
      } else {
        rethrow;
      }
    }
    final entries = json['entries'];
    if (entries is! List) {
      return const <DropboxApiFile>[];
    }
    return entries
        .whereType<Map<Object?, Object?>>()
        .map((raw) => _parseFile(_coerceMap(raw)))
        .toList();
  }

  @override
  Future<DropboxApiFile?> getMetadata(String path) async {
    final uri = Uri.https('api.dropboxapi.com', '/2/files/get_metadata');
    final body = jsonEncode(<String, Object?>{
      'path': path,
      'include_media_info': false,
      'include_deleted': false,
      'include_has_explicit_shared_members': false,
    });
    final json = await _requestJsonOrNull(
      uri,
      body: utf8.encode(body),
      contentType: 'application/json',
      allowNotFound: true,
    );
    if (json.isEmpty) {
      return null;
    }
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<List<int>> download(String path) async {
    final uri = Uri.https('content.dropboxapi.com', '/2/files/download');
    return _requestBytes(
      uri,
      apiArg: jsonEncode(<String, Object?>{'path': path}),
    );
  }

  @override
  Future<DropboxApiFile> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final uri = Uri.https('content.dropboxapi.com', '/2/files/upload');
    final arg = jsonEncode(<String, Object?>{
      'path': path,
      'mode': overwrite ? 'overwrite' : 'add',
      'autorename': false,
      'mute': false,
      'strict_conflict': false,
    });
    final json = await _requestJson(
      uri,
      body: bytes,
      contentType: 'application/octet-stream',
      apiArg: arg,
    );
    return _parseFile(json);
  }

  @override
  Future<void> delete(String path) async {
    final uri = Uri.https('api.dropboxapi.com', '/2/files/delete_v2');
    final body = jsonEncode(<String, Object?>{'path': path});
    await _requestJson(
      uri,
      body: utf8.encode(body),
      contentType: 'application/json',
      allowNotFound: true,
    );
  }

  @override
  Future<void> createFolder(String path) async {
    if (path.isEmpty || path == '/') {
      // Корневой App Folder нельзя создавать через API — пропускаем.
      return;
    }
    final uri = Uri.https('api.dropboxapi.com', '/2/files/create_folder_v2');
    final body = jsonEncode(<String, Object?>{
      'path': path,
      'autorename': false,
    });
    final json = await _requestJson(
      uri,
      body: utf8.encode(body),
      contentType: 'application/json',
      allowConflict: true,
    );
    if (json.isNotEmpty) {
      Log.d('createFolder response for $path: $json');
    }
  }

  Future<Map<String, Object?>> _requestJson(
    Uri uri, {
    required List<int> body,
    required String contentType,
    String? apiArg,
    bool allowConflict = false,
    bool allowNotFound = false,
  }) async {
    final bytes = await _requestBytes(
      uri,
      body: body,
      contentType: contentType,
      apiArg: apiArg,
      allowConflict: allowConflict,
      allowNotFound: allowNotFound,
    );
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

  Future<Map<String, Object?>> _requestJsonOrNull(
    Uri uri, {
    required List<int> body,
    required String contentType,
    String? apiArg,
    bool allowNotFound = false,
  }) async {
    try {
      return await _requestJson(
        uri,
        body: body,
        contentType: contentType,
        apiArg: apiArg,
        allowNotFound: allowNotFound,
      );
    } on SyncAdapterException catch (error) {
      final code = error.code ?? '';
      final message = error.message;
      Log.d('Dropbox API error caught: code=$code message=$message');
      if (code.startsWith('dropbox_409') &&
          (message.contains('path/not_found') ||
              message.contains('path_lookup/not_found'))) {
        Log.d('Dropbox API path not found: returning empty response');
        return const <String, Object?>{};
      }
      rethrow;
    }
  }

  Future<List<int>> _requestBytes(
    Uri uri, {
    List<int>? body,
    String? contentType,
    String? apiArg,
    bool allowConflict = false,
    bool allowNotFound = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final effectiveTimeout =
        uri.host == 'content.dropboxapi.com' ? _transferTimeout : _requestTimeout;
    Log.d('Dropbox request: POST $uri');
    try {
      final token = await tokenProvider.getToken();
      final valid = requireValidToken(token);
      final request =
          await _httpClient.postUrl(uri).timeout(effectiveTimeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        '${valid.tokenType} ${valid.accessToken}',
      );
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (apiArg != null) {
        request.headers.set('Dropbox-API-Arg', apiArg);
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
        'Dropbox response: POST $uri -> ${response.statusCode} '
        '(${bytes.length} bytes, ${stopwatch.elapsedMilliseconds} ms)',
      );
      if (response.statusCode >= 400) {
        final bodyText = bytes.isEmpty ? '' : utf8.decode(bytes);
        final baseCode = 'dropbox_${response.statusCode}';
        final isNotFound = bodyText.contains('path/not_found') ||
            bodyText.contains('path_lookup/not_found');
        final code = isNotFound ? '${baseCode}_path_not_found' : baseCode;
        if (allowConflict && response.statusCode == 409) {
          Log.d('Dropbox HTTP 409 ignored uri=$uri');
          return const <int>[];
        }
        if (allowNotFound && isNotFound) {
          Log.d('Dropbox HTTP 409 not_found ignored uri=$uri');
          return const <int>[];
        }
        Log.d('Dropbox HTTP error ${response.statusCode} uri=$uri');
        throw SyncAdapterException(
          'Dropbox API error ${response.statusCode}${bodyText.isEmpty ? '' : ': $bodyText'}',
          code: code,
        );
      }
      return bytes;
    } on TimeoutException {
      Log.d(
        'Dropbox timeout: POST $uri after ${effectiveTimeout.inSeconds}s',
      );
      throw SyncAdapterException(
        'Dropbox timeout',
        code: 'dropbox_timeout',
      );
    } on HandshakeException catch (error) {
      Log.d('Dropbox SSL error: POST $uri -> $error');
      throw SyncAdapterException(
        'Dropbox SSL error',
        code: 'dropbox_ssl',
      );
    } on SocketException catch (error) {
      Log.d('Dropbox network error: POST $uri -> $error');
      throw SyncAdapterException(
        'Dropbox network error: ${error.message}',
        code: 'dropbox_socket',
      );
    } on HttpException catch (error) {
      Log.d('Dropbox HTTP error: POST $uri -> $error');
      throw SyncAdapterException(
        'Dropbox HTTP error: ${error.message}',
        code: 'dropbox_http',
      );
    }
  }

  DropboxApiFile _parseFile(Map<String, Object?> map) {
    final modified = map['client_modified'] ?? map['server_modified'];
    final size = map['size'];
    return DropboxApiFile(
      path: map['path_display'] as String? ??
          map['path_lower'] as String? ??
          '',
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
}
