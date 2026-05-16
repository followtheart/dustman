import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../domain/entities/large_file_item.dart';

/// 大文件查找器：递归扫描指定目录，仅产出大于阈值的文件。
///
/// 扫描器**只读**，不持有任何状态：每次调用 [scan] 都创建独立的 [Stream]。
class LargeFileScanner {
  const LargeFileScanner({
    this.minBytes = 100 * 1024 * 1024,
    this.extensions = const <String>{},
    this.maxFiles = 50000,
  });

  /// 文件最小尺寸阈值。低于此值不产出。
  final int minBytes;

  /// 允许的后缀集合（含点，小写）。空集合 = 不过滤。
  final Set<String> extensions;

  /// 控量：每个根目录最多遍历 [maxFiles] 个文件，避免在系统盘 root 上爆炸。
  final int maxFiles;

  /// 递归扫描 [rootPath]，产出大于 [minBytes] 的文件。
  Stream<LargeFileItem> scan(String rootPath) async* {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return;

    var visited = 0;
    final filterExt = extensions
        .map((e) => e.startsWith('.') ? e.toLowerCase() : '.${e.toLowerCase()}')
        .toSet();

    Stream<FileSystemEntity> entries;
    try {
      entries = dir.list(recursive: true, followLinks: false);
    } on FileSystemException catch (e) {
      AppLogger.warn(
        'list failed at $rootPath: ${e.osError?.message}',
        tag: 'LargeFileScanner',
      );
      return;
    }

    await for (final entity in entries.handleError(
      (Object error, StackTrace stack) {
        AppLogger.debug(
          'list error in $rootPath: $error',
          tag: 'LargeFileScanner',
        );
      },
      test: (e) => e is FileSystemException,
    )) {
      if (entity is! File) continue;
      visited++;
      if (visited > maxFiles) {
        AppLogger.warn(
          'truncated $rootPath at $maxFiles entries',
          tag: 'LargeFileScanner',
        );
        break;
      }

      // 后缀过滤（小写）
      final ext = p.extension(entity.path).toLowerCase();
      if (filterExt.isNotEmpty && !filterExt.contains(ext)) continue;

      FileStat stat;
      try {
        stat = await entity.stat();
      } on FileSystemException {
        continue;
      }
      if (stat.size < minBytes) continue;

      yield LargeFileItem(
        path: entity.path,
        size: stat.size,
        lastModified: stat.modified,
        extension: ext,
      );
    }
  }
}
