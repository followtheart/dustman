import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../domain/entities/installed_program.dart';
import 'registry_reader.dart';

/// 枚举系统中已安装程序的 Uninstall 列表，构建 [InstalledProgramIndex]。
///
/// 三处来源：
///  - HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall (64-bit view)
///  - HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall (32-bit view)
///  - HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall (default)
class InstalledProgramsRepository {
  InstalledProgramsRepository();

  static const _uninstallSubKey =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

  /// 非 Windows 平台返回空索引。
  Future<InstalledProgramIndex> build() async {
    if (!Platform.isWindows) {
      AppLogger.info('non-Windows: empty index', tag: 'InstalledPrograms');
      return InstalledProgramIndex(const []);
    }
    final all = <InstalledProgram>[];
    _readFrom(RegRoot.hklm, RegView.v64, all);
    _readFrom(RegRoot.hklm, RegView.v32, all);
    _readFrom(RegRoot.hkcu, RegView.v64, all);

    // 简单去重：按 (displayName, installLocation) 唯一。
    final seen = <String>{};
    final dedup = <InstalledProgram>[];
    for (final pgm in all) {
      final key = '${pgm.displayName.toLowerCase()}|'
          '${pgm.installLocation ?? ''}';
      if (seen.add(key)) dedup.add(pgm);
    }
    AppLogger.info(
      'enumerated ${dedup.length} installed programs',
      tag: 'InstalledPrograms',
    );
    return InstalledProgramIndex(dedup);
  }

  void _readFrom(RegRoot root, RegView view, List<InstalledProgram> out) {
    final root0 = RegKey.open(root, _uninstallSubKey, view: view);
    if (root0 == null) return;
    try {
      final names = root0.enumSubKeyNames();
      for (final name in names) {
        final sub = root0.openSubKey(name);
        if (sub == null) continue;
        try {
          // SystemComponent=1 / ParentKeyName 非空 → 跳过
          final sysComp = sub.readDword('SystemComponent') ?? 0;
          final parentKey = sub.readString('ParentKeyName');
          if (sysComp != 0) continue;
          if (parentKey != null && parentKey.isNotEmpty) continue;

          final displayName = sub.readString('DisplayName');
          if (displayName == null || displayName.isEmpty) continue;

          final publisher = sub.readString('Publisher');
          final installLoc = sub.readString('InstallLocation');

          out.add(InstalledProgram(
            displayName: displayName,
            publisher: publisher,
            installLocation: _normalizeLocation(installLoc),
            registryKeyPath: sub.fullPath,
            systemComponent: sysComp != 0,
          ));
        } finally {
          sub.close();
        }
      }
    } finally {
      root0.close();
    }
  }

  static String? _normalizeLocation(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    // 剥离首尾引号
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    // 规范化路径
    try {
      s = p.normalize(s);
    } on FormatException {
      return null;
    }
    s = s.replaceAll('/', '\\').toLowerCase();
    // 去掉尾部分隔符
    while (s.endsWith('\\')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;
    return s;
  }
}
