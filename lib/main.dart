import 'dart:async';
import 'dart:ui';

import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/core/utils/app_messenger.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/ai/data/ai_service.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Log.init();
  Log.installErrorHandlers();
  _installAiErrorHandlers();
  runZonedGuarded(() {
    runApp(const CogniReadApp());
  }, (error, stackTrace) {
    if (_handleAiError(error)) {
      return;
    }
    Log.e('Uncaught zone error', error: error, stackTrace: stackTrace);
  });
}

void _installAiErrorHandlers() {
  final defaultBuilder = ErrorWidget.builder;
  ErrorWidget.builder = (details) {
    final error = details.exception;
    if (_isAiError(error)) {
      return _AiErrorWidget(message: _friendlyAiError(error.toString()));
    }
    return defaultBuilder(details);
  };

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final handled = _handleAiError(details.exception);
    if (!handled) {
      previousOnError?.call(details);
    }
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    final handled = _handleAiError(error);
    final previousHandled =
        previousPlatformHandler?.call(error, stackTrace) ?? false;
    return handled || previousHandled;
  };
}

bool _handleAiError(Object error) {
  if (_isAiError(error)) {
    AppMessenger.showMessage(_friendlyAiError(error.toString()));
    return true;
  }
  return false;
}

bool _isAiError(Object error) {
  if (error is AiServiceException) {
    return true;
  }
  final message = error.toString();
  return message.contains('AI HTTP') ||
      message.contains('AiServiceException') ||
      message.contains('AccessDenied.Unpurchased') ||
      message.contains('Access to model denied');
}

String _friendlyAiError(String message) {
  final trimmed = message.trim();
  if (trimmed.contains('AccessDenied.Unpurchased') ||
      trimmed.contains('Access to model denied')) {
    return 'Нет доступа к модели. Выберите другую модель или проверьте права.';
  }
  final match = RegExp(r'AI HTTP (\\d{3})').firstMatch(trimmed);
  if (match != null) {
    final code = int.tryParse(match.group(1) ?? '');
    switch (code) {
      case 401:
        return 'Доступ запрещен (HTTP 401). Проверь API ключ.';
      case 403:
        return 'Доступ запрещен (HTTP 403). Проверь права ключа/аккаунта.';
      case 404:
        return 'Endpoint не найден (HTTP 404). Проверь URL.';
      case 429:
        return 'Слишком много запросов (HTTP 429). Попробуй позже.';
    }
  }
  if (trimmed.length > 240) {
    return '${trimmed.substring(0, 240)}…';
  }
  return trimmed;
}

class _AiErrorWidget extends StatelessWidget {
  const _AiErrorWidget({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F2EA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
