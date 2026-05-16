import '../entities/installed_program.dart';
import '../entities/residue_item.dart';

/// 残留扫描器抽象。三类（文件系统 / 注册表 / 失效快捷方式）各自实现。
///
/// 故意**不复用** `JunkScanner`，因为：
/// - 输出实体不同（[ResidueItem] 含信心、证据）；
/// - 清理流程不同（文件 → 回收站；注册表 → 备份 + 删除）；
/// - 选择粒度不同：垃圾清理勾分类，残留清理勾单项。
abstract class ResidueScanner {
  ResidueKind get kind;

  /// 流式扫描。内部应捕获单项错误并跳过 + warn，不向上抛。
  Stream<ResidueItem> scan(InstalledProgramIndex index);
}
