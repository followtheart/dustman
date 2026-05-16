import 'dart:io';

import '../../core/utils/logger.dart';
import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';

/// 复用：递归扫描一个或多个目录，把所有文件转成 [JunkItem]。
/// 单文件 stat 出错时跳过 + 记 warn，不向上抛。
mixin DirectoryScannerMixin {
  Stream<JunkItem> scanDirectories(
    Iterable<String> roots,
    JunkCategoryType category, {
    bool Function(FileSystemEntity)? filter,
  }) async* {
    for (final root in roots) {
      if (root.isEmpty) continue;
      final dir = Directory(root);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          if (filter != null && !filter(entity)) continue;
          try {
            final stat = await entity.stat();
            yield JunkItem(
              path: entity.path,
              size: stat.size,
              category: category,
            );
          } on FileSystemException catch (e) {
            AppLogger.debug(
              'stat skipped: ${entity.path} (${e.osError?.message})',
              tag: 'Scanner',
            );
          }
        }
      } on FileSystemException catch (e) {
        AppLogger.warn(
          'list failed at $root: ${e.osError?.message}',
          tag: 'Scanner',
        );
      }
    }
  }
}
