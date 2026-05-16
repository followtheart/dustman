import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';
import '../services/recycle_bin_service.dart';

class RecycleBinScanner implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.recycleBin;

  @override
  bool get requiresElevation => false;

  @override
  Stream<JunkItem> scan() async* {
    final size = RecycleBinService.querySize();
    final count = RecycleBinService.queryItemCount();
    if (size <= 0 || count <= 0) return;
    yield JunkItem(
      path: 'shell:RecycleBinFolder',
      size: size,
      category: type,
      isVirtual: true,
      note: '$count 个项目',
    );
  }

  @override
  Future<CleanReport> clean(List<JunkItem> items) async {
    if (items.isEmpty) return CleanReport.empty();
    final freed = items.fold<int>(0, (s, it) => s + it.size);
    final ok = RecycleBinService.empty();
    if (!ok) {
      return CleanReport(
        bytesFreed: 0,
        itemsDeleted: 0,
        failures: [CleanFailure('shell:RecycleBinFolder', '清空回收站调用失败')],
      );
    }
    return CleanReport(
      bytesFreed: freed,
      itemsDeleted: items.length,
      failures: const [],
    );
  }
}
