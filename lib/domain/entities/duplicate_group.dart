/// 重复文件组：同一份内容（size + hash 一致）对应的所有副本。
class DuplicateGroup {
  DuplicateGroup({
    required this.hash,
    required this.size,
    required this.paths,
  });

  /// 内容哈希（SHA1 hex，小写）。
  final String hash;

  /// 单个文件的字节数（组内一致）。
  final int size;

  /// 已排序的副本路径列表（先扫描到的排在前）。
  final List<String> paths;

  /// 组内副本数。
  int get count => paths.length;

  /// 这一组占用的总字节数。
  int get totalBytes => size * paths.length;

  /// 删除多余副本（保留 1 个）可释放的字节数。
  int get reclaimableBytes => size * (paths.length - 1).clamp(0, paths.length);
}

/// 扫描进度：用于 UI 状态卡片。
class DuplicateScanProgress {
  DuplicateScanProgress({
    required this.filesIndexed,
    required this.candidatePairs,
    required this.groupsFound,
    required this.bytesHashed,
  });

  /// 已枚举（无论是否被丢弃）的文件数。
  final int filesIndexed;

  /// 经过 size 预筛后，还需 hash 比对的候选文件数。
  final int candidatePairs;

  /// 已找到的重复组数量。
  final int groupsFound;

  /// 已读取并参与 hash 的字节数。
  final int bytesHashed;
}
