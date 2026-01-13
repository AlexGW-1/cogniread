import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:cogniread/src/core/utils/logger.dart';

class HiveBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await Hive.initFlutter();
    _initialized = true;
  }

  static Future<Box<T>> openBoxSafe<T>(
    String name, {
    int attempts = 5,
    Duration initialDelay = const Duration(milliseconds: 50),
  }) async {
    await ensureInitialized();
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }
    var delay = initialDelay;
    for (var i = 0; i < attempts; i++) {
      try {
        final box = await Hive.openBox<T>(name);
        return box;
      } on FileSystemException catch (e) {
        final osMsg = e.osError?.message;
        final isLockError = e.message.contains('lock failed') ||
            (e.osError?.errorCode == 35) ||
            (osMsg != null && osMsg.contains('Resource temporarily unavailable'));
        Log.d('openBoxSafe: open failed (attempt ${i + 1}/$attempts) for "$name": $e');
        if (!isLockError || i == attempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    // Fallback - try one last time and let exception bubble up if it fails
    return Hive.openBox<T>(name);
  }
}
