import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';
import '../platform/windows_paths.dart';
import '../services/cleaner_service.dart';
import '_directory_scanner_mixin.dart';

class TempFilesScanner with DirectoryScannerMixin implements JunkScanner {
  @override
  JunkCategoryType get type => JunkCategoryType.tempFiles;

  @override
  bool get requiresElevation => true; // C:\Windows\Temp 需要管理员

  @override
  Stream<JunkItem> scan() => scanDirectories(
        [WindowsPaths.userTemp, WindowsPaths.windowsTemp],
        type,
      );

  @override
  Future<CleanReport> clean(List<JunkItem> items) =>
      CleanerService.deleteItems(items);
}
