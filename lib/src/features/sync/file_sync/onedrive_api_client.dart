import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class OneDriveApiFile {
  const OneDriveApiFile({
    required this.id,
    required this.name,
    required this.path,
    this.modifiedTime,
    this.size,
  });

  final String id;
  final String name;
  final String path;
  final DateTime? modifiedTime;
  final int? size;
}

abstract class OneDriveApiClient {
  Future<List<OneDriveApiFile>> listChildren(String path);

  Future<OneDriveApiFile?> getMetadata(String path);

  Future<List<int>> download(String path);

  Future<OneDriveApiFile> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  });

  Future<void> delete(String path);
}

class HttpOneDriveApiClient implements OneDriveApiClient {
  HttpOneDriveApiClient({
    required this.tokenProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final OAuthTokenProvider tokenProvider;
  final HttpClient _httpClient;

  @override
  Future<List<OneDriveApiFile>> listChildren(String path) async {
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/special/approot:/$path:/children',
    );
    final json = await _requestJson('GET', uri);
    final values = json['value'];
    if (values is! List) {
      return const <OneDriveApiFile>[];
    }
    return values
        .whereType<Map<Object?, Object?>>()
        .map((raw) => _parseFile(_coerceMap(raw)))
        .toList();
  }

  @override
  Future<OneDriveApiFile?> getMetadata(String path) async {
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/special/approot:/$path:',
    );
    final json = await _requestJson('GET', uri);
    if (json.isEmpty) {
      return null;
    }
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<List<int>> download(String path) async {
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/special/approot:/$path:/content',
    );
    return _requestBytes('GET', uri);
  }

  @override
  Future<OneDriveApiFile> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/special/approot:/$path:/content',
    );
    final json = await _requestJson(
      'PUT',
      uri,
      body: bytes,
      contentType: contentType ?? 'application/json',
    );
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<void> delete(String path) async {
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/special/approot:/$path:',
    );
    await _requestBytes('DELETE', uri);
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
  }) async {
    final bytes = await _requestBytes(
      method,
      uri,
      body: body,
      contentType: contentType,
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

  Future<List<int>> _requestBytes(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
  }) async {
    final token = await tokenProvider.getToken();
    final valid = requireValidToken(token);
    final request = await _httpClient.openUrl(method, uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      '${valid.tokenType} ${valid.accessToken}',
    );
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
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
        'OneDrive API error ${response.statusCode}',
        code: 'onedrive_${response.statusCode}',
      );
    }
    return bytes;
  }

  OneDriveApiFile _parseFile(Map<String, Object?> map) {
    final modified = map['lastModifiedDateTime'];
    final size = map['size'];
    final parent = map['parentReference'];
    final parentPath = parent is Map ? parent['path'] as String? : null;
    final name = map['name'] as String? ?? '';
    return OneDriveApiFile(
      id: map['id'] as String? ?? '',
      name: name,
      path: parentPath == null ? name : '$parentPath/$name',
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
