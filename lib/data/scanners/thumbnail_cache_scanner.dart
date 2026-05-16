import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';
import '../platform/windows_paths.dart';
import '../services/cleaner_service.dart';
import '_directory_scanner_mixin.dart';

class ThumbnailCacheScanner with DirectoryScannerMixin implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.thumbnailCache;

  @override
  Stream<JunkItem> scan() => scanDirectories(
        [WindowsPaths.thumbnailCacheDir],
        type,
        filter: (e) {
          final name = e.uri.pathSegments.last.toLowerCase();
          return name.startsWith('thumbcache_') ||
              name.startsWith('iconcache_');
        },
      );

  @override
  Future<CleanReport> clean(List<JunkItem> items) =>
      CleanerService.deleteItems(items);
}
