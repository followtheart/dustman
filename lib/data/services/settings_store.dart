import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/app_paths.dart';
import '../../core/utils/logger.dart';

/// JSON-backed key/value store。绿色版下会落到 exe 同目录的 data 文件夹，
/// 安装版下会落到 `%APPDATA%\Dustman`。
class SettingsStore {
  SettingsStore._();

  static SettingsStore? _instance;
  static SettingsStore get instance => _instance ??= SettingsStore._();

  Map<String, dynamic>? _cache;
  Future<void>? _loadFuture;
  Future<void>? _flush;

  Future<void> _ensureLoaded() {
    if (_cache != null) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final f = File(AppPaths.settingsFile());
    if (!await f.exists()) {
      _cache = <String, dynamic>{};
      return;
    }
    try {
      final s = await f.readAsString();
      if (s.trim().isEmpty) {
        _cache = <String, dynamic>{};
        return;
      }
      final decoded = json.decode(s);
      if (decoded is Map<String, dynamic>) {
        _cache = decoded;
      } else {
        _cache = <String, dynamic>{};
      }
    } on Object catch (e) {
      AppLogger.warn('settings load failed: $e', tag: 'SettingsStore');
      _cache = <String, dynamic>{};
    }
  }

  Future<String?> getString(String key) async {
    await _ensureLoaded();
    final v = _cache![key];
    return v is String ? v : null;
  }

  Future<int?> getInt(String key) async {
    await _ensureLoaded();
    final v = _cache![key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<bool?> getBool(String key) async {
    await _ensureLoaded();
    final v = _cache![key];
    return v is bool ? v : null;
  }

  Future<void> setString(String key, String value) async {
    await _ensureLoaded();
    _cache![key] = value;
    await _persist();
  }

  Future<void> setInt(String key, int value) async {
    await _ensureLoaded();
    _cache![key] = value;
    await _persist();
  }

  Future<void> setBool(String key, bool value) async {
    await _ensureLoaded();
    _cache![key] = value;
    await _persist();
  }

  Future<void> remove(String key) async {
    await _ensureLoaded();
    _cache!.remove(key);
    await _persist();
  }

  Future<void> _persist() {
    // 串行化写入，避免并发覆盖。
    final prev = _flush ?? Future.value();
    final next = prev.then((_) async {
      try {
        final f = File(AppPaths.settingsFile());
        await f.parent.create(recursive: true);
        await f.writeAsString(json.encode(_cache));
      } on Object catch (e) {
        AppLogger.warn('settings persist failed: $e', tag: 'SettingsStore');
      }
    });
    _flush = next;
    return next;
  }
}
