import '../entities/junk_category.dart';
import '../entities/junk_item.dart';

abstract class JunkScanner {
  JunkCategoryType get type;
  bool get requiresElevation => false;

  /// 流式扫描。Scanner 内部应捕获单文件异常并跳过，不向上抛。
  Stream<JunkItem> scan();

  /// 删除给定的项。返回汇总报告。
  Future<CleanReport> clean(List<JunkItem> items);
}
