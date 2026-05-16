import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';
import '../../core/utils/registry_safety_guard.dart';
import '../../core/utils/safety_guard.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/entities/residue_item.dart';
import '../platform/registry_reader.dart';
import 'registry_backup_service.dart';

/// 清理 [ResidueItem]。
///  - 文件/目录 / 失效快捷方式：经 [SafetyGuard] 校验 → 移入回收站；
///  - 注册表键：备份 .reg → 经 [RegistrySafetyGuard] 校验 → `RegDeleteTree`。
class ResidueCleanerService {
  ResidueCleanerService._();

  static Future<ResidueCleanReport> clean(List<ResidueItem> items) async {
    if (items.isEmpty) return ResidueCleanReport.empty();

    var freed = 0;
    var deleted = 0;
    final failures = <CleanFailure>[];
    String? backupDir;

    RegistryBackupService? session;
    final hasRegistry = items.any((it) => it.kind == ResidueKind.registryKey);
    if (hasRegistry && Platform.isWindows) {
      try {
        session = await RegistryBackupService.openSession();
        backupDir = session.sessionDir;
      } on Object catch (e) {
        AppLogger.error(
          'open backup session failed',
          error: e,
          tag: 'ResidueCleaner',
        );
        // 备份目录创建失败仍要继续；具体注册表项导出失败时跳过该项。
      }
    }

    for (final item in items) {
      try {
        switch (item.kind) {
          case ResidueKind.fileDir:
          case ResidueKind.deadShortcut:
            await _deleteFileOrDir(item, (bytes) {
              freed += bytes;
              deleted++;
            }, failures);
          case ResidueKind.registryKey:
            await _deleteRegistry(item, session, (bytes) {
              freed += bytes;
              deleted++;
            }, failures);
        }
      } on Object catch (e, st) {
        AppLogger.error(
          'clean residue ${item.path} threw',
          error: e, stack: st, tag: 'ResidueCleaner',
        );
        failures.add(CleanFailure(item.path, e.toString()));
      }
    }

    return ResidueCleanReport(
      bytesFreed: freed,
      itemsDeleted: deleted,
      failures: failures,
      registryBackupDir: backupDir,
    );
  }

  static Future<void> _deleteFileOrDir(
    ResidueItem item,
    void Function(int bytes) onOk,
    List<CleanFailure> failures,
  ) async {
    if (!SafetyGuard.isSafeToDelete(item.path)) {
      failures.add(CleanFailure(item.path, '受保护路径，已跳过'));
      return;
    }
    if (Platform.isWindows) {
      final ok = _shellMoveToRecycleBin(item.path);
      if (!ok) {
        failures.add(CleanFailure(item.path, '移入回收站失败'));
        return;
      }
      onOk(item.size);
      return;
    }
    // 非 Windows：直接删除（用于测试）
    try {
      final dir = Directory(item.path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        onOk(item.size);
        return;
      }
      final f = File(item.path);
      if (await f.exists()) {
        await f.delete();
        onOk(item.size);
        return;
      }
      failures.add(CleanFailure(item.path, '路径不存在'));
    } on FileSystemException catch (e) {
      failures.add(CleanFailure(item.path, e.osError?.message ?? e.message));
    }
  }

  static Future<void> _deleteRegistry(
    ResidueItem item,
    RegistryBackupService? session,
    void Function(int bytes) onOk,
    List<CleanFailure> failures,
  ) async {
    if (!Platform.isWindows) {
      failures.add(CleanFailure(item.path, '仅 Windows 支持注册表清理'));
      return;
    }
    if (!RegistrySafetyGuard.isSafeToDelete(item.path)) {
      failures.add(CleanFailure(item.path, '受保护注册表键，已跳过'));
      return;
    }
    if (session == null) {
      failures.add(CleanFailure(item.path, '无备份目录，已跳过'));
      return;
    }
    final backup = await session.exportKey(item.path);
    if (backup == null) {
      failures.add(CleanFailure(item.path, '导出 .reg 备份失败，已跳过删除'));
      return;
    }
    final ok = _regDeleteTree(item);
    if (!ok) {
      failures.add(CleanFailure(item.path, 'RegDeleteTree 失败（可能需管理员权限）'));
      return;
    }
    onOk(item.size);
  }

  /// 调用 `SHFileOperationW` 把单个文件 / 目录移入回收站。
  /// `pFrom` 必须是双 NUL 结尾的字符串（多文件分隔）。
  static bool _shellMoveToRecycleBin(String path) {
    // 构造 "path\0\0"：两个 NUL 终止符（pFrom 必须双零结尾）
    final bytes = path.codeUnits;
    final ptr = calloc<Uint16>(bytes.length + 2);
    for (var i = 0; i < bytes.length; i++) {
      ptr[i] = bytes[i];
    }
    ptr[bytes.length] = 0;
    ptr[bytes.length + 1] = 0;
    final pFrom = ptr.cast<Utf16>();
    final op = calloc<SHFILEOPSTRUCT>()
      ..ref.wFunc = FO_DELETE
      ..ref.pFrom = pFrom
      ..ref.fFlags =
          FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
    try {
      final rc = SHFileOperation(op);
      if (rc != 0) {
        AppLogger.warn(
          'SHFileOperation($path) rc=$rc '
          'aborted=${op.ref.fAnyOperationsAborted}',
          tag: 'ResidueCleaner',
        );
        return false;
      }
      return op.ref.fAnyOperationsAborted == 0;
    } finally {
      calloc.free(ptr);
      calloc.free(op);
    }
  }

  static bool _regDeleteTree(ResidueItem item) {
    // path 已是规范化形式（32-bit 残留也写成 HKLM\SOFTWARE\Wow6432Node\X），
    // 所以始终用 64-bit 视图打开即可。
    const view = RegView.v64;
    final lower = item.path.toLowerCase();
    final RegRoot root;
    String subKey;
    if (lower.startsWith('hklm\\')) {
      root = RegRoot.hklm;
      subKey = item.path.substring(5);
    } else if (lower.startsWith('hkcu\\')) {
      root = RegRoot.hkcu;
      subKey = item.path.substring(5);
    } else {
      AppLogger.warn('unknown registry root: ${item.path}',
          tag: 'ResidueCleaner');
      return false;
    }
    final lastSep = subKey.lastIndexOf('\\');
    if (lastSep <= 0) return false;
    final parentSub = subKey.substring(0, lastSep);
    final leaf = subKey.substring(lastSep + 1);
    final parent = RegKey.open(root, parentSub, view: view);
    if (parent == null) return false;
    try {
      return parent.deleteSubTree(leaf);
    } finally {
      parent.close();
    }
  }
}
