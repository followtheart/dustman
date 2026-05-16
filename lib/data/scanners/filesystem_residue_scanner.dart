import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/installed_program.dart';
import '../../domain/entities/residue_item.dart';
import '../../domain/scanners/residue_scanner.dart';
import '../platform/windows_paths.dart';

/// 扫描 Program Files / AppData / ProgramData 的**一级子目录**，
/// 寻找未匹配到任何已安装程序的孤儿目录。
///
/// 只扫一级是控量手段：避免把单个程序的几千个子文件全部列成残留。
class FilesystemResidueScanner implements ResidueScanner {
  FilesystemResidueScanner({List<String>? roots}) : _roots = roots ?? _defaultRoots();

  final List<String> _roots;

  @override
  ResidueKind get kind => ResidueKind.fileDir;

  static List<String> _defaultRoots() {
    if (!Platform.isWindows) return const [];
    final programFiles = Platform.environment['ProgramFiles'] ??
        r'C:\Program Files';
    final programFiles86 = Platform.environment['ProgramFiles(x86)'] ??
        r'C:\Program Files (x86)';
    return [
      programFiles,
      programFiles86,
      WindowsPaths.appData,
      WindowsPaths.localAppData,
      WindowsPaths.programData,
    ].where((s) => s.isNotEmpty).toList();
  }

  @override
  Stream<ResidueItem> scan(InstalledProgramIndex index) async* {
    for (final root in _roots) {
      yield* _scanRoot(root, index);
    }
  }

  Stream<ResidueItem> _scanRoot(
    String rootPath,
    InstalledProgramIndex index,
  ) async* {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    List<FileSystemEntity> children;
    try {
      children = await root.list(followLinks: false).toList();
    } on FileSystemException catch (e) {
      AppLogger.warn(
        'list failed at $rootPath: ${e.osError?.message}',
        tag: 'ResidueScanner',
      );
      return;
    }

    for (final entity in children) {
      if (entity is! Directory) continue;
      final base = p.basename(entity.path);
      final baseLower = base.toLowerCase();

      // 1. 白名单过滤
      if (AppConstants.residueDirWhitelist.contains(baseLower)) continue;
      if (baseLower.startsWith('.') || baseLower.startsWith(r'$')) continue;

      // 2. 匹配已安装程序
      if (index.matchesPath(entity.path)) continue;

      // 3. 候选：统计大小 + 信心评级
      try {
        final summary = await _summarize(entity);
        final residue = _buildResidue(entity.path, base, summary);
        if (residue != null) yield residue;
      } on FileSystemException catch (e) {
        AppLogger.debug(
          'stat failed: ${entity.path} (${e.osError?.message})',
          tag: 'ResidueScanner',
        );
      }
    }
  }

  Future<_DirSummary> _summarize(Directory dir) async {
    var total = 0;
    var fileCount = 0;
    var dirCount = 0;
    var hasExe = false;
    var hasDll = false;
    var hasData = false;
    DateTime? latest;

    // 控量：最多统计 5000 个条目；超过后停止累计大小但记录 truncated
    var visited = 0;
    var truncated = false;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        visited++;
        if (visited > 5000) {
          truncated = true;
          break;
        }
        if (entity is File) {
          fileCount++;
          try {
            final stat = await entity.stat();
            total += stat.size;
            final mtime = stat.modified;
            if (latest == null || mtime.isAfter(latest)) latest = mtime;
          } on FileSystemException {
            // 跳过
          }
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.exe')) hasExe = true;
          if (lower.endsWith('.dll')) hasDll = true;
          if (lower.endsWith('.dat') ||
              lower.endsWith('.ini') ||
              lower.endsWith('.json') ||
              lower.endsWith('.xml') ||
              lower.endsWith('.log')) {
            hasData = true;
          }
        } else if (entity is Directory) {
          dirCount++;
        }
      }
    } on FileSystemException catch (e) {
      AppLogger.debug(
        'sub-list failed in ${dir.path}: ${e.osError?.message}',
        tag: 'ResidueScanner',
      );
    }

    return _DirSummary(
      total: total,
      fileCount: fileCount,
      dirCount: dirCount,
      hasExe: hasExe,
      hasDll: hasDll,
      hasData: hasData,
      lastModified: latest,
      truncated: truncated,
    );
  }

  ResidueItem? _buildResidue(
    String path,
    String name,
    _DirSummary s,
  ) {
    final evidence = <String>[];
    evidence.add('未匹配到任何已安装程序的 InstallLocation 或 DisplayName');
    if (s.fileCount == 0 && s.dirCount == 0) {
      evidence.add('空目录');
    } else {
      evidence.add('文件 ${s.fileCount} · 子目录 ${s.dirCount} · '
          '${_humanSize(s.total)}');
      if (s.hasExe) evidence.add('含可执行文件');
      if (s.hasDll) evidence.add('含 .dll');
      if (s.hasData) evidence.add('含配置 / 数据文件');
      if (s.lastModified != null) {
        evidence.add('最近修改：${_fmtDate(s.lastModified!)}');
      }
      if (s.truncated) evidence.add('超过 5000 项已截断统计');
    }

    final isEmpty = s.fileCount == 0 && s.dirCount == 0;
    final small = s.total < 256 * 1024 && !s.hasExe && !s.hasDll;
    final daysAgo = s.lastModified == null
        ? null
        : DateTime.now().difference(s.lastModified!).inDays;

    ResidueConfidence conf;
    String reason;
    if (isEmpty) {
      conf = ResidueConfidence.high;
      reason = '空目录，可安全删除';
    } else if (small) {
      conf = ResidueConfidence.high;
      reason = '体积 < 256KB 且无可执行文件';
    } else if (s.total < 50 * 1024 * 1024 &&
        !s.hasExe &&
        daysAgo != null &&
        daysAgo > 90) {
      conf = ResidueConfidence.medium;
      reason = '体积小且 ${daysAgo} 天未修改';
    } else if (s.hasExe || s.total >= 50 * 1024 * 1024) {
      conf = ResidueConfidence.low;
      reason = '体积较大或含可执行文件，需人工确认';
    } else {
      conf = ResidueConfidence.low;
      reason = '证据不足，仅作展示';
    }

    return ResidueItem(
      id: path,
      name: name,
      path: path,
      size: s.total,
      kind: ResidueKind.fileDir,
      confidence: conf,
      reason: reason,
      evidence: evidence,
      lastModified: s.lastModified,
    );
  }

  static String _humanSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _DirSummary {
  _DirSummary({
    required this.total,
    required this.fileCount,
    required this.dirCount,
    required this.hasExe,
    required this.hasDll,
    required this.hasData,
    required this.lastModified,
    required this.truncated,
  });

  final int total;
  final int fileCount;
  final int dirCount;
  final bool hasExe;
  final bool hasDll;
  final bool hasData;
  final DateTime? lastModified;
  final bool truncated;
}
