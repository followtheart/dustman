import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';
import '../../core/utils/safety_guard.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/entities/startup_item.dart';
import '../platform/registry_reader.dart';

/// 删除 / 禁用 [StartupItem]。
///
///  - 注册表项：直接 `RegDeleteValue` 删除值（无字节释放语义，bytesFreed=0）；
///  - 启动文件夹 .lnk：经 [SafetyGuard] → 移入回收站。
///
/// HKLM 项可能需要管理员权限；权限不足时计入 failures 而非抛异常。
class StartupCleanerService {
  StartupCleanerService._();

  static Future<CleanReport> remove(List<StartupItem> items) async {
    if (items.isEmpty) return CleanReport.empty();
    var deleted = 0;
    final failures = <CleanFailure>[];

    for (final item in items) {
      try {
        if (item.source.isRegistry) {
          final ok = _deleteRegistryValue(item);
          if (ok) {
            deleted++;
          } else {
            failures.add(CleanFailure(
              '${item.registryFullKeyPath}\\${item.registryValueName}',
              '删除失败（可能需要管理员权限）',
            ));
          }
        } else {
          final ok = await _deleteShortcut(item, failures);
          if (ok) deleted++;
        }
      } on Object catch (e, st) {
        AppLogger.error('startup remove threw', error: e, stack: st,
            tag: 'StartupCleaner');
        failures.add(CleanFailure(item.id, e.toString()));
      }
    }
    return CleanReport(
      bytesFreed: 0,
      itemsDeleted: deleted,
      failures: failures,
    );
  }

  static bool _deleteRegistryValue(StartupItem item) {
    if (!Platform.isWindows) return false;
    final full = item.registryFullKeyPath ?? '';
    final value = item.registryValueName ?? '';
    if (full.isEmpty || value.isEmpty) return false;

    final lower = full.toLowerCase();
    final RegRoot root;
    String sub;
    if (lower.startsWith('hklm\\')) {
      root = RegRoot.hklm;
      sub = full.substring(5);
    } else if (lower.startsWith('hkcu\\')) {
      root = RegRoot.hkcu;
      sub = full.substring(5);
    } else {
      AppLogger.warn('unknown reg root: $full', tag: 'StartupCleaner');
      return false;
    }
    final view = item.source == StartupSource.registryRunWow6432
        ? RegView.v32
        : RegView.v64;
    final key = RegKey.open(root, sub, view: view, writable: true);
    if (key == null) return false;
    try {
      return key.deleteValue(value);
    } finally {
      key.close();
    }
  }

  static Future<bool> _deleteShortcut(
    StartupItem item,
    List<CleanFailure> failures,
  ) async {
    final path = item.shortcutPath;
    if (path == null || path.isEmpty) {
      failures.add(CleanFailure(item.id, '快捷方式路径为空'));
      return false;
    }
    if (!SafetyGuard.isSafeToDelete(path)) {
      failures.add(CleanFailure(path, '受保护路径，已跳过'));
      return false;
    }
    if (Platform.isWindows) {
      final ok = _shellMoveToRecycleBin(path);
      if (!ok) {
        failures.add(CleanFailure(path, '移入回收站失败'));
        return false;
      }
      return true;
    }
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
      return true;
    } on FileSystemException catch (e) {
      failures.add(CleanFailure(path, e.osError?.message ?? e.message));
      return false;
    }
  }

  static bool _shellMoveToRecycleBin(String path) {
    final units = path.codeUnits;
    final ptr = calloc<Uint16>(units.length + 2);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    ptr[units.length + 1] = 0;
    final op = calloc<SHFILEOPSTRUCT>()
      ..ref.wFunc = FO_DELETE
      ..ref.pFrom = ptr.cast<Utf16>()
      ..ref.fFlags =
          FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
    try {
      final rc = SHFileOperation(op);
      if (rc != 0) {
        AppLogger.warn('SHFileOperation($path) rc=$rc',
            tag: 'StartupCleaner');
        return false;
      }
      return op.ref.fAnyOperationsAborted == 0;
    } finally {
      calloc.free(ptr);
      calloc.free(op);
    }
  }
}
