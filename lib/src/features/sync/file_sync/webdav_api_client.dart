import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:xml/xml.dart';

class WebDavItem {
  const WebDavItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.modifiedTime,
    this.size,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final DateTime? modifiedTime;
  final int? size;
}

class WebDavAuth {
  const WebDavAuth._({
    this.basicUsername,
    this.basicPassword,
    this.tokenProvider,
  });

  factory WebDavAuth.basic(String username, String password) {
    return WebDavAuth._(basicUsername: username, basicPassword: password);
  }

  factory WebDavAuth.bearer(OAuthTokenProvider tokenProvider) {
    return WebDavAuth._(tokenProvider: tokenProvider);
  }

  final String? basicUsername;
  final String? basicPassword;
  final OAuthTokenProvider? tokenProvider;
}

abstract class WebDavApiClient {
  Future<List<WebDavItem>> listFolder(String path);

  Future<List<int>> download(String path);

  Future<void> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  });

  Future<void> delete(String path);
}

class HttpWebDavApiClient implements WebDavApiClient {
  HttpWebDavApiClient({
    required Uri baseUri,
    WebDavAuth? auth,
    HttpClient? httpClient,
  })  : _baseUri = baseUri,
        _auth = auth,
        _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final WebDavAuth? _auth;
  final HttpClient _httpClient;

  @override
  Future<List<WebDavItem>> listFolder(String path) async {
    final uri = _resolve(path);
    final body = utf8.encode('''
<?xml version="1.0" encoding="utf-8" ?>
<propfind xmlns="DAV:">
  <prop>
    <getcontentlength />
    <getlastmodified />
    <resourcetype />
  </prop>
</propfind>
''');
    final bytes = await _request(
      'PROPFIND',
      uri,
      body: body,
      contentType: 'text/xml',
      headers: const <String, String>{'Depth': '1'},
      allowMultiStatus: true,
    );
    return _parsePropfind(bytes, uri);
  }

  @override
  Future<List<int>> download(String path) async {
    final uri = _resolve(path);
    return _request('GET', uri);
  }

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    final uri = _resolve(path);
    await _request(
      'PUT',
      uri,
      body: bytes,
      contentType: contentType ?? 'application/octet-stream',
    );
  }

  @override
  Future<void> delete(String path) async {
    final uri = _resolve(path);
    await _request('DELETE', uri);
  }

  Future<List<int>> _request(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const <String, String>{},
    bool allowMultiStatus = false,
  }) async {
    final request = await _httpClient.openUrl(method, uri);
    await _applyAuth(request);
    headers.forEach(request.headers.set);
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
    final ok = response.statusCode < 400 ||
        (allowMultiStatus && response.statusCode == 207);
    if (!ok) {
      throw SyncAdapterException(
        'WebDAV error ${response.statusCode}',
        code: 'webdav_${response.statusCode}',
      );
    }
    return bytes;
  }

  Future<void> _applyAuth(HttpClientRequest request) async {
    final auth = _auth;
    if (auth == null) {
      return;
    }
    if (auth.basicUsername != null && auth.basicPassword != null) {
      final raw = '${auth.basicUsername}:${auth.basicPassword}';
      final encoded = base64.encode(utf8.encode(raw));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic $encoded',
      );
      return;
    }
    final tokenProvider = auth.tokenProvider;
    if (tokenProvider != null) {
      final token = await tokenProvider.getToken();
      final valid = requireValidToken(token);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        '${valid.tokenType} ${valid.accessToken}',
      );
    }
  }

  Uri _resolve(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return _baseUri.resolve(normalized);
  }

  List<WebDavItem> _parsePropfind(List<int> bytes, Uri baseUri) {
    if (bytes.isEmpty) {
      return const <WebDavItem>[];
    }
    final document = XmlDocument.parse(utf8.decode(bytes));
    final responses = document.findAllElements('response');
    final items = <WebDavItem>[];
    for (final response in responses) {
      final hrefNode = response.findElements('href').firstOrNull;
      final href = hrefNode?.innerText;
      if (href == null || href.isEmpty) {
        continue;
      }
      final uri = baseUri.resolve(href);
      final path = uri.path;
      if (path == baseUri.path || path == '${baseUri.path}/') {
        continue;
      }
      final prop = response
          .findAllElements('prop')
          .firstOrNull;
      final resourceType = prop?.findAllElements('resourcetype').firstOrNull;
      final isCollection =
          resourceType?.findAllElements('collection').isNotEmpty ?? false;
      final sizeText =
          prop?.findAllElements('getcontentlength').firstOrNull?.innerText;
      final modifiedText =
          prop?.findAllElements('getlastmodified').firstOrNull?.innerText;
      final size = sizeText == null ? null : int.tryParse(sizeText);
      final modified =
          modifiedText == null ? null : HttpDate.parse(modifiedText);
      final name = uri.pathSegments.isEmpty
          ? path
          : uri.pathSegments.last;
      items.add(
        WebDavItem(
          path: uri.path,
          name: name,
          isDirectory: isCollection,
          modifiedTime: modified,
          size: size,
        ),
      );
    }
    return items.where((item) => !item.isDirectory).toList();
  }
}

extension _XmlFirstOrNull on Iterable<XmlElement> {
  XmlElement? get firstOrNull => isEmpty ? null : first;
}
