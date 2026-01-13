import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';

class GoogleDriveApiFile {
  const GoogleDriveApiFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.size,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? size;
}

abstract class GoogleDriveApiClient {
  Future<List<GoogleDriveApiFile>> listFiles({
    String? query,
    String spaces = 'appDataFolder',
  });

  Future<GoogleDriveApiFile?> getFileByName(
    String name, {
    String spaces = 'appDataFolder',
  });

  Future<List<int>> downloadFile(String fileId);

  Future<GoogleDriveApiFile> createFile({
    required String name,
    required List<int> bytes,
    String parent = 'appDataFolder',
    String? contentType,
  });

  Future<GoogleDriveApiFile> updateFile({
    required String fileId,
    required List<int> bytes,
    String? contentType,
  });

  Future<void> deleteFile(String fileId);
}

class HttpGoogleDriveApiClient implements GoogleDriveApiClient {
  HttpGoogleDriveApiClient({
    required this.tokenProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final OAuthTokenProvider tokenProvider;
  final HttpClient _httpClient;

  @override
  Future<List<GoogleDriveApiFile>> listFiles({
    String? query,
    String spaces = 'appDataFolder',
  }) async {
    final params = <String, String>{
      'spaces': spaces,
      'fields': 'files(id,name,modifiedTime,size)',
    };
    if (query != null && query.isNotEmpty) {
      params['q'] = query;
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      params,
    );
    final json = await _requestJson('GET', uri);
    final files = json['files'];
    if (files is! List) {
      return const <GoogleDriveApiFile>[];
    }
    return files
        .whereType<Map<Object?, Object?>>()
        .map((raw) => _parseFile(_coerceMap(raw)))
        .toList();
  }

  @override
  Future<GoogleDriveApiFile?> getFileByName(
    String name, {
    String spaces = 'appDataFolder',
  }) async {
    final query = "name='${_escapeQueryValue(name)}' and trashed=false";
    final files = await listFiles(query: query, spaces: spaces);
    if (files.isEmpty) {
      return null;
    }
    return files.first;
  }

  @override
  Future<List<int>> downloadFile(String fileId) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/$fileId',
      <String, String>{'alt': 'media'},
    );
    return _requestBytes('GET', uri);
  }

  @override
  Future<GoogleDriveApiFile> createFile({
    required String name,
    required List<int> bytes,
    String parent = 'appDataFolder',
    String? contentType,
  }) async {
    final boundary = 'cogniread_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode(<String, Object?>{
      'name': name,
      'parents': <String>[parent],
    });
    final body = _buildMultipartBody(
      boundary: boundary,
      metadata: metadata,
      bytes: bytes,
      contentType: contentType ?? 'application/json',
    );
    final uri = Uri.https(
      'www.googleapis.com',
      '/upload/drive/v3/files',
      const <String, String>{'uploadType': 'multipart'},
    );
    final json = await _requestJson(
      'POST',
      uri,
      body: body,
      contentType: 'multipart/related; boundary=$boundary',
    );
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<GoogleDriveApiFile> updateFile({
    required String fileId,
    required List<int> bytes,
    String? contentType,
  }) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/upload/drive/v3/files/$fileId',
      const <String, String>{'uploadType': 'media'},
    );
    final json = await _requestJson(
      'PATCH',
      uri,
      body: bytes,
      contentType: contentType ?? 'application/json',
    );
    return _parseFile(_coerceMap(json));
  }

  @override
  Future<void> deleteFile(String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId');
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
        'Google Drive API error ${response.statusCode}',
        code: 'google_drive_${response.statusCode}',
      );
    }
    return bytes;
  }

  String _escapeQueryValue(String value) {
    return value.replaceAll("'", "\\'");
  }

  GoogleDriveApiFile _parseFile(Map<String, Object?> map) {
    final modified = map['modifiedTime'];
    final size = map['size'];
    return GoogleDriveApiFile(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      modifiedTime:
          modified is String ? DateTime.tryParse(modified) : null,
      size: size is String
          ? int.tryParse(size)
          : (size is num ? size.toInt() : null),
    );
  }

  List<int> _buildMultipartBody({
    required String boundary,
    required String metadata,
    required List<int> bytes,
    required String contentType,
  }) {
    final delimiter = '--$boundary';
    final closeDelimiter = '--$boundary--';
    final buffer = StringBuffer()
      ..writeln(delimiter)
      ..writeln('Content-Type: application/json; charset=UTF-8')
      ..writeln()
      ..writeln(metadata)
      ..writeln(delimiter)
      ..writeln('Content-Type: $contentType')
      ..writeln()
      ..write('');
    final headerBytes = utf8.encode(buffer.toString());
    final footerBytes = utf8.encode('\r\n$closeDelimiter\r\n');
    return <int>[
      ...headerBytes,
      ...bytes,
      ...footerBytes,
    ];
  }

  Map<String, Object?> _coerceMap(Map<Object?, Object?> source) {
    return source.map(
      (key, value) => MapEntry(key?.toString() ?? '', value),
    );
  }
}
