import 'package:hive_flutter/hive_flutter.dart';

class LibraryPreferencesStore {
  static const String _boxName = 'library_prefs';
  static const String _viewModeKey = 'view_mode';
  static const String _deviceIdKey = 'device_id';
  static bool _initialized = false;
  Box<dynamic>? _box;

  Future<void> init() async {
    if (!_initialized) {
      await Hive.initFlutter();
      _initialized = true;
    }
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Box<dynamic> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LibraryPreferencesStore not initialized');
    }
    return box;
  }

  Future<String?> loadViewMode() async {
    return _requireBox.get(_viewModeKey) as String?;
  }

  Future<void> saveViewMode(String mode) async {
    await _requireBox.put(_viewModeKey, mode);
  }

  Future<String?> loadDeviceId() async {
    return _requireBox.get(_deviceIdKey) as String?;
  }

  Future<void> saveDeviceId(String deviceId) async {
    await _requireBox.put(_deviceIdKey, deviceId);
  }
}
