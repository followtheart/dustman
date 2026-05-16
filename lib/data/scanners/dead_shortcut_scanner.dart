import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../domain/entities/installed_program.dart';
import '../../domain/entities/residue_item.dart';
import '../../domain/scanners/residue_scanner.dart';
import '../platform/shortcut_resolver.dart';
import '../platform/windows_paths.dart';

/// 扫描 Start Menu 下的所有 .lnk，过滤出目标不存在的"死快捷方式"。
class DeadShortcutScanner implements ResidueScanner {
  DeadShortcutScanner({List<String>? roots}) : _roots = roots ?? _defaultRoots();

  final List<String> _roots;

  @override
  ResidueKind get kind => ResidueKind.deadShortcut;

  static List<String> _defaultRoots() {
    if (!Platform.isWindows) return const [];
    final results = <String>[];
    final appData = WindowsPaths.appData;
    final programData = WindowsPaths.programData;
    if (appData.isNotEmpty) {
      results
          .add(p.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
    }
    if (programData.isNotEmpty) {
      results.add(
          p.join(programData, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
    }
    return results;
  }

  @override
  Stream<ResidueItem> scan(InstalledProgramIndex index) async* {
    if (!Platform.isWindows) return;
    final lnks = <String>[];
    for (final root in _roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && e.path.toLowerCase().endsWith('.lnk')) {
            lnks.add(e.path);
          }
        }
      } on FileSystemException catch (err) {
        AppLogger.warn(
          'list shortcut root $root failed: ${err.osError?.message}',
          tag: 'DeadShortcut',
        );
      }
    }

    if (lnks.isEmpty) return;

    yield* _resolveBatch(lnks);
  }

  Stream<ResidueItem> _resolveBatch(List<String> lnks) async* {
    // 分批 20 个并发解析
    const batchSize = 20;
    final results = <ResidueItem>[];
    await ShortcutResolver.runCoInitialized(() async {
      for (var i = 0; i < lnks.length; i += batchSize) {
        final batch = lnks.sublist(
          i,
          (i + batchSize).clamp(0, lnks.length),
        );
        final futures = batch.map(_inspectOne);
        final batchResults = await Future.wait(futures);
        for (final r in batchResults) {
          if (r != null) results.add(r);
        }
      }
    });
    for (final r in results) {
      yield r;
    }
  }

  Future<ResidueItem?> _inspectOne(String lnk) async {
    try {
      final info = ShortcutResolver.resolve(lnk);
      if (info == null) return null;
      final target = info.target.trim();
      if (target.isEmpty) return null;
      if (target.startsWith(r'\\')) return null; // UNC：跳过
      // 仅当目标是绝对路径且本地盘
      if (!_isAbsoluteLocal(target)) return null;
      final exists = await File(target).exists() ||
          await Directory(target).exists();
      if (exists) return null;

      // stat 失败也算死
      int size = 0;
      DateTime? mtime;
      try {
        final stat = await FileStat.stat(lnk);
        size = stat.size;
        mtime = stat.modified;
      } on FileSystemException {
        // ignore
      }

      return ResidueItem(
        id: lnk,
        name: p.basenameWithoutExtension(lnk),
        path: lnk,
        size: size,
        kind: ResidueKind.deadShortcut,
        confidence: ResidueConfidence.high,
        reason: '目标不存在：$target',
        evidence: [
          '快捷方式：$lnk',
          '目标路径：$target',
          if (info.workingDirectory.isNotEmpty)
            '工作目录：${info.workingDirectory}',
          if (info.arguments.isNotEmpty) '启动参数：${info.arguments}',
        ],
        lastModified: mtime,
        extra: {'target': target},
      );
    } catch (e, st) {
      AppLogger.debug('inspect $lnk failed: $e\n$st', tag: 'DeadShortcut');
      return null;
    }
  }

  static bool _isAbsoluteLocal(String path) {
    if (path.length < 3) return false;
    final c = path.codeUnitAt(0);
    final isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    return isLetter && path[1] == ':' && (path[2] == '\\' || path[2] == '/');
  }
}
