import 'dart:io';

import '../../core/utils/logger.dart';
import '../../core/utils/safety_guard.dart';
import '../../domain/entities/junk_item.dart';

/// 通用的文件/目录删除工具，所有非虚拟项的清理走这里。
class CleanerService {
  /// 删除一批普通的物理文件/目录。
  ///
  /// - 自动经过 [SafetyGuard]；
  /// - 单项失败不会中断整体；
  /// - 返回汇总报告。
  static Future<CleanReport> deleteItems(List<JunkItem> items) async {
    var freed = 0;
    var deleted = 0;
    final failures = <CleanFailure>[];

    for (final item in items) {
      if (item.isVirtual) continue;
      if (!SafetyGuard.isSafeToDelete(item.path)) {
        failures.add(CleanFailure(item.path, '受保护路径，已跳过'));
        continue;
      }
      try {
        if (item.isDirectory) {
          final dir = Directory(item.path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            freed += item.size;
            deleted += 1;
          }
        } else {
          final file = File(item.path);
          if (await file.exists()) {
            await file.delete();
            freed += item.size;
            deleted += 1;
          }
        }
      } on FileSystemException catch (e) {
        AppLogger.warn(
          'delete failed: ${item.path} (${e.osError?.message})',
          tag: 'Cleaner',
        );
        failures.add(CleanFailure(item.path, e.osError?.message ?? e.message));
      }
    }

    return CleanReport(
      bytesFreed: freed,
      itemsDeleted: deleted,
      failures: failures,
    );
  }
}
