/// 磁盘 TreeMap 节点。children == null 表示叶子（文件或已截断目录）。
class DiskNode {
  DiskNode({
    required this.path,
    required this.name,
    required this.size,
    required this.isDirectory,
    this.children,
  });

  final String path;
  final String name;

  /// 字节数；对目录而言是递归合计。
  final int size;
  final bool isDirectory;

  /// 子节点（按 size 降序）。null 表示叶子或未展开。
  final List<DiskNode>? children;

  bool get isLeaf => children == null || children!.isEmpty;
}
