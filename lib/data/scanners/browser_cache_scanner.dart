import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';
import '../platform/windows_paths.dart';
import '../services/cleaner_service.dart';
import '_directory_scanner_mixin.dart';

class BrowserCacheScanner with DirectoryScannerMixin implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.browserCache;

  @override
  bool get requiresElevation => false;

  @override
  Stream<JunkItem> scan() async* {
    final roots = <String>[];

    for (final path in WindowsPaths.browserCachePaths) {
      // Firefox 路径是 Profiles 根目录，需要展开每个 *.default-release 下的 cache2
      if (path.endsWith('Profiles')) {
        final dir = Directory(path);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final cache = p.join(entity.path, 'cache2');
          if (await Directory(cache).exists()) roots.add(cache);
        }
      } else {
        roots.add(path);
      }
    }

    yield* scanDirectories(roots, type);
  }

  @override
  Future<CleanReport> clean(List<JunkItem> items) =>
      CleanerService.deleteItems(items);
}
