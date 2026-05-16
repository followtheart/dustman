import 'junk_category.dart';

/// 单个可清理项。可能是文件、目录，或虚拟项（例如"回收站"整体）。
class JunkItem {
  JunkItem({
    required this.path,
    required this.size,
    required this.category,
    this.isDirectory = false,
    this.isVirtual = false,
    this.note,
  });

  final String path;
  final int size;
  final JunkCategoryType category;
  final bool isDirectory;

  /// 虚拟项：不对应真实路径，由 Scanner 自行处理（如清空回收站、DNS 缓存）。
  final bool isVirtual;

  final String? note;
}

class CleanReport {
  CleanReport({
    required this.bytesFreed,
    required this.itemsDeleted,
    required this.failures,
  });

  final int bytesFreed;
  final int itemsDeleted;
  final List<CleanFailure> failures;

  factory CleanReport.empty() =>
      CleanReport(bytesFreed: 0, itemsDeleted: 0, failures: const []);

  CleanReport merge(CleanReport other) => CleanReport(
        bytesFreed: bytesFreed + other.bytesFreed,
        itemsDeleted: itemsDeleted + other.itemsDeleted,
        failures: [...failures, ...other.failures],
      );
}

class CleanFailure {
  CleanFailure(this.path, this.reason);
  final String path;
  final String reason;
}
