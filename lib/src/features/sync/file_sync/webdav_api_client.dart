import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/features/sync/file_sync/oauth.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:cogniread/src/core/utils/logger.dart';
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

class WebDavOptionsResult {
  const WebDavOptionsResult({
    required this.hasDav,
    required this.allowsPropfind,
    required this.allowsMkcol,
  });

  final bool hasDav;
  final bool allowsPropfind;
  final bool allowsMkcol;
}

class WebDavRawResponse {
  const WebDavRawResponse({
    required this.statusCode,
    required this.bytes,
  });

  final int statusCode;
  final List<int> bytes;
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

  Future<List<int>?> download(
    String path, {
    bool allowNotFound = false,
  });

  Future<void> upload({
    required String path,
    required List<int> bytes,
    String? contentType,
  });

  Future<WebDavOptionsResult> options(String path);

  Future<void> createFolder(String path);

  Future<void> delete(String path);
}

class HttpWebDavApiClient implements WebDavApiClient {
  HttpWebDavApiClient({
    required Uri baseUri,
    WebDavAuth? auth,
    Duration requestTimeout = const Duration(seconds: 20),
    Duration transferTimeout = const Duration(minutes: 2),
    bool allowInsecure = false,
    HttpClient? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _auth = auth,
        _requestTimeout = requestTimeout,
        _transferTimeout = transferTimeout,
        _allowInsecure = allowInsecure,
        _httpClient = httpClient ?? HttpClient() {
    if (_allowInsecure) {
      _httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    }
  }

  final Uri _baseUri;
  final WebDavAuth? _auth;
  final Duration _requestTimeout;
  final Duration _transferTimeout;
  final bool _allowInsecure;
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
      timeout: _requestTimeout,
    );
    return _parsePropfind(bytes, uri);
  }

  Future<WebDavRawResponse> propfindRaw(
    String path, {
    String depth = '1',
  }) async {
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
    return _requestRaw(
      'PROPFIND',
      uri,
      body: body,
      contentType: 'text/xml',
      headers: <String, String>{'Depth': depth},
      timeout: _requestTimeout,
    );
  }

  Future<WebDavRawResponse> mkcolRaw(String path) async {
    final normalized = path.endsWith('/') ? path : '$path/';
    final uri = _resolve(normalized);
    return _requestRaw(
      'MKCOL',
      uri,
      timeout: _requestTimeout,
    );
  }

  @override
  Future<List<int>?> download(
    String path, {
    bool allowNotFound = false,
  }) async {
    final uri = _resolve(path);
    return _requestDownload(
      uri,
      allowNotFound: allowNotFound,
      timeout: _transferTimeout,
    );
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
      timeout: _transferTimeout,
    );
  }

  @override
  Future<WebDavOptionsResult> options(String path) async {
    final uri = _resolve(path);
    return _requestOptions(uri, timeout: _requestTimeout);
  }

  @override
  Future<void> createFolder(String path) async {
    final normalized = path.endsWith('/') ? path : '$path/';
    try {
      final response = await mkcolRaw(normalized);
      if (response.statusCode < 400) {
        return;
      }
      if (response.statusCode == 405) {
        Log.d('WebDAV MKCOL ignored (405) for path: $path');
        return;
      }
      if (response.statusCode == 409) {
        try {
          await listFolder(normalized);
          Log.d('WebDAV MKCOL ignored (409) for existing path: $path');
          return;
        } on SyncAdapterException {
          rethrow;
        }
      }
      throw SyncAdapterException(
        'WebDAV error ${response.statusCode}',
        code: 'webdav_${response.statusCode}',
      );
    } on SyncAdapterException {
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final uri = _resolve(path);
    await _request('DELETE', uri, timeout: _requestTimeout);
  }

  Future<List<int>> _request(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const <String, String>{},
    bool allowMultiStatus = false,
    Duration? timeout,
  }) async {
    final response = await _requestRaw(
      method,
      uri,
      body: body,
      contentType: contentType,
      headers: headers,
      timeout: timeout,
    );
    final ok = response.statusCode < 400 ||
        (allowMultiStatus && response.statusCode == 207);
    if (!ok) {
      throw SyncAdapterException(
        'WebDAV error ${response.statusCode}',
        code: 'webdav_${response.statusCode}',
      );
    }
    return response.bytes;
  }

  Future<WebDavRawResponse> _requestRaw(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const <String, String>{},
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    final stopwatch = Stopwatch()..start();
    Log.d('WebDAV request: $method $uri');
    try {
      final request =
          await _httpClient.openUrl(method, uri).timeout(effectiveTimeout);
      await _applyAuth(request);
      headers.forEach(request.headers.set);
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
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
        'WebDAV response: $method $uri -> ${response.statusCode} '
        '(${bytes.length} bytes, ${stopwatch.elapsedMilliseconds} ms)',
      );
      return WebDavRawResponse(
        statusCode: response.statusCode,
        bytes: bytes,
      );
    } on TimeoutException {
      Log.d(
        'WebDAV timeout: $method $uri after '
        '${effectiveTimeout.inSeconds}s',
      );
      throw SyncAdapterException(
        'WebDAV timeout',
        code: 'webdav_timeout',
      );
    } on HandshakeException catch (error) {
      Log.d('WebDAV SSL error: $method $uri -> $error');
      throw SyncAdapterException(
        'WebDAV SSL error',
        code: 'webdav_ssl',
      );
    } on SocketException catch (error) {
      Log.d('WebDAV network error: $method $uri -> $error');
      throw SyncAdapterException(
        'WebDAV network error: ${error.message}',
        code: 'webdav_socket',
      );
    } on HttpException catch (error) {
      Log.d('WebDAV HTTP error: $method $uri -> $error');
      throw SyncAdapterException(
        'WebDAV HTTP error: ${error.message}',
        code: 'webdav_http',
      );
    }
  }

  Future<WebDavOptionsResult> _requestOptions(
    Uri uri, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    final stopwatch = Stopwatch()..start();
    Log.d('WebDAV request: OPTIONS $uri');
    try {
      final request =
          await _httpClient.openUrl('OPTIONS', uri).timeout(effectiveTimeout);
      await _applyAuth(request);
      final response = await request.close().timeout(effectiveTimeout);
      final bytes = await response
          .fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          )
          .timeout(effectiveTimeout);
      final ok = response.statusCode < 400;
      Log.d(
        'WebDAV response: OPTIONS $uri -> ${response.statusCode} '
        '(${bytes.length} bytes, ${stopwatch.elapsedMilliseconds} ms)',
      );
      if (!ok) {
        throw SyncAdapterException(
          'WebDAV error ${response.statusCode}',
          code: 'webdav_${response.statusCode}',
        );
      }
      final dav = response.headers.value('dav');
      final allowRaw = response.headers.value('allow') ??
          response.headers.value('public') ??
          '';
      final allows = allowRaw
          .split(',')
          .map((value) => value.trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      return WebDavOptionsResult(
        hasDav: dav != null && dav.trim().isNotEmpty,
        allowsPropfind: allows.contains('PROPFIND'),
        allowsMkcol: allows.contains('MKCOL'),
      );
    } on TimeoutException {
      Log.d(
        'WebDAV timeout: OPTIONS $uri after '
        '${effectiveTimeout.inSeconds}s',
      );
      throw SyncAdapterException(
        'WebDAV timeout',
        code: 'webdav_timeout',
      );
    } on HandshakeException catch (error) {
      Log.d('WebDAV SSL error: OPTIONS $uri -> $error');
      throw SyncAdapterException(
        'WebDAV SSL error',
        code: 'webdav_ssl',
      );
    } on SocketException catch (error) {
      Log.d('WebDAV network error: OPTIONS $uri -> $error');
      throw SyncAdapterException(
        'WebDAV network error: ${error.message}',
        code: 'webdav_socket',
      );
    } on HttpException catch (error) {
      Log.d('WebDAV HTTP error: OPTIONS $uri -> $error');
      throw SyncAdapterException(
        'WebDAV HTTP error: ${error.message}',
        code: 'webdav_http',
      );
    }
  }

  Future<List<int>?> _requestDownload(
    Uri uri, {
    required bool allowNotFound,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    final stopwatch = Stopwatch()..start();
    Log.d('WebDAV request: GET $uri');
    try {
      final request =
          await _httpClient.openUrl('GET', uri).timeout(effectiveTimeout);
      await _applyAuth(request);
      final response = await request.close().timeout(effectiveTimeout);
      final bytes = await response
          .fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          )
          .timeout(effectiveTimeout);
      Log.d(
        'WebDAV response: GET $uri -> ${response.statusCode} '
        '(${bytes.length} bytes, ${stopwatch.elapsedMilliseconds} ms)',
      );
      if (allowNotFound && response.statusCode == 404) {
        return null;
      }
      final ok = response.statusCode < 400;
      if (!ok) {
        throw SyncAdapterException(
          'WebDAV error ${response.statusCode}',
          code: 'webdav_${response.statusCode}',
        );
      }
      return bytes;
    } on TimeoutException {
      Log.d(
        'WebDAV timeout: GET $uri after ${effectiveTimeout.inSeconds}s',
      );
      throw SyncAdapterException(
        'WebDAV timeout',
        code: 'webdav_timeout',
      );
    } on HandshakeException catch (error) {
      Log.d('WebDAV SSL error: GET $uri -> $error');
      throw SyncAdapterException(
        'WebDAV SSL error',
        code: 'webdav_ssl',
      );
    } on SocketException catch (error) {
      Log.d('WebDAV network error: GET $uri -> $error');
      throw SyncAdapterException(
        'WebDAV network error: ${error.message}',
        code: 'webdav_socket',
      );
    } on HttpException catch (error) {
      Log.d('WebDAV HTTP error: GET $uri -> $error');
      throw SyncAdapterException(
        'WebDAV HTTP error: ${error.message}',
        code: 'webdav_http',
      );
    }
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

  static Uri _normalizeBaseUri(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '$path/');
  }

  List<WebDavItem> _parsePropfind(List<int> bytes, Uri baseUri) {
    if (bytes.isEmpty) {
      return const <WebDavItem>[];
    }
    final raw = utf8.decode(bytes);
    final lower = raw.toLowerCase();
    final looksLikeHtml = lower.contains('<html') ||
        lower.contains('<head') ||
        lower.contains('<body') ||
        lower.contains('<!doctype html');
    if (looksLikeHtml) {
      throw SyncAdapterException(
        'WebDAV response is HTML. Check base URL and credentials.',
        code: 'webdav_invalid_xml',
      );
    }
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(raw);
    } catch (_) {
      throw SyncAdapterException(
        'WebDAV response is not valid XML.',
        code: 'webdav_invalid_xml',
      );
    }

    Iterable<XmlElement> elementsByLocalName(XmlNode node, String name) {
      return node.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == name);
    }

    final responses = elementsByLocalName(document, 'response');
    final items = <WebDavItem>[];
    for (final response in responses) {
      final href = elementsByLocalName(response, 'href').firstOrNull?.innerText;
      if (href == null || href.isEmpty) {
        continue;
      }
      final uri = baseUri.resolve(href);
      final path = uri.path;
      if (path == baseUri.path || path == '${baseUri.path}/') {
        continue;
      }
      final prop = elementsByLocalName(response, 'prop').firstOrNull;
      final resourceType = prop == null
          ? null
          : elementsByLocalName(prop, 'resourcetype').firstOrNull;
      final isCollection =
          resourceType == null
              ? false
              : elementsByLocalName(resourceType, 'collection').isNotEmpty;
      final sizeText =
          prop == null
              ? null
              : elementsByLocalName(prop, 'getcontentlength')
                  .firstOrNull
                  ?.innerText;
      final modifiedText =
          prop == null
              ? null
              : elementsByLocalName(prop, 'getlastmodified').firstOrNull?.innerText;
      final size = sizeText == null ? null : int.tryParse(sizeText);
      DateTime? modified;
      if (modifiedText != null) {
        try {
          modified = HttpDate.parse(modifiedText);
        } catch (_) {
          modified = null;
        }
      }
      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      final name = segments.isEmpty ? path : segments.last;
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
    return items;
  }
}

extension _XmlFirstOrNull on Iterable<XmlElement> {
  XmlElement? get firstOrNull => isEmpty ? null : first;
}
