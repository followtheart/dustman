/// 启动项来源。
///
/// - 注册表 Run/RunOnce：值名 = 显示名，值数据 = 命令行；
/// - Startup 文件夹：用户/全局开始菜单下的 .lnk 快捷方式。
enum StartupSource {
  registryRunCurrentUser,
  registryRunLocalMachine,
  registryRunOnceCurrentUser,
  registryRunOnceLocalMachine,
  registryRunWow6432,
  startupFolderUser,
  startupFolderCommon;

  String get displayName => switch (this) {
        StartupSource.registryRunCurrentUser =>
          'HKCU\\…\\Run',
        StartupSource.registryRunLocalMachine =>
          'HKLM\\…\\Run',
        StartupSource.registryRunOnceCurrentUser =>
          'HKCU\\…\\RunOnce',
        StartupSource.registryRunOnceLocalMachine =>
          'HKLM\\…\\RunOnce',
        StartupSource.registryRunWow6432 =>
          'HKLM\\Wow6432Node\\…\\Run',
        StartupSource.startupFolderUser => '当前用户启动文件夹',
        StartupSource.startupFolderCommon => '全局启动文件夹',
      };

  bool get isRegistry => switch (this) {
        StartupSource.startupFolderUser ||
        StartupSource.startupFolderCommon =>
          false,
        _ => true,
      };

  bool get requiresElevation => switch (this) {
        StartupSource.registryRunLocalMachine ||
        StartupSource.registryRunOnceLocalMachine ||
        StartupSource.registryRunWow6432 ||
        StartupSource.startupFolderCommon =>
          true,
        _ => false,
      };
}

/// 单条开机自启项。
class StartupItem {
  StartupItem({
    required this.id,
    required this.name,
    required this.command,
    required this.source,
    this.registryFullKeyPath,
    this.registryValueName,
    this.shortcutPath,
    this.targetPath,
  });

  /// 唯一 ID：用作 UI 勾选键。
  final String id;

  /// 展示名：注册表值名 / .lnk 文件名。
  final String name;

  /// 完整命令行（注册表值数据）或解析后的 target + args。
  final String command;

  final StartupSource source;

  /// 注册表项的父键完整路径（含 HKLM/HKCU 前缀）。仅注册表项有值。
  final String? registryFullKeyPath;

  /// 注册表值名。仅注册表项有值。
  final String? registryValueName;

  /// .lnk 路径。仅启动文件夹项有值。
  final String? shortcutPath;

  /// 解析后的可执行目标。可能为空（无法解析或为 UWP / shell:）。
  final String? targetPath;
}
