import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';

class ShortcutInfo {
  ShortcutInfo({
    required this.lnkPath,
    required this.target,
    required this.arguments,
    required this.workingDirectory,
  });

  final String lnkPath;

  /// 解析后的目标路径。空字符串表示无法解析或为非文件目标。
  final String target;
  final String arguments;
  final String workingDirectory;

  bool get hasFileTarget => target.isNotEmpty && !target.startsWith(r'\\');
}

/// 通过 `IShellLinkW + IPersistFile` 解析 `.lnk` 文件。
///
/// 调用者**必须**在使用前初始化 COM（一般在程序启动期），或包在
/// `runCoInitialized` 区段内。
class ShortcutResolver {
  ShortcutResolver._();

  /// 初始化 COM（线程级 STA），执行 [body]，结束后反初始化。
  static Future<T> runCoInitialized<T>(Future<T> Function() body) async {
    if (!Platform.isWindows) return body();
    final hr = CoInitializeEx(
      nullptr,
      COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
    );
    final init = hr == S_OK || hr == S_FALSE;
    try {
      return await body();
    } finally {
      if (init) CoUninitialize();
    }
  }

  /// 解析单个 .lnk，失败时返回 null。需要先 [runCoInitialized]。
  static ShortcutInfo? resolve(String lnkPath) {
    if (!Platform.isWindows) return null;
    final link = ShellLink.createInstance();
    try {
      final pf = IPersistFile(link.toInterface(IID_IPersistFile));
      try {
        final pPath = lnkPath.toNativeUtf16();
        try {
          final hr = pf.load(pPath, STGM_READ);
          if (FAILED(hr)) {
            AppLogger.debug(
              'IPersistFile.Load failed hr=$hr ($lnkPath)',
              tag: 'Shortcut',
            );
            return null;
          }
        } finally {
          free(pPath);
        }

        const bufLen = MAX_PATH * 2;
        final targetBuf = calloc<Uint16>(bufLen).cast<Utf16>();
        final argsBuf = calloc<Uint16>(bufLen).cast<Utf16>();
        final wdBuf = calloc<Uint16>(bufLen).cast<Utf16>();
        try {
          // SLGP_RAWPATH：不展开环境变量；SLGP_UNCPRIORITY：UNC 优先
          final hrTarget = link.getPath(
            targetBuf,
            bufLen,
            nullptr,
            SLGP_RAWPATH,
          );
          link.getArguments(argsBuf, bufLen);
          link.getWorkingDirectory(wdBuf, bufLen);

          if (FAILED(hrTarget)) {
            return ShortcutInfo(
              lnkPath: lnkPath,
              target: '',
              arguments: argsBuf.toDartString(),
              workingDirectory: wdBuf.toDartString(),
            );
          }
          return ShortcutInfo(
            lnkPath: lnkPath,
            target: targetBuf.toDartString(),
            arguments: argsBuf.toDartString(),
            workingDirectory: wdBuf.toDartString(),
          );
        } finally {
          calloc.free(targetBuf);
          calloc.free(argsBuf);
          calloc.free(wdBuf);
        }
      } finally {
        pf.release();
      }
    } catch (e, st) {
      AppLogger.warn('resolve $lnkPath failed: $e\n$st', tag: 'Shortcut');
      return null;
    } finally {
      link.release();
    }
  }
}
