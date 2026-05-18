import 'dart:io';

import 'package:path/path.dart' as p;

import 'logger.dart';

/// Dustman 数据目录与运行模式（绿色版 / 安装版）。
///
/// 判定方式：可执行文件所在目录存在 `portable.flag` 文件即视为绿色版，
/// 所有偏好与日志统一写到 `<exe_dir>\data`；否则写到 `%APPDATA%\Dustman`。
class AppPaths {
  AppPaths._();

  static bool _initialized = false;
  static bool _portable = false;
  static late String _dataDir;

  static const _portableFlagFile = 'portable.flag';
  static const _appName = 'Dustman';

  /// 是否绿色版（portable）。未初始化时返回 false。
  static bool get isPortable => _portable;

  /// Dustman 主数据目录（保证存在）。
  static String get dataDir {
    if (!_initialized) {
      _initSync();
    }
    return _dataDir;
  }

  /// 日志目录。
  static String get logDir {
    final d = p.join(dataDir, 'logs');
    _ensureDir(d);
    return d;
  }

  /// 用户设置 JSON 文件路径。
  static String settingsFile() => p.join(dataDir, 'settings.json');

  /// 计划任务状态 JSON 文件路径。
  static String scheduleStateFile() => p.join(dataDir, 'schedule.json');

  /// FileClaw 认证文件（DPAPI 加密的 refresh_token）。仅 Pro 版用到。
  static String authFile() => p.join(dataDir, 'auth.bin');

  static void _initSync() {
    _initialized = true;
    final exeDir = _executableDirectory();
    if (exeDir != null) {
      final flag = File(p.join(exeDir, _portableFlagFile));
      if (flag.existsSync()) {
        _portable = true;
        _dataDir = p.join(exeDir, 'data');
        _ensureDir(_dataDir);
        AppLogger.info('portable mode at $_dataDir', tag: 'AppPaths');
        return;
      }
    }
    _portable = false;
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      _dataDir = p.join(appData, _appName);
    } else {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      _dataDir = p.join(home, '.${_appName.toLowerCase()}');
    }
    _ensureDir(_dataDir);
    AppLogger.info('installed mode at $_dataDir', tag: 'AppPaths');
  }

  static String? _executableDirectory() {
    try {
      return p.dirname(Platform.resolvedExecutable);
    } on Object {
      return null;
    }
  }

  static void _ensureDir(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } on FileSystemException catch (e) {
      AppLogger.warn(
        'failed to create $path: ${e.osError?.message ?? e.message}',
        tag: 'AppPaths',
      );
    }
  }
}
