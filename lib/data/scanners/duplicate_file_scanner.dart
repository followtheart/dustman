import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/duplicate_group.dart';

/// 按 (size 预筛 + SHA1 内容哈希) 检测重复文件。
///
/// 流程：
/// 1. 遍历根目录，按文件大小分桶；
/// 2. 同尺寸桶里 ≥ 2 个文件时再做 hash；
/// 3. 同 hash 的算作一组重复。
///
/// 控量：忽略 < [minBytes] 的小文件（默认 1MB），避免几千个 0 字节占位文件干扰。
class DuplicateFileScanner {
  const DuplicateFileScanner({
    this.minBytes = 1024 * 1024,
    this.maxFiles = 100000,
  });

  final int minBytes;
  final int maxFiles;

  /// 扫描多个根目录，产出 [DuplicateGroup]。
  ///
  /// 中间状态通过 [onProgress] 回调上报，避免污染主 stream。
  Stream<DuplicateGroup> scan(
    List<String> roots, {
    void Function(DuplicateScanProgress)? onProgress,
  }) async* {
    final sizeBuckets = <int, List<String>>{};
    var filesIndexed = 0;
    var groupsFound = 0;

    // 阶段 1：枚举 + size 分桶
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false).handleError(
          (Object e, StackTrace _) {
            AppLogger.debug('list err in $root: $e', tag: 'DupScanner');
          },
          test: (e) => e is FileSystemException,
        )) {
          if (entity is! File) continue;
          filesIndexed++;
          if (filesIndexed > maxFiles) {
            AppLogger.warn(
              'truncated indexing at $maxFiles files',
              tag: 'DupScanner',
            );
            break;
          }
          int size;
          try {
            size = (await entity.stat()).size;
          } on FileSystemException {
            continue;
          }
          if (size < minBytes) continue;
          (sizeBuckets[size] ??= <String>[]).add(entity.path);
          if (filesIndexed % 200 == 0) {
            final candidates = sizeBuckets.values
                .where((l) => l.length > 1)
                .fold<int>(0, (s, l) => s + l.length);
            onProgress?.call(DuplicateScanProgress(
              filesIndexed: filesIndexed,
              candidatePairs: candidates,
              groupsFound: groupsFound,
              bytesHashed: 0,
            ));
          }
        }
      } on FileSystemException catch (e) {
        AppLogger.warn('walk $root: ${e.osError?.message}',
            tag: 'DupScanner');
      }
    }

    // 阶段 2：候选桶内 hash
    final candidatePaths = <String>[];
    for (final list in sizeBuckets.values) {
      if (list.length > 1) candidatePaths.addAll(list);
    }
    onProgress?.call(DuplicateScanProgress(
      filesIndexed: filesIndexed,
      candidatePairs: candidatePaths.length,
      groupsFound: groupsFound,
      bytesHashed: 0,
    ));

    var bytesHashed = 0;
    for (final entry in sizeBuckets.entries) {
      final size = entry.key;
      final paths = entry.value;
      if (paths.length < 2) continue;

      final hashed = <String, List<String>>{};
      for (final path in paths) {
        final h = await _sha1OfFile(File(path));
        if (h == null) continue;
        (hashed[h] ??= <String>[]).add(path);
        bytesHashed += size;
        onProgress?.call(DuplicateScanProgress(
          filesIndexed: filesIndexed,
          candidatePairs: candidatePaths.length,
          groupsFound: groupsFound,
          bytesHashed: bytesHashed,
        ));
      }
      for (final ent in hashed.entries) {
        if (ent.value.length < 2) continue;
        groupsFound++;
        yield DuplicateGroup(
          hash: ent.key,
          size: size,
          paths: ent.value,
        );
      }
    }

    onProgress?.call(DuplicateScanProgress(
      filesIndexed: filesIndexed,
      candidatePairs: candidatePaths.length,
      groupsFound: groupsFound,
      bytesHashed: bytesHashed,
    ));
  }

  Future<String?> _sha1OfFile(File f) async {
    try {
      final digest = await sha1.bind(f.openRead()).first;
      return digest.toString();
    } on FileSystemException catch (e) {
      AppLogger.debug(
        'hash failed ${f.path}: ${e.osError?.message}',
        tag: 'DupScanner',
      );
      return null;
    } on Object catch (e) {
      AppLogger.debug('hash failed ${f.path}: $e', tag: 'DupScanner');
      return null;
    }
  }
}
