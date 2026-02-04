import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AiKind { summary, qa }

enum AiScopeType { book, chapter, selection, note }

enum AiStatus { ready, running, failed }

class AiScope {
  const AiScope({required this.type, required this.id, required this.label});

  final AiScopeType type;
  final String id;
  final String label;

  @override
  bool operator ==(Object other) {
    return other is AiScope &&
        other.type == type &&
        other.id == id &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(type, id, label);
}

class AiConfig {
  const AiConfig({this.baseUrl, this.apiKey, this.model, this.embeddingModel});

  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? embeddingModel;

  bool get isConfigured => baseUrl != null && baseUrl!.trim().isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? embeddingModel,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      embeddingModel: embeddingModel ?? this.embeddingModel,
    );
  }
}

class AiContext {
  const AiContext({required this.text, this.title});

  final String text;
  final String? title;
}

class AiArtifact {
  const AiArtifact({
    required this.id,
    required this.kind,
    required this.scopeType,
    required this.scopeId,
    required this.inputHash,
    required this.status,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.prompt,
    this.model,
    this.error,
  });

  final String id;
  final AiKind kind;
  final AiScopeType scopeType;
  final String scopeId;
  final String inputHash;
  final AiStatus status;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? prompt;
  final String? model;
  final String? error;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'scopeType': scopeType.name,
      'scopeId': scopeId,
      'inputHash': inputHash,
      'status': status.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'prompt': prompt,
      'model': model,
      'error': error,
    };
  }

  static AiArtifact fromMap(Map<String, Object?> map) {
    final createdAt = _parseDate(map['createdAt']);
    final updatedAt = _parseDate(map['updatedAt'], fallback: createdAt);
    return AiArtifact(
      id: map['id'] as String? ?? '',
      kind: _parseKind(map['kind']) ?? AiKind.summary,
      scopeType: _parseScopeType(map['scopeType']) ?? AiScopeType.book,
      scopeId: map['scopeId'] as String? ?? '',
      inputHash: map['inputHash'] as String? ?? '',
      status: _parseStatus(map['status']) ?? AiStatus.ready,
      content: map['content'] as String? ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      prompt: map['prompt'] as String?,
      model: map['model'] as String?,
      error: map['error'] as String?,
    );
  }
}

String aiInputHash({
  required AiKind kind,
  required AiScope scope,
  required String text,
  String? prompt,
}) {
  final normalizedPrompt = prompt?.trim() ?? '';
  final normalizedText = text.trim();
  final payload =
      '${kind.name}|${scope.type.name}|${scope.id}|$normalizedPrompt|$normalizedText';
  return sha1.convert(utf8.encode(payload)).toString();
}

DateTime _parseDate(Object? value, {DateTime? fallback}) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}

AiKind? _parseKind(Object? value) {
  if (value is String) {
    return AiKind.values.cast<AiKind?>().firstWhere(
      (item) => item?.name == value,
      orElse: () => null,
    );
  }
  return null;
}

AiScopeType? _parseScopeType(Object? value) {
  if (value is String) {
    return AiScopeType.values.cast<AiScopeType?>().firstWhere(
      (item) => item?.name == value,
      orElse: () => null,
    );
  }
  return null;
}

AiStatus? _parseStatus(Object? value) {
  if (value is String) {
    return AiStatus.values.cast<AiStatus?>().firstWhere(
      (item) => item?.name == value,
      orElse: () => null,
    );
  }
  return null;
}
