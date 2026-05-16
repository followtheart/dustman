import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../domain/entities/startup_item.dart';
import '../platform/registry_reader.dart';
import '../platform/shortcut_resolver.dart';
import '../platform/windows_paths.dart';

/// 扫描所有"经典"自启动来源：
/// - HKCU/HKLM 下 Run / RunOnce / WOW6432Node\Run；
/// - 当前用户 / 全局 启动文件夹下的 .lnk。
///
/// 故意不读 Task Scheduler / Services / WMI —— 这些归属"服务管理"，是 v0.3+。
class StartupItemScanner {
  StartupItemScanner();

  /// 同步入口，便于在 Isolate 外直接 await。
  /// 内部会临时初始化 COM 解析 .lnk。
  Future<List<StartupItem>> scan() async {
    if (!Platform.isWindows) return const [];
    final out = <StartupItem>[];
    out.addAll(_scanRegistry(
      root: RegRoot.hkcu,
      subKey: r'Software\Microsoft\Windows\CurrentVersion\Run',
      source: StartupSource.registryRunCurrentUser,
    ));
    out.addAll(_scanRegistry(
      root: RegRoot.hkcu,
      subKey: r'Software\Microsoft\Windows\CurrentVersion\RunOnce',
      source: StartupSource.registryRunOnceCurrentUser,
    ));
    out.addAll(_scanRegistry(
      root: RegRoot.hklm,
      subKey: r'Software\Microsoft\Windows\CurrentVersion\Run',
      source: StartupSource.registryRunLocalMachine,
    ));
    out.addAll(_scanRegistry(
      root: RegRoot.hklm,
      subKey: r'Software\Microsoft\Windows\CurrentVersion\RunOnce',
      source: StartupSource.registryRunOnceLocalMachine,
    ));
    out.addAll(_scanRegistry(
      root: RegRoot.hklm,
      subKey: r'Software\Microsoft\Windows\CurrentVersion\Run',
      source: StartupSource.registryRunWow6432,
      view: RegView.v32,
    ));

    await ShortcutResolver.runCoInitialized(() async {
      out.addAll(_scanStartupFolder(
        dirPath: _userStartupDir(),
        source: StartupSource.startupFolderUser,
      ));
      out.addAll(_scanStartupFolder(
        dirPath: _commonStartupDir(),
        source: StartupSource.startupFolderCommon,
      ));
    });

    return out;
  }

  List<StartupItem> _scanRegistry({
    required RegRoot root,
    required String subKey,
    required StartupSource source,
    RegView view = RegView.v64,
  }) {
    final out = <StartupItem>[];
    final key = RegKey.open(root, subKey, view: view);
    if (key == null) return out;
    try {
      for (final v in key.enumValues()) {
        final cmd = key.readString(v.name) ?? '';
        if (cmd.isEmpty) continue;
        final full = '${root.prefix}\\$subKey';
        out.add(StartupItem(
          id: '${source.name}::$full::${v.name}',
          name: v.name,
          command: cmd,
          source: source,
          registryFullKeyPath: full,
          registryValueName: v.name,
          targetPath: _extractExe(cmd),
        ));
      }
    } finally {
      key.close();
    }
    return out;
  }

  List<StartupItem> _scanStartupFolder({
    required String dirPath,
    required StartupSource source,
  }) {
    final out = <StartupItem>[];
    if (dirPath.isEmpty) return out;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return out;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      AppLogger.warn(
        'startup folder list failed: ${e.osError?.message}',
        tag: 'StartupScanner',
      );
      return out;
    }
    for (final entity in entries) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.lnk')) continue;
      String target = '';
      String args = '';
      final info = ShortcutResolver.resolve(entity.path);
      if (info != null) {
        target = info.target;
        args = info.arguments;
      }
      final name = p.basenameWithoutExtension(entity.path);
      final cmd = args.isEmpty ? target : '$target $args';
      out.add(StartupItem(
        id: '${source.name}::${entity.path}',
        name: name,
        command: cmd,
        source: source,
        shortcutPath: entity.path,
        targetPath: target.isEmpty ? null : target,
      ));
    }
    return out;
  }

  static String _userStartupDir() {
    final appData = WindowsPaths.appData;
    if (appData.isEmpty) return '';
    return p.join(
        appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
  }

  static String _commonStartupDir() {
    final programData = WindowsPaths.programData;
    if (programData.isEmpty) return '';
    return p.join(programData, 'Microsoft', 'Windows', 'Start Menu',
        'Programs', 'Startup');
  }

  /// 从命令行字符串里粗略提取可执行文件路径（带引号或第一个 token）。
  static String? _extractExe(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('"')) {
      final end = trimmed.indexOf('"', 1);
      if (end > 1) return trimmed.substring(1, end);
    }
    final sp = trimmed.indexOf(' ');
    return sp > 0 ? trimmed.substring(0, sp) : trimmed;
  }
}
