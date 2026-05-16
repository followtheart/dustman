import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/installed_program.dart';
import '../../domain/entities/residue_item.dart';
import '../../domain/scanners/residue_scanner.dart';
import '../platform/registry_reader.dart';

/// 扫描 `HKLM\SOFTWARE\*` 与 `HKCU\SOFTWARE\*` 下的 Publisher 键，
/// 寻找未匹配到任何已安装程序的孤儿条目。
class RegistryResidueScanner implements ResidueScanner {
  RegistryResidueScanner();

  @override
  ResidueKind get kind => ResidueKind.registryKey;

  @override
  Stream<ResidueItem> scan(InstalledProgramIndex index) async* {
    if (!Platform.isWindows) return;
    final sources = <(RegRoot, RegView)>[
      (RegRoot.hklm, RegView.v64),
      (RegRoot.hklm, RegView.v32),
      (RegRoot.hkcu, RegView.v64),
    ];
    for (final src in sources) {
      yield* _scanRoot(src.$1, src.$2, index);
    }
  }

  Stream<ResidueItem> _scanRoot(
    RegRoot root,
    RegView view,
    InstalledProgramIndex index,
  ) async* {
    final software = RegKey.open(root, 'SOFTWARE', view: view);
    if (software == null) {
      AppLogger.debug(
        'cannot open SOFTWARE for $root($view)',
        tag: 'RegistryResidue',
      );
      return;
    }
    try {
      final children = software.enumSubKeys();
      for (final child in children) {
        final nameLower = child.name.toLowerCase();
        if (AppConstants.registryPublisherBlacklist.contains(nameLower)) {
          continue;
        }
        if (index.matchesPublisherKey(child.name)) continue;

        // 控量：子键 ≤ 16、值 ≤ 64
        if (child.subKeyCount > 16 || child.valueCount > 64) continue;

        // 32-bit 视图下，HKLM\SOFTWARE\X 物理位置在 HKLM\SOFTWARE\Wow6432Node\X
        final actualPath = (view == RegView.v32 && root == RegRoot.hklm)
            ? 'HKLM\\SOFTWARE\\Wow6432Node\\${child.name}'
            : '${software.fullPath}\\${child.name}';

        final residue = _buildResidue(
          name: child.name,
          actualPath: actualPath,
          info: child,
          view: view,
        );
        yield residue;
      }
    } finally {
      software.close();
    }
  }

  ResidueItem _buildResidue({
    required String name,
    required String actualPath,
    required RegSubKeyInfo info,
    required RegView view,
  }) {
    final evidence = <String>[];
    evidence.add('未匹配到任何已安装程序的 Publisher / DisplayName');
    evidence.add('子键 ${info.subKeyCount} 个，值 ${info.valueCount} 个');
    evidence.add('LastWriteTime: ${_fmtDate(info.lastWriteTime)}');
    if (view == RegView.v32) evidence.add('视图：32-bit (Wow6432Node)');

    final daysAgo = DateTime.now().difference(info.lastWriteTime).inDays;

    ResidueConfidence conf;
    String reason;
    if (daysAgo > 365) {
      conf = ResidueConfidence.high;
      reason = '上次写入 ${daysAgo} 天前 (> 1 年)';
    } else if (daysAgo > 180 || info.subKeyCount > 8) {
      conf = ResidueConfidence.medium;
      reason = '上次写入 ${daysAgo} 天前';
    } else {
      conf = ResidueConfidence.low;
      reason = '近期仍有写入，可能仍在使用';
    }

    // 估算字节：粗略以"键名 30 字符 + 每值 64 字节"算
    final estBytes = name.length * 2 +
        info.subKeyCount * 64 +
        info.valueCount * 64;

    return ResidueItem(
      id: actualPath,
      name: name,
      path: actualPath,
      size: estBytes,
      kind: ResidueKind.registryKey,
      confidence: conf,
      reason: reason,
      evidence: evidence,
      lastModified: info.lastWriteTime,
      extra: {'view': view.name},
    );
  }

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }
}
