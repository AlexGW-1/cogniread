import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

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
  }) : _httpClient = httpClient ?? HttpClient();

  final OAuthTokenProvider tokenProvider;
  final HttpClient _httpClient;

  @override
  Future<List<YandexDiskApiFile>> listFolder(String path) async {
    final uri = Uri.https(
      'cloud-api.yandex.net',
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    final json = await _requestJson(uri);
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
      'cloud-api.yandex.net',
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    final json = await _requestJson(uri);
    if (json.isEmpty) {
      return null;
    }
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<List<int>> download(String path) async {
    final uri = Uri.https(
      'cloud-api.yandex.net',
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
  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool overwrite = true,
  }) async {
    final uri = Uri.https(
      'cloud-api.yandex.net',
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
      'cloud-api.yandex.net',
      '/v1/disk/resources',
      <String, String>{'path': path},
    );
    await _requestBytes(uri, method: 'DELETE');
  }

  Future<Map<String, Object?>> _requestJson(Uri uri) async {
    final bytes = await _requestBytes(uri);
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

  Future<List<int>> _requestBytes(
    Uri uri, {
    String method = 'GET',
    List<int>? body,
    bool includeAuth = true,
  }) async {
    final request = await _httpClient.openUrl(method, uri);
    if (includeAuth) {
      final token = await tokenProvider.getToken();
      final valid = requireValidToken(token);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        '${valid.tokenType} ${valid.accessToken}',
      );
    }
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode >= 400) {
      throw SyncAdapterException(
        'Yandex Disk API error ${response.statusCode}',
        code: 'yandex_${response.statusCode}',
      );
    }
    return bytes;
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
}
