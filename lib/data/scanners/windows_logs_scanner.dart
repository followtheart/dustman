import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';
import '../platform/windows_paths.dart';
import '../services/cleaner_service.dart';
import '_directory_scanner_mixin.dart';

class WindowsLogsScanner with DirectoryScannerMixin implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.windowsLogs;

  @override
  bool get requiresElevation => true;

  static const _exts = ['.log', '.dmp', '.etl', '.evtx', '.cab', '.old'];

  @override
  Stream<JunkItem> scan() => scanDirectories(
        WindowsPaths.windowsLogDirs,
        type,
        filter: (e) {
          final lower = e.path.toLowerCase();
          return _exts.any(lower.endsWith);
        },
      );

  @override
  Future<CleanReport> clean(List<JunkItem> items) =>
      CleanerService.deleteItems(items);
}
