import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Log {
  static File? _file;
  static IOSink? _sink;
  static bool _initialized = false;
  static bool _fileLoggingEnabled = true;
  static Future<void> _fileWriteChain = Future<void>.value();
  static final RegExp _urlUserInfo = RegExp(
    r'(https?://)([^\s/@]+:[^\s@]+)@',
    caseSensitive: false,
  );
  static final List<RegExp> _redactions = <RegExp>[
    RegExp(
      r'access[_-]?token\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'refresh[_-]?token\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'client(?:[_-\s]?|)secret\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'password\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'authorization\s*[:=]\s*bearer\s+[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'authorization\s*[:=]\s*oauth\s+[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'authorization\s*[:=]\s*basic\s+[a-z0-9+/=]+',
      caseSensitive: false,
    ),
    RegExp(
      r'\bbasic\s+[a-z0-9+/=]{20,}',
      caseSensitive: false,
    ),
    RegExp(
      r'\bbearer\s+[a-z0-9\-._~+/=]{20,}',
      caseSensitive: false,
    ),
    RegExp(
      r'(access_token|refresh_token)=[^&\s]+',
      caseSensitive: false,
    ),
    RegExp(
      r'"(access_token|refresh_token)"\s*:\s*"[^"]+"',
      caseSensitive: false,
    ),
    RegExp(
      r"'(access_token|refresh_token)'\s*:\s*'[^']+'",
      caseSensitive: false,
    ),
    RegExp(
      r'"client_secret"\s*:\s*"[^"]+"',
      caseSensitive: false,
    ),
    RegExp(
      r"'client_secret'\s*:\s*'[^']+'",
      caseSensitive: false,
    ),
    RegExp(
      r'"password"\s*:\s*"[^"]+"',
      caseSensitive: false,
    ),
    RegExp(
      r"'password'\s*:\s*'[^']+'",
      caseSensitive: false,
    ),
  ];

  static Future<void> init({String fileName = 'cogniread.log'}) async {
    if (_initialized) {
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, fileName));
      await file.parent.create(recursive: true);
      _file = file;
      _sink = file.openWrite(mode: FileMode.append);
      _fileLoggingEnabled = true;
      _fileWriteChain = Future<void>.value();
      _initialized = true;
      d('Logger initialized: ${file.path}');
    } catch (error, stackTrace) {
      _initialized = true;
      dev.log(
        'Logger init failed: $error',
        name: 'CogniRead',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static String? get logFilePath => _file?.path;

  static void installErrorHandlers() {
    FlutterError.onError = (details) {
      e(
        'FlutterError',
        error: details.exception,
        stackTrace: details.stack,
        context: details.context?.toDescription(),
        informationCollector: details.informationCollector,
      );
      if (!kReleaseMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      e(
        'Uncaught error',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    };
  }

  static void d(String message) => _log('D', message);

  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _log('W', message, error: error, stackTrace: stackTrace);
  }

  static void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? context,
    Iterable<DiagnosticsNode> Function()? informationCollector,
  }) {
    final extra = <String>[];
    if (context != null && context.trim().isNotEmpty) {
      extra.add('context=$context');
    }
    if (informationCollector != null) {
      try {
        final info = informationCollector()
            .map((node) => node.toStringDeep())
            .join('\n');
        if (info.trim().isNotEmpty) {
          extra.add(info.trim());
        }
      } catch (_) {}
    }
    final suffix = extra.isEmpty ? '' : '\n${extra.join('\n')}';
    _log(
      'E',
      '$message$suffix',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _log(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final sanitized = _sanitize(message);
    final sanitizedError =
        error == null ? null : _sanitize(error.toString()).trim();
    final sanitizedStackTrace =
        stackTrace == null ? null : _sanitize(stackTrace.toString());
    dev.log(
      sanitized,
      name: 'CogniRead',
      error: sanitizedError,
      stackTrace:
          sanitizedStackTrace == null
              ? null
              : StackTrace.fromString(sanitizedStackTrace),
    );
    final sink = _sink;
    if (sink != null && _fileLoggingEnabled) {
      final ts = DateTime.now().toIso8601String();
      final lines = <String>[
        '[$ts][$level] $sanitized',
        if (sanitizedError != null && sanitizedError.isNotEmpty)
          '  error: $sanitizedError',
        if (sanitizedStackTrace != null && sanitizedStackTrace.isNotEmpty)
          '  stack: $sanitizedStackTrace',
      ];
      _enqueueFileWrite(lines);
    }
  }

  static void _enqueueFileWrite(List<String> lines) {
    final sink = _sink;
    if (sink == null || !_fileLoggingEnabled) {
      return;
    }
    _fileWriteChain = _fileWriteChain.then((_) async {
      if (!_fileLoggingEnabled) {
        return;
      }
      try {
        for (final line in lines) {
          sink.writeln(line);
        }
        await sink.flush();
      } catch (error, stackTrace) {
        _fileLoggingEnabled = false;
        dev.log(
          'File logging disabled: $error',
          name: 'CogniRead',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  static String _sanitize(String message) {
    var result = message;
    result = result.replaceAllMapped(_urlUserInfo, (match) {
      return '${match.group(1)}[REDACTED]@';
    });
    for (final pattern in _redactions) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }
    return result;
  }
}
