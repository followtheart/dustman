import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../domain/entities/disk_node.dart';

/// 进度报告。
class DiskScanProgress {
  DiskScanProgress({
    required this.currentPath,
    required this.entriesScanned,
    required this.bytesAccumulated,
  });

  final String currentPath;
  final int entriesScanned;
  final int bytesAccumulated;
}

/// 递归统计目录占用，生成 [DiskNode] 树。
///
/// 设计取舍：
///  - 不展开符号链接 / Junction（避免循环、避免计错系统盘）；
///  - 每个目录最多保留 [maxChildrenPerDir] 个子节点（其余合并到 “其它”）；
///  - 控制最大深度 [maxDepth] 避免在 `C:\Windows\WinSxS` 之类的目录爆栈；
///  - 单文件读 [FileStat] 失败直接跳过。
class DiskTreemapScanner {
  DiskTreemapScanner({
    this.maxDepth = 6,
    this.maxChildrenPerDir = 200,
    this.minNodeBytes = 0,
    this.progressEveryNEntries = 500,
  });

  final int maxDepth;
  final int maxChildrenPerDir;

  /// 小于该大小的子节点会被合并到 “其它”，仅当所在目录子项过多时生效。
  final int minNodeBytes;

  final int progressEveryNEntries;

  bool _cancelled = false;

  /// 取消正在进行的扫描；调用者持有 scanner 即可。
  void cancel() => _cancelled = true;

  /// 入口：异步扫描 [rootPath]，返回根 [DiskNode]。`null` 表示路径不存在或被取消。
  Future<DiskNode?> scan(
    String rootPath, {
    void Function(DiskScanProgress)? onProgress,
  }) async {
    _cancelled = false;
    final root = Directory(rootPath);
    if (!await root.exists()) return null;

    final counter = _Counter();
    final node = await _scanDir(
      root,
      depth: 0,
      onProgress: onProgress,
      counter: counter,
    );
    if (_cancelled) return null;
    return node;
  }

  Future<DiskNode> _scanDir(
    Directory dir, {
    required int depth,
    required _Counter counter,
    void Function(DiskScanProgress)? onProgress,
  }) async {
    final name = _basenameOrDrive(dir.path);

    if (_cancelled) {
      return DiskNode(
        path: dir.path,
        name: name,
        size: 0,
        isDirectory: true,
        children: const [],
      );
    }

    var totalBytes = 0;
    final children = <DiskNode>[];

    // depth >= maxDepth：仍统计字节，但不展开 children。
    final expand = depth < maxDepth;

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(recursive: false, followLinks: false).toList();
    } on FileSystemException catch (e) {
      AppLogger.debug(
        'list failed at ${dir.path}: ${e.osError?.message}',
        tag: 'DiskTreemapScanner',
      );
      return DiskNode(
        path: dir.path,
        name: name,
        size: 0,
        isDirectory: true,
        children: expand ? const [] : null,
      );
    }

    for (final entity in entries) {
      if (_cancelled) break;
      counter.entries++;
      if (counter.entries % progressEveryNEntries == 0 && onProgress != null) {
        onProgress(DiskScanProgress(
          currentPath: dir.path,
          entriesScanned: counter.entries,
          bytesAccumulated: counter.bytes,
        ));
      }

      if (entity is File) {
        FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          continue;
        }
        final size = stat.size;
        if (size <= 0) continue;
        counter.bytes += size;
        totalBytes += size;
        if (expand) {
          children.add(DiskNode(
            path: entity.path,
            name: p.basename(entity.path),
            size: size,
            isDirectory: false,
          ));
        }
      } else if (entity is Directory) {
        // 跳过符号链接 / Junction：FileStat.type 仍然是 directory，但 link.path != real
        try {
          final stat = await entity.stat();
          // 简单启发：reparse / symlink 通过 FileSystemEntity.isLinkSync
          if (await FileSystemEntity.isLink(entity.path)) continue;
          // ignore stat to avoid lint
          stat.type;
        } on FileSystemException {
          continue;
        }
        final sub = await _scanDir(
          entity,
          depth: depth + 1,
          onProgress: onProgress,
          counter: counter,
        );
        totalBytes += sub.size;
        if (expand && sub.size > 0) {
          children.add(sub);
        }
      }
    }

    if (!expand) {
      return DiskNode(
        path: dir.path,
        name: name,
        size: totalBytes,
        isDirectory: true,
        children: null,
      );
    }

    // 排序、合并末尾的小项到 "其它"
    children.sort((a, b) => b.size.compareTo(a.size));
    final reduced = _reduceChildren(children, dir.path);
    return DiskNode(
      path: dir.path,
      name: name,
      size: totalBytes,
      isDirectory: true,
      children: reduced,
    );
  }

  List<DiskNode> _reduceChildren(List<DiskNode> children, String parentPath) {
    if (children.length <= maxChildrenPerDir) {
      if (minNodeBytes <= 0) return children;
      return _foldSmallTail(children, parentPath);
    }
    final keep = children.take(maxChildrenPerDir - 1).toList();
    final rest = children.skip(maxChildrenPerDir - 1).toList();
    final restBytes = rest.fold<int>(0, (s, n) => s + n.size);
    keep.add(DiskNode(
      path: p.join(parentPath, '(其它 ${rest.length} 项)'),
      name: '(其它 ${rest.length} 项)',
      size: restBytes,
      isDirectory: false,
    ));
    return keep;
  }

  List<DiskNode> _foldSmallTail(List<DiskNode> children, String parentPath) {
    final keep = <DiskNode>[];
    final small = <DiskNode>[];
    for (final c in children) {
      if (c.size < minNodeBytes) {
        small.add(c);
      } else {
        keep.add(c);
      }
    }
    if (small.isEmpty) return keep;
    final restBytes = small.fold<int>(0, (s, n) => s + n.size);
    keep.add(DiskNode(
      path: p.join(parentPath, '(其它 ${small.length} 项)'),
      name: '(其它 ${small.length} 项)',
      size: restBytes,
      isDirectory: false,
    ));
    return keep;
  }

  static String _basenameOrDrive(String path) {
    final base = p.basename(path);
    if (base.isNotEmpty) return base;
    // 比如 `D:\` 的 basename 为空
    return path;
  }
}

class _Counter {
  int entries = 0;
  int bytes = 0;
}
