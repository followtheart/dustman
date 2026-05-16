import 'dart:io';

import '../../core/utils/logger.dart';
import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';

class DnsCacheScanner implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.dnsCache;

  @override
  bool get requiresElevation => false;

  @override
  Stream<JunkItem> scan() async* {
    // DNS 缓存大小无法直接查询，统一以一个虚拟项呈现，"大小"为 0。
    yield JunkItem(
      path: 'dns:cache',
      size: 0,
      category: type,
      isVirtual: true,
      note: '执行 ipconfig /flushdns',
    );
  }

  @override
  Future<CleanReport> clean(List<JunkItem> items) async {
    if (items.isEmpty || !Platform.isWindows) return CleanReport.empty();
    try {
      final result =
          await Process.run('ipconfig', ['/flushdns'], runInShell: true);
      if (result.exitCode != 0) {
        AppLogger.warn('flushdns exit=${result.exitCode}', tag: 'DNS');
        return CleanReport(
          bytesFreed: 0,
          itemsDeleted: 0,
          failures: [CleanFailure('dns:cache', 'exit=${result.exitCode}')],
        );
      }
      return CleanReport(
        bytesFreed: 0,
        itemsDeleted: 1,
        failures: const [],
      );
    } on ProcessException catch (e) {
      return CleanReport(
        bytesFreed: 0,
        itemsDeleted: 0,
        failures: [CleanFailure('dns:cache', e.message)],
      );
    }
  }
}
