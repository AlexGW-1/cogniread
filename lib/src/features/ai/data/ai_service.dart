import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cogniread/src/core/utils/logger.dart';

class AiServiceResult {
  const AiServiceResult({
    required this.content,
    this.model,
    this.raw,
    this.error,
  });

  final String content;
  final String? model;
  final Map<String, Object?>? raw;
  final String? error;

  bool get hasError => error != null && error!.trim().isNotEmpty;
}

class AiEmbeddingResult {
  const AiEmbeddingResult({
    required this.embedding,
    this.model,
    this.raw,
    this.error,
  });

  final List<double> embedding;
  final String? model;
  final Map<String, Object?>? raw;
  final String? error;

  bool get hasError => error != null && error!.trim().isNotEmpty;
}

abstract class AiService {
  Future<AiServiceResult> summarize({
    required String text,
    required String scopeId,
    required String scopeType,
    String? title,
    String? model,
  });

  Future<AiServiceResult> answer({
    required String question,
    required String context,
    required String scopeId,
    required String scopeType,
    String? model,
  });

  Future<AiEmbeddingResult> embed({
    required String input,
    String? model,
  });
}

class AiHttpService implements AiService {
  AiHttpService({
    required Uri baseUri,
    this.apiKey,
    HttpClient? httpClient,
    Duration? timeout,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _httpClient = httpClient ?? HttpClient(),
        _timeout = timeout ?? const Duration(seconds: 60),
        _useGemini = _isGeminiBase(_normalizeBaseUri(baseUri)),
        _useOpenAi =
            _isOpenAiCompatibleBase(_normalizeBaseUri(baseUri)) &&
            !_isGeminiBase(_normalizeBaseUri(baseUri)) {
    _httpClient.connectionTimeout ??= const Duration(seconds: 10);
  }

  final Uri _baseUri;
  final String? apiKey;
  final HttpClient _httpClient;
  final Duration _timeout;
  final bool _useOpenAi;
  final bool _useGemini;

  @override
  Future<AiServiceResult> summarize({
    required String text,
    required String scopeId,
    required String scopeType,
    String? title,
    String? model,
  }) async {
    try {
      if (_useGemini) {
        return await _postGeminiGenerateContent(
          prompt: text,
          instructions: _summaryInstructions(title),
          model: model,
        );
      }
      if (_useOpenAi) {
        return await _postOpenAiResponse(
          input: text,
          instructions: _summaryInstructions(title),
          model: model,
        );
      }
      final payload = <String, Object?>{
        'text': text,
        'scopeId': scopeId,
        'scopeType': scopeType,
        'title': title,
        'model': model,
      };
      return await _postJson('ai/summary', payload);
    } catch (error) {
      return AiServiceResult(
        content: '',
        model: model,
        raw: null,
        error: _errorMessage(error),
      );
    }
  }

  @override
  Future<AiServiceResult> answer({
    required String question,
    required String context,
    required String scopeId,
    required String scopeType,
    String? model,
  }) async {
    try {
      if (_useGemini) {
        final prompt = _qaPrompt(context, question);
        return await _postGeminiGenerateContent(
          prompt: prompt,
          instructions: _qaInstructions(),
          model: model,
        );
      }
      if (_useOpenAi) {
        final prompt = _qaPrompt(context, question);
        return await _postOpenAiResponse(
          input: prompt,
          instructions: _qaInstructions(),
          model: model,
        );
      }
      final payload = <String, Object?>{
        'question': question,
        'context': context,
        'scopeId': scopeId,
        'scopeType': scopeType,
        'model': model,
      };
      return await _postJson('ai/qa', payload);
    } catch (error) {
      return AiServiceResult(
        content: '',
        model: model,
        raw: null,
        error: _errorMessage(error),
      );
    }
  }

  @override
  Future<AiEmbeddingResult> embed({
    required String input,
    String? model,
  }) async {
    try {
      if (_useGemini) {
        return await _postGeminiEmbedContent(input: input, model: model);
      }
      if (_useOpenAi) {
        return await _postOpenAiEmbedding(input: input, model: model);
      }
      final payload = <String, Object?>{
        'text': input,
        'input': input,
        'model': model,
      };
      return await _postEmbeddingJson('ai/embeddings', payload);
    } catch (error) {
      return AiEmbeddingResult(
        embedding: const <double>[],
        model: model,
        raw: null,
        error: _errorMessage(error),
      );
    }
  }

  Future<AiServiceResult> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final uri = _resolve(path);
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey != null && apiKey!.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${apiKey!.trim()}');
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _serviceErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: payload['model']?.toString(),
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _serviceErrorResult(
          'AI response is not JSON',
          model: payload['model']?.toString(),
        );
      }
      final content = _extractContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return _serviceErrorResult(
          'AI response missing content',
          model: decoded['model']?.toString() ?? payload['model']?.toString(),
          raw: decoded,
        );
      }
      final model = decoded['model']?.toString();
      return AiServiceResult(
        content: content.trim(),
        model: model,
        raw: decoded,
      );
    } on TimeoutException {
      return _serviceErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: payload['model']?.toString(),
      );
    } catch (error) {
      Log.d('AI request failed ($path): $error');
      return _serviceErrorResult(
        _errorMessage(error),
        model: payload['model']?.toString(),
      );
    }
  }

  Future<AiEmbeddingResult> _postEmbeddingJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final uri = _resolve(path);
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey != null && apiKey!.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${apiKey!.trim()}');
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _embeddingErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: payload['model']?.toString(),
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _embeddingErrorResult(
          'AI response is not JSON',
          model: payload['model']?.toString(),
        );
      }
      final embedding = _extractEmbedding(decoded);
      if (embedding == null || embedding.isEmpty) {
        return _embeddingErrorResult(
          'AI response missing embedding',
          model: decoded['model']?.toString() ?? payload['model']?.toString(),
          raw: decoded,
        );
      }
      final responseModel = decoded['model']?.toString();
      return AiEmbeddingResult(
        embedding: embedding,
        model: responseModel ?? payload['model']?.toString(),
        raw: decoded,
      );
    } on TimeoutException {
      return _embeddingErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: payload['model']?.toString(),
      );
    } catch (error) {
      Log.d('AI embeddings request failed ($path): $error');
      return _embeddingErrorResult(
        _errorMessage(error),
        model: payload['model']?.toString(),
      );
    }
  }

  Future<AiServiceResult> _postOpenAiResponse({
    required String input,
    required String instructions,
    required String? model,
    bool allowFallback = true,
  }) async {
    final resolvedModel = model?.trim() ?? '';
    if (resolvedModel.isEmpty) {
      return _serviceErrorResult(
        'Для OpenAI Responses API нужно указать модель.',
      );
    }
    final payload = <String, Object?>{
      'model': resolvedModel,
      'input': input,
      'instructions': instructions,
      'text': <String, Object?>{
        'format': <String, Object?>{'type': 'text'},
      },
    };
    final uri = _openAiResponsesUri(_baseUri);
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey == null || apiKey!.trim().isEmpty) {
        return _serviceErrorResult('API key обязателен для OpenAI.');
      }
      request.headers.set('Authorization', 'Bearer ${apiKey!.trim()}');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (allowFallback &&
            (response.statusCode == 404 || response.statusCode == 405)) {
          return _postOpenAiChatCompletions(
            input: input,
            instructions: instructions,
            model: model,
          );
        }
        return _serviceErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: resolvedModel,
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _serviceErrorResult(
          'AI response is not JSON',
          model: resolvedModel,
        );
      }
      final content = _extractOpenAiContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return _serviceErrorResult(
          'AI response missing content',
          model: decoded['model']?.toString() ?? resolvedModel,
          raw: decoded,
        );
      }
      final responseModel = decoded['model']?.toString();
      return AiServiceResult(
        content: content.trim(),
        model: responseModel ?? resolvedModel,
        raw: decoded,
      );
    } on TimeoutException {
      return _serviceErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: resolvedModel,
      );
    } catch (error) {
      Log.d('OpenAI request failed: $error');
      return _serviceErrorResult(_errorMessage(error), model: resolvedModel);
    }
  }

  Future<AiServiceResult> _postOpenAiChatCompletions({
    required String input,
    required String instructions,
    required String? model,
  }) async {
    final resolvedModel = model?.trim() ?? '';
    if (resolvedModel.isEmpty) {
      return _serviceErrorResult(
        'Для OpenAI Chat Completions нужно указать модель.',
      );
    }
    final payload = <String, Object?>{
      'model': resolvedModel,
      'messages': [
        {'role': 'system', 'content': instructions},
        {'role': 'user', 'content': input},
      ],
    };
    final uri = _openAiChatCompletionsUri(_baseUri);
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey == null || apiKey!.trim().isEmpty) {
        return _serviceErrorResult('API key обязателен для OpenAI.');
      }
      request.headers.set('Authorization', 'Bearer ${apiKey!.trim()}');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _serviceErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: resolvedModel,
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _serviceErrorResult(
          'AI response is not JSON',
          model: resolvedModel,
        );
      }
      final content = _extractChatCompletionsContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return _serviceErrorResult(
          'AI response missing content',
          model: decoded['model']?.toString() ?? resolvedModel,
          raw: decoded,
        );
      }
      final responseModel = decoded['model']?.toString();
      return AiServiceResult(
        content: content.trim(),
        model: responseModel ?? resolvedModel,
        raw: decoded,
      );
    } on TimeoutException {
      return _serviceErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: resolvedModel,
      );
    } catch (error) {
      Log.d('OpenAI chat completions request failed: $error');
      return _serviceErrorResult(_errorMessage(error), model: resolvedModel);
    }
  }

  Future<AiEmbeddingResult> _postOpenAiEmbedding({
    required String input,
    required String? model,
  }) async {
    final resolvedModel = model?.trim() ?? '';
    if (resolvedModel.isEmpty) {
      return _embeddingErrorResult(
        'Для OpenAI embeddings нужно указать модель.',
      );
    }
    final payload = <String, Object?>{
      'model': resolvedModel,
      'input': input,
    };
    final uri = _openAiEmbeddingsUri(_baseUri);
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey == null || apiKey!.trim().isEmpty) {
        return _embeddingErrorResult('API key обязателен для OpenAI.');
      }
      request.headers.set('Authorization', 'Bearer ${apiKey!.trim()}');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _embeddingErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: resolvedModel,
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _embeddingErrorResult(
          'AI response is not JSON',
          model: resolvedModel,
        );
      }
      final embedding = _extractEmbedding(decoded);
      if (embedding == null || embedding.isEmpty) {
        return _embeddingErrorResult(
          'AI response missing embedding',
          model: decoded['model']?.toString() ?? resolvedModel,
          raw: decoded,
        );
      }
      final responseModel = decoded['model']?.toString();
      return AiEmbeddingResult(
        embedding: embedding,
        model: responseModel ?? resolvedModel,
        raw: decoded,
      );
    } on TimeoutException {
      return _embeddingErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: resolvedModel,
      );
    } catch (error) {
      Log.d('OpenAI embeddings request failed: $error');
      return _embeddingErrorResult(_errorMessage(error), model: resolvedModel);
    }
  }

  Future<AiEmbeddingResult> _postGeminiEmbedContent({
    required String input,
    required String? model,
  }) async {
    final resolvedModel = model?.trim() ?? '';
    if (resolvedModel.isEmpty) {
      return _embeddingErrorResult('Для Gemini нужно указать модель.');
    }
    if (apiKey == null || apiKey!.trim().isEmpty) {
      return _embeddingErrorResult('API key обязателен для Gemini.');
    }
    final uri = _geminiEmbedContentUri(
      _baseUri,
      resolvedModel,
      apiKey: apiKey!.trim(),
    );
    final payload = <String, Object?>{
      'content': {
        'parts': [
          {'text': input},
        ],
      },
    };
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _embeddingErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: resolvedModel,
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _embeddingErrorResult(
          'AI response is not JSON',
          model: resolvedModel,
        );
      }
      final embedding = _extractEmbedding(decoded);
      if (embedding == null || embedding.isEmpty) {
        return _embeddingErrorResult(
          'AI response missing embedding',
          model: resolvedModel,
          raw: decoded,
        );
      }
      return AiEmbeddingResult(
        embedding: embedding,
        model: resolvedModel,
        raw: decoded,
      );
    } on TimeoutException {
      return _embeddingErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: resolvedModel,
      );
    } catch (error) {
      Log.d('Gemini embeddings request failed: $error');
      return _embeddingErrorResult(_errorMessage(error), model: resolvedModel);
    }
  }

  Future<AiServiceResult> _postGeminiGenerateContent({
    required String prompt,
    required String instructions,
    required String? model,
  }) async {
    final resolvedModel = model?.trim() ?? '';
    if (resolvedModel.isEmpty) {
      return _serviceErrorResult('Для Gemini нужно указать модель.');
    }
    if (apiKey == null || apiKey!.trim().isEmpty) {
      return _serviceErrorResult('API key обязателен для Gemini.');
    }
    final uri = _geminiGenerateContentUri(
      _baseUri,
      resolvedModel,
      apiKey: apiKey!.trim(),
    );
    final payload = <String, Object?>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'systemInstruction': {
        'parts': [
          {'text': instructions},
        ],
      },
    };
    try {
      final request = await _httpClient.openUrl('POST', uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _serviceErrorResult(
          _formatHttpError(
            statusCode: response.statusCode,
            body: body,
            uri: uri,
            reasonPhrase: response.reasonPhrase,
          ),
          model: resolvedModel,
        );
      }
      final decoded = _tryDecode(body);
      if (decoded == null) {
        return _serviceErrorResult(
          'AI response is not JSON',
          model: resolvedModel,
        );
      }
      final content = _extractGeminiContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return _serviceErrorResult(
          'AI response missing content',
          model: resolvedModel,
          raw: decoded,
        );
      }
      return AiServiceResult(
        content: content.trim(),
        model: resolvedModel,
        raw: decoded,
      );
    } on TimeoutException {
      return _serviceErrorResult(
        'AI timeout. Попробуйте уменьшить контекст или выбрать более быструю модель.',
        model: resolvedModel,
      );
    } catch (error) {
      Log.d('Gemini request failed: $error');
      return _serviceErrorResult(_errorMessage(error), model: resolvedModel);
    }
  }

  Uri _resolve(String path) {
    final normalizedBase = _baseUri.toString().trim();
    final base = normalizedBase.endsWith('/')
        ? normalizedBase
        : '$normalizedBase/';
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(base).resolve(normalizedPath);
  }

  Map<String, Object?>? _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  String? _extractContent(Map<String, Object?> decoded) {
    final candidates = <String>[
      'content',
      'answer',
      'summary',
      'text',
      'result',
    ];
    for (final key in candidates) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _extractOpenAiContent(Map<String, Object?> decoded) {
    final output = decoded['output'];
    if (output is List) {
      for (final item in output) {
        if (item is Map) {
          final type = item['type'];
          if (type == 'message') {
            final content = item['content'];
            if (content is List) {
              for (final block in content) {
                if (block is Map) {
                  final blockType = block['type'];
                  if (blockType == 'output_text') {
                    final text = block['text'];
                    if (text is String && text.trim().isNotEmpty) {
                      return text;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    final text = decoded['output_text'];
    if (text is String && text.trim().isNotEmpty) {
      return text;
    }
    return _extractContent(decoded);
  }

  String? _extractChatCompletionsContent(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String && content.trim().isNotEmpty) {
            return content;
          }
        }
        final text = first['text'];
        if (text is String && text.trim().isNotEmpty) {
          return text;
        }
      }
    }
    return _extractContent(decoded);
  }

  String? _extractGeminiContent(Map<String, Object?> decoded) {
    final candidates = decoded['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map) {
        final content = first['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final part = parts.first;
            if (part is Map) {
              final text = part['text'];
              if (text is String && text.trim().isNotEmpty) {
                return text;
              }
            }
          }
        }
      }
    }
    return _extractContent(decoded);
  }
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _errorMessage(Object error) {
  if (error is AiServiceException) {
    return error.message;
  }
  return error.toString();
}

AiServiceResult _serviceErrorResult(
  String message, {
  String? model,
  Map<String, Object?>? raw,
}) {
  return AiServiceResult(
    content: '',
    model: model,
    raw: raw,
    error: message,
  );
}

AiEmbeddingResult _embeddingErrorResult(
  String message, {
  String? model,
  Map<String, Object?>? raw,
}) {
  return AiEmbeddingResult(
    embedding: const <double>[],
    model: model,
    raw: raw,
    error: message,
  );
}

String _compact(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length <= 200) {
    return trimmed;
  }
  return '${trimmed.substring(0, 200)}…';
}

String _formatHttpError({
  required int statusCode,
  required String body,
  required Uri uri,
  String? reasonPhrase,
}) {
  final safeUri = _stripQuery(uri);
  final details = <String>[];
  final reason = reasonPhrase?.trim() ?? '';
  if (reason.isNotEmpty) {
    details.add(reason);
  }
  final compactBody = _compact(body);
  if (compactBody.isNotEmpty) {
    details.add(compactBody);
  }
  if (details.isEmpty) {
    details.add('пустой ответ');
  }
  return 'AI HTTP $statusCode: ${details.join(' • ')} '
      '(endpoint ${safeUri.toString()})';
}

Uri _stripQuery(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}

Uri _normalizeBaseUri(Uri uri) {
  final cleaned = uri.replace(queryParameters: const {}, fragment: null);
  var path = cleaned.path;
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final lower = path.toLowerCase();
  const suffixes = [
    '/ai/summary',
    '/ai/qa',
    '/ai/embeddings',
    '/responses',
    '/chat/completions',
    '/embeddings',
  ];
  for (final suffix in suffixes) {
    if (lower.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  return cleaned.replace(path: path);
}

bool _isOpenAiCompatibleBase(Uri baseUri) {
  final host = baseUri.host.toLowerCase();
  if (host.contains('openai.com') || host.contains('groq.com')) {
    return true;
  }
  final path = baseUri.path.toLowerCase();
  if (path.contains('/openai/')) {
    return true;
  }
  if (path.contains('compatible-mode')) {
    return true;
  }
  return false;
}

bool _isGeminiBase(Uri baseUri) {
  final host = baseUri.host.toLowerCase();
  if (host.contains('generativelanguage.googleapis.com') ||
      host.contains('ai.google.dev')) {
    return true;
  }
  return false;
}

Uri _openAiResponsesUri(Uri baseUri) {
  final scheme = baseUri.scheme.isEmpty ? 'https' : baseUri.scheme;
  final host = baseUri.host.isEmpty ? 'api.openai.com' : baseUri.host;
  var path = baseUri.path.trim();
  if (path.isEmpty) {
    path = '/v1';
  }
  if (path.endsWith('/openai')) {
    path = '$path/v1';
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/responses')) {
    path = '$path/responses';
  }
  return Uri(
    scheme: scheme,
    host: host,
    port: baseUri.hasPort ? baseUri.port : null,
    path: path,
  );
}

Uri _openAiEmbeddingsUri(Uri baseUri) {
  final scheme = baseUri.scheme.isEmpty ? 'https' : baseUri.scheme;
  final host = baseUri.host.isEmpty ? 'api.openai.com' : baseUri.host;
  var path = baseUri.path.trim();
  if (path.isEmpty) {
    path = '/v1';
  }
  if (path.endsWith('/openai')) {
    path = '$path/v1';
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/embeddings')) {
    path = '$path/embeddings';
  }
  return Uri(
    scheme: scheme,
    host: host,
    port: baseUri.hasPort ? baseUri.port : null,
    path: path,
  );
}

Uri _openAiChatCompletionsUri(Uri baseUri) {
  final scheme = baseUri.scheme.isEmpty ? 'https' : baseUri.scheme;
  final host = baseUri.host.isEmpty ? 'api.openai.com' : baseUri.host;
  var path = baseUri.path.trim();
  if (path.isEmpty) {
    path = '/v1';
  }
  if (path.endsWith('/openai')) {
    path = '$path/v1';
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/chat/completions')) {
    path = '$path/chat/completions';
  }
  return Uri(
    scheme: scheme,
    host: host,
    port: baseUri.hasPort ? baseUri.port : null,
    path: path,
  );
}

Uri _geminiGenerateContentUri(
  Uri baseUri,
  String model, {
  required String apiKey,
}) {
  var path = baseUri.path.trim();
  if (path.isEmpty || path == '/') {
    path = '/v1beta';
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.contains('/v1')) {
    path = '/v1beta';
  }
  var normalizedModel = model.trim();
  if (normalizedModel.startsWith('models/')) {
    normalizedModel = normalizedModel.substring('models/'.length);
  }
  final targetPath = '$path/models/$normalizedModel:generateContent';
  final query = Map<String, String>.from(baseUri.queryParameters);
  query['key'] = apiKey;
  return baseUri.replace(path: targetPath, queryParameters: query);
}

Uri _geminiEmbedContentUri(
  Uri baseUri,
  String model, {
  required String apiKey,
}) {
  var path = baseUri.path.trim();
  if (path.isEmpty || path == '/') {
    path = '/v1beta';
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.contains('/v1')) {
    path = '/v1beta';
  }
  var normalizedModel = model.trim();
  if (normalizedModel.startsWith('models/')) {
    normalizedModel = normalizedModel.substring('models/'.length);
  }
  final targetPath = '$path/models/$normalizedModel:embedContent';
  final query = Map<String, String>.from(baseUri.queryParameters);
  query['key'] = apiKey;
  return baseUri.replace(path: targetPath, queryParameters: query);
}

List<double>? _extractEmbedding(Map<String, Object?> decoded) {
  final direct = decoded['embedding'];
  if (direct is List) {
    return _coerceEmbeddingList(direct);
  }
  if (direct is Map) {
    final values = direct['values'];
    if (values is List) {
      return _coerceEmbeddingList(values);
    }
  }
  final data = decoded['data'];
  if (data is List && data.isNotEmpty) {
    final first = data.first;
    if (first is Map) {
      final embedded = first['embedding'];
      if (embedded is List) {
        return _coerceEmbeddingList(embedded);
      }
    }
  }
  final embeddings = decoded['embeddings'];
  if (embeddings is List && embeddings.isNotEmpty) {
    final first = embeddings.first;
    if (first is Map) {
      final values = first['values'];
      if (values is List) {
        return _coerceEmbeddingList(values);
      }
    } else if (first is List) {
      return _coerceEmbeddingList(first);
    }
  }
  final vector = decoded['vector'];
  if (vector is List) {
    return _coerceEmbeddingList(vector);
  }
  return null;
}

List<double> _coerceEmbeddingList(List<dynamic> values) {
  return values
      .map((value) => value is num ? value.toDouble() : double.nan)
      .where((value) => value.isFinite)
      .toList(growable: false);
}

String _summaryInstructions(String? title) {
  final prefix = 'Сделай краткую, структурированную сводку текста.';
  if (title == null || title.trim().isEmpty) {
    return prefix;
  }
  return '$prefix Тема: ${title.trim()}.';
}

String _qaInstructions() {
  return 'Отвечай на вопрос строго по контексту. Если ответа нет, скажи, что данных недостаточно.';
}

String _qaPrompt(String context, String question) {
  return 'Контекст:\n$context\n\nВопрос:\n$question';
}
