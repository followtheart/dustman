import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';

/// 通过 Win32 API 查询与清空回收站。非 Windows 平台返回 0 / 直接返回成功。
class RecycleBinService {
  /// 返回当前所有驱动器上回收站的总占用字节数。
  static int querySize() {
    if (!Platform.isWindows) return 0;
    final info = calloc<SHQUERYRBINFO>()
      ..ref.cbSize = sizeOf<SHQUERYRBINFO>();
    try {
      // pszRootPath = nullptr 表示查询所有驱动器
      final hr = SHQueryRecycleBin(nullptr, info);
      if (hr != S_OK) {
        AppLogger.warn('SHQueryRecycleBin failed: hr=$hr', tag: 'RecycleBin');
        return 0;
      }
      return info.ref.i64Size;
    } finally {
      calloc.free(info);
    }
  }

  static int queryItemCount() {
    if (!Platform.isWindows) return 0;
    final info = calloc<SHQUERYRBINFO>()
      ..ref.cbSize = sizeOf<SHQUERYRBINFO>();
    try {
      final hr = SHQueryRecycleBin(nullptr, info);
      if (hr != S_OK) return 0;
      return info.ref.i64NumItems;
    } finally {
      calloc.free(info);
    }
  }

  /// 清空全部回收站。flags 默认安静模式（不弹原生确认框）。
  static bool empty({bool silent = true}) {
    if (!Platform.isWindows) return true;
    var flags = 0;
    if (silent) {
      flags = SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND;
    }
    final hr = SHEmptyRecycleBin(NULL, nullptr, flags);
    if (hr != S_OK) {
      AppLogger.warn('SHEmptyRecycleBin failed: hr=$hr', tag: 'RecycleBin');
      return false;
    }
    return true;
  }
}
