import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/installed_program.dart';

/// 启动卸载向导。把 `UninstallString` 拆成 `exe + args`，再调 `ShellExecuteW`，
/// 这样一来：
///  - 用户能看到原厂卸载界面 / 可以在弹窗里取消；
///  - UAC 弹窗由 Windows 自身负责（`verb="runas"` 显式提权可选）；
///  - 我们不直接 `await Process.run`，避免把同步阻塞带到 UI 线程。
class UninstallerService {
  UninstallerService._();

  /// 启动卸载。返回 true 表示进程已经成功拉起（不代表用户最终确认卸载）。
  ///
  /// 当 [silent] 为 true 且 `QuietUninstallString` 不为空时使用静默版本。
  static Future<bool> launch(
    InstalledProgram program, {
    bool silent = false,
  }) async {
    if (!Platform.isWindows) {
      AppLogger.info('non-Windows: skip uninstall', tag: 'Uninstaller');
      return false;
    }
    final cmd = silent
        ? (program.quietUninstallString ?? program.uninstallString)
        : program.uninstallString;
    if (cmd == null || cmd.isEmpty) {
      AppLogger.warn('no UninstallString for ${program.displayName}',
          tag: 'Uninstaller');
      return false;
    }
    final (exe, args) = _splitCommand(cmd);
    if (exe.isEmpty) return false;

    final lpFile = exe.toNativeUtf16();
    final lpParams = args.isEmpty ? nullptr : args.toNativeUtf16();
    // 不用 "runas"：让目标安装包自己决定要不要 UAC。
    final lpVerb = 'open'.toNativeUtf16();
    try {
      final rc = ShellExecute(
        NULL,
        lpVerb,
        lpFile,
        lpParams,
        nullptr,
        SW_SHOWNORMAL,
      );
      // ShellExecute 返回 > 32 表示成功
      if (rc <= 32) {
        AppLogger.warn(
          'ShellExecute($exe) failed rc=$rc',
          tag: 'Uninstaller',
        );
        return false;
      }
      AppLogger.info(
        'started uninstaller: $exe $args',
        tag: 'Uninstaller',
      );
      return true;
    } finally {
      free(lpFile);
      if (lpParams != nullptr) free(lpParams);
      free(lpVerb);
    }
  }

  /// 拆分 `"C:\Program Files\Foo\unins000.exe" /qn` 为 (exe, args)。
  ///
  /// 兼容以下三种形态：
  ///  - 带引号路径：`"...\foo.exe" args`
  ///  - 不带引号、无空格：`foo.exe /S`
  ///  - MsiExec 命令：`MsiExec.exe /X{GUID}`
  static (String, String) _splitCommand(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return ('', '');
    if (s.startsWith('"')) {
      final end = s.indexOf('"', 1);
      if (end < 0) return (s.substring(1), '');
      final exe = s.substring(1, end);
      final args = end + 1 < s.length ? s.substring(end + 1).trim() : '';
      return (exe, args);
    }
    // 没有引号 —— 找出第一个 `.exe` 后的空格作为切分点
    final lower = s.toLowerCase();
    final exeIdx = lower.indexOf('.exe');
    if (exeIdx > 0) {
      final tail = exeIdx + 4;
      if (tail >= s.length) {
        return (s, '');
      }
      // .exe 之后必须紧跟空格 / Tab 才算分隔
      final next = s[tail];
      if (next == ' ' || next == '\t') {
        return (s.substring(0, tail), s.substring(tail + 1).trim());
      }
    }
    // 实在拆不出来：当成整体可执行命令交给 ShellExecute
    return (s, '');
  }

  /// 公开测试入口。
  static (String, String) splitCommandForTest(String raw) => _splitCommand(raw);
}
