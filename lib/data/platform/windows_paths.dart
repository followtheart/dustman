import 'dart:io';

import 'package:path/path.dart' as p;

/// Windows 上常用的"已知文件夹"路径。非 Windows 平台返回空字符串。
class WindowsPaths {
  WindowsPaths._();

  static String get _env => '';

  static String _envOr(String key) => Platform.environment[key] ?? _env;

  static String get userTemp => _envOr('TEMP');
  static String get windowsTemp =>
      p.join(_envOr('SystemRoot').isEmpty ? r'C:\Windows' : _envOr('SystemRoot'), 'Temp');
  static String get localAppData => _envOr('LOCALAPPDATA');
  static String get appData => _envOr('APPDATA');
  static String get programData => _envOr('ProgramData');
  static String get systemRoot =>
      _envOr('SystemRoot').isEmpty ? r'C:\Windows' : _envOr('SystemRoot');

  /// 浏览器缓存常见路径
  static List<String> get browserCachePaths => [
        // Chrome
        p.join(localAppData, 'Google', 'Chrome', 'User Data', 'Default', 'Cache'),
        p.join(localAppData, 'Google', 'Chrome', 'User Data', 'Default', 'Code Cache'),
        // Edge
        p.join(localAppData, 'Microsoft', 'Edge', 'User Data', 'Default', 'Cache'),
        p.join(localAppData, 'Microsoft', 'Edge', 'User Data', 'Default', 'Code Cache'),
        // Firefox (profile-aware) —— Scanner 内会递归查找
        p.join(localAppData, 'Mozilla', 'Firefox', 'Profiles'),
      ];

  /// 缩略图缓存目录
  static String get thumbnailCacheDir =>
      p.join(localAppData, 'Microsoft', 'Windows', 'Explorer');

  /// Windows 日志目录
  static List<String> get windowsLogDirs => [
        p.join(systemRoot, 'Logs'),
        p.join(systemRoot, 'Panther'),
        p.join(systemRoot, 'SoftwareDistribution', 'Download'),
      ];
}
