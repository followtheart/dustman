/// 大文件查找结果。
class LargeFileItem {
  LargeFileItem({
    required this.path,
    required this.size,
    required this.lastModified,
    required this.extension,
  });

  /// 文件绝对路径，同时作为 UI 选中态的稳定 ID。
  final String path;
  final int size;
  final DateTime lastModified;

  /// 后缀（含点，例如 `.iso`）。无后缀时为空字符串。
  final String extension;
}
