import '../../domain/entities/junk_item.dart';

enum ResidueKind { fileDir, registryKey, deadShortcut }

enum ResidueConfidence { high, medium, low }

extension ResidueKindUi on ResidueKind {
  String get displayName => switch (this) {
        ResidueKind.fileDir => '文件系统',
        ResidueKind.registryKey => '注册表',
        ResidueKind.deadShortcut => '失效快捷方式',
      };
}

extension ResidueConfidenceUi on ResidueConfidence {
  String get displayName => switch (this) {
        ResidueConfidence.high => '高',
        ResidueConfidence.medium => '中',
        ResidueConfidence.low => '低',
      };
}

class ResidueItem {
  ResidueItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.kind,
    required this.confidence,
    required this.reason,
    this.evidence = const [],
    this.lastModified,
    this.extra,
  });

  /// 稳定 ID（用于 UI 勾选状态）。一般取 path 本身。
  final String id;

  /// 展示名（basename / Publisher 键名 / .lnk 文件名等）。
  final String name;

  /// 文件路径 / 注册表完整路径 / .lnk 路径。
  final String path;

  /// 字节，注册表项按估算字节计（值与子键数 × 平均长度）。
  final int size;

  final ResidueKind kind;
  final ResidueConfidence confidence;

  /// 一句话总结。
  final String reason;

  /// 详细证据，展开面板列出。
  final List<String> evidence;

  final DateTime? lastModified;

  /// 额外元数据（如 .lnk 的目标路径）。
  final Map<String, Object?>? extra;
}

/// 残留清理的汇总报告。比 [CleanReport] 多出"注册表备份目录"信息。
class ResidueCleanReport extends CleanReport {
  ResidueCleanReport({
    required super.bytesFreed,
    required super.itemsDeleted,
    required super.failures,
    this.registryBackupDir,
  });

  /// 本次操作的 .reg 备份目录。若无注册表项则为 null。
  final String? registryBackupDir;

  factory ResidueCleanReport.empty() => ResidueCleanReport(
        bytesFreed: 0,
        itemsDeleted: 0,
        failures: const [],
      );

  ResidueCleanReport mergeResidue(ResidueCleanReport other) =>
      ResidueCleanReport(
        bytesFreed: bytesFreed + other.bytesFreed,
        itemsDeleted: itemsDeleted + other.itemsDeleted,
        failures: [...failures, ...other.failures],
        registryBackupDir: other.registryBackupDir ?? registryBackupDir,
      );
}
