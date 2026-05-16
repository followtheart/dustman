import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../platform/windows_paths.dart';

/// 通过 `reg.exe export` 导出注册表键到 .reg 文件。
///
/// 设计要点：
/// - 备份失败必须**取消该项删除**（上游 [ResidueCleanerService] 处理）；
/// - 同一次清理共用一个时间戳目录 → 便于一次性回滚。
class RegistryBackupService {
  RegistryBackupService._(this.sessionDir);

  /// 当前清理会话的备份目录（已 mkdir）。
  final String sessionDir;

  /// 创建一次新的备份会话：`%APPDATA%\Dustman\backups\<yyyyMMdd-HHmmss>`。
  static Future<RegistryBackupService> openSession() async {
    final base = p.join(
      WindowsPaths.appData.isEmpty
          ? Directory.systemTemp.path
          : WindowsPaths.appData,
      'Dustman',
      'backups',
    );
    final stamp = _timestamp(DateTime.now());
    final dir = Directory(p.join(base, stamp));
    await dir.create(recursive: true);
    AppLogger.info('backup session @ ${dir.path}', tag: 'RegistryBackup');
    return RegistryBackupService._(dir.path);
  }

  /// 导出 [fullKeyPath]（形如 `HKLM\SOFTWARE\Adobe`）到一个 .reg 文件。
  /// 成功返回备份文件绝对路径，失败返回 null。
  Future<String?> exportKey(String fullKeyPath) async {
    if (!Platform.isWindows) return null;
    final outFile = p.join(sessionDir, _sanitize(fullKeyPath) + '.reg');
    try {
      final result = await Process.run(
        'reg.exe',
        ['export', fullKeyPath, outFile, '/y'],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        AppLogger.warn(
          'reg export "$fullKeyPath" failed (exit=${result.exitCode}, '
          'stderr=${result.stderr})',
          tag: 'RegistryBackup',
        );
        return null;
      }
      if (!await File(outFile).exists()) return null;
      return outFile;
    } on ProcessException catch (e) {
      AppLogger.warn(
        'reg.exe not available: ${e.message}',
        tag: 'RegistryBackup',
      );
      return null;
    }
  }

  static String _sanitize(String path) {
    final buf = StringBuffer();
    for (final r in path.runes) {
      // Windows 不允许 \ / : * ? " < > |
      const banned = [0x5C, 0x2F, 0x3A, 0x2A, 0x3F, 0x22, 0x3C, 0x3E, 0x7C];
      buf.writeCharCode(banned.contains(r) ? 0x5F /* _ */ : r);
    }
    final out = buf.toString();
    return out.length > 200 ? out.substring(0, 200) : out;
  }

  static String _timestamp(DateTime d) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}
