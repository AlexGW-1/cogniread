import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/features/ai/data/ai_artifact_store.dart';
import 'package:cogniread/src/features/ai/data/ai_service.dart';
import 'package:flutter/foundation.dart';

class AiController extends ChangeNotifier {
  AiController({
    required AiConfig config,
    required AiArtifactStore store,
    required AiService? service,
    required Future<AiContext> Function(AiScope scope) contextProvider,
  }) : _config = config,
       _store = store,
       _service = service,
       _contextProvider = contextProvider;

  static const int _maxContextChars = 12000;

  final AiArtifactStore _store;
  final AiService? _service;
  final Future<AiContext> Function(AiScope scope) _contextProvider;

  AiConfig _config;
  AiScope? _scope;
  AiContext? _context;
  AiArtifact? _summary;
  List<AiArtifact> _qaItems = const <AiArtifact>[];
  bool _summaryLoading = false;
  bool _qaLoading = false;
  String? _summaryError;
  String? _qaError;
  int _nonce = 0;

  AiConfig get config => _config;
  AiScope? get scope => _scope;
  AiContext? get context => _context;
  AiArtifact? get summary => _summary;
  List<AiArtifact> get qaItems => List<AiArtifact>.unmodifiable(_qaItems);
  bool get summaryLoading => _summaryLoading;
  bool get qaLoading => _qaLoading;
  String? get summaryError => _summaryError;
  String? get qaError => _qaError;

  Future<void> init() async {
    await _store.init();
  }

  Future<void> setScope(AiScope scope) async {
    if (_scope == scope) {
      return;
    }
    _scope = scope;
    _summary = null;
    _qaItems = const <AiArtifact>[];
    _summaryError = null;
    _qaError = null;
    notifyListeners();
    await _loadScope(scope);
  }

  Future<void> refreshConfig(AiConfig config, {bool reload = true}) async {
    _config = config;
    if (reload && _scope != null) {
      await _loadScope(_scope!);
    }
  }

  Future<void> regenerateSummary() async {
    final scope = _scope;
    if (scope == null) {
      return;
    }
    _summary = null;
    _summaryError = null;
    notifyListeners();
    await _requestSummary(scope, force: true);
  }

  Future<void> askQuestion(String question) async {
    final scope = _scope;
    if (scope == null) {
      return;
    }
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (!_config.isConfigured) {
      _qaError = 'AI не настроен. Укажите endpoint в настройках.';
      notifyListeners();
      return;
    }
    final service = _service;
    if (service == null) {
      _qaError = 'AI сервис недоступен.';
      notifyListeners();
      return;
    }
    final context = _context;
    if (context == null) {
      _qaError = 'Контекст не загружен.';
      notifyListeners();
      return;
    }
    final normalizedContext = _limitText(context.text);
    final inputHash = aiInputHash(
      kind: AiKind.qa,
      scope: scope,
      text: normalizedContext,
      prompt: trimmed,
    );
    final cached = await _store.findCached(
      kind: AiKind.qa,
      scopeType: scope.type,
      scopeId: scope.id,
      inputHash: inputHash,
    );
    if (cached != null) {
      _qaItems = <AiArtifact>[cached, ..._qaItems];
      notifyListeners();
      return;
    }
    _qaLoading = true;
    _qaError = null;
    notifyListeners();
    try {
      final result = await service.answer(
        question: trimmed,
        context: normalizedContext,
        scopeId: scope.id,
        scopeType: scope.type.name,
        model: _config.model,
      );
      final now = DateTime.now();
      final artifact = AiArtifact(
        id: _makeArtifactId(),
        kind: AiKind.qa,
        scopeType: scope.type,
        scopeId: scope.id,
        inputHash: inputHash,
        status: AiStatus.ready,
        content: result.content,
        createdAt: now,
        updatedAt: now,
        prompt: trimmed,
        model: result.model ?? _config.model,
      );
      await _store.upsert(artifact);
      _qaItems = <AiArtifact>[artifact, ..._qaItems];
    } catch (error) {
      _qaError = _errorMessage(error);
      Log.d('AI Q&A failed: $error');
    } finally {
      _qaLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadScope(AiScope scope) async {
    final current = ++_nonce;
    _summaryLoading = true;
    _summaryError = null;
    _qaError = null;
    notifyListeners();
    try {
      final context = await _contextProvider(scope);
      if (current != _nonce) {
        return;
      }
      _context = AiContext(
        text: _limitText(context.text),
        title: context.title,
      );
      await _loadQaHistory(scope);
      if (current != _nonce) {
        return;
      }
      await _requestSummary(scope, force: false);
    } catch (error) {
      _summaryError = _errorMessage(error);
      _summaryLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadQaHistory(AiScope scope) async {
    final items = await _store.loadForScope(
      scopeType: scope.type,
      scopeId: scope.id,
      kind: AiKind.qa,
    );
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _qaItems = items;
  }

  Future<void> _requestSummary(AiScope scope, {required bool force}) async {
    if (!_config.isConfigured) {
      _summaryError = 'AI не настроен. Укажите endpoint в настройках.';
      _summaryLoading = false;
      notifyListeners();
      return;
    }
    final service = _service;
    if (service == null) {
      _summaryError = 'AI сервис недоступен.';
      _summaryLoading = false;
      notifyListeners();
      return;
    }
    final context = _context;
    if (context == null) {
      _summaryError = 'Контекст не загружен.';
      _summaryLoading = false;
      notifyListeners();
      return;
    }
    final inputHash = aiInputHash(
      kind: AiKind.summary,
      scope: scope,
      text: context.text,
    );
    if (!force) {
      final cached = await _store.findCached(
        kind: AiKind.summary,
        scopeType: scope.type,
        scopeId: scope.id,
        inputHash: inputHash,
      );
      if (cached != null) {
        _summary = cached;
        _summaryLoading = false;
        notifyListeners();
        return;
      }
    }
    _summaryLoading = true;
    _summaryError = null;
    notifyListeners();
    try {
      final result = await service.summarize(
        text: context.text,
        scopeId: scope.id,
        scopeType: scope.type.name,
        title: context.title,
        model: _config.model,
      );
      final now = DateTime.now();
      final artifact = AiArtifact(
        id: _makeArtifactId(),
        kind: AiKind.summary,
        scopeType: scope.type,
        scopeId: scope.id,
        inputHash: inputHash,
        status: AiStatus.ready,
        content: result.content,
        createdAt: now,
        updatedAt: now,
        model: result.model ?? _config.model,
      );
      await _store.upsert(artifact);
      _summary = artifact;
    } catch (error) {
      _summaryError = _errorMessage(error);
      Log.d('AI summary failed: $error');
    } finally {
      _summaryLoading = false;
      notifyListeners();
    }
  }

  String _limitText(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= _maxContextChars) {
      return trimmed;
    }
    return trimmed.substring(0, _maxContextChars);
  }

  String _errorMessage(Object error) {
    if (error is AiServiceException) {
      final message = _friendlyAiError(error.message);
      if (message.length > 240) {
        return '${message.substring(0, 240)}…';
      }
      return message;
    }
    final raw = error.toString();
    if (raw.length > 240) {
      return '${raw.substring(0, 240)}…';
    }
    return raw;
  }

  String _friendlyAiError(String message) {
    final trimmed = message.trim();
    final match = RegExp(r'AI HTTP (\\d{3})').firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    final code = int.tryParse(match.group(1) ?? '');
    if (code == null) {
      return trimmed;
    }
    switch (code) {
      case 401:
        return 'Доступ запрещен (HTTP 401). Проверь API ключ.';
      case 403:
        return 'Доступ запрещен (HTTP 403). Проверь права ключа/аккаунта.';
      case 404:
        return 'Endpoint не найден (HTTP 404). Проверь URL.';
      case 429:
        return 'Слишком много запросов (HTTP 429). Попробуй позже.';
      default:
        return 'AI ошибка HTTP $code. Проверь настройки и доступ.';
    }
  }
}

String _makeArtifactId() {
  return 'ai-${DateTime.now().microsecondsSinceEpoch}';
}
