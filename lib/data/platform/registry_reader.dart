import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';

/// 注册表根：HKLM 或 HKCU。
enum RegRoot {
  hklm,
  hkcu;

  int get handle => switch (this) {
        RegRoot.hklm => HKEY_LOCAL_MACHINE,
        RegRoot.hkcu => HKEY_CURRENT_USER,
      };

  String get prefix => switch (this) {
        RegRoot.hklm => 'HKLM',
        RegRoot.hkcu => 'HKCU',
      };
}

/// 32-bit / 64-bit 视图。
enum RegView {
  v64,
  v32;

  int get flag => switch (this) {
        RegView.v64 => KEY_WOW64_64KEY,
        RegView.v32 => KEY_WOW64_32KEY,
      };
}

/// 子键基本信息。
class RegSubKeyInfo {
  RegSubKeyInfo({
    required this.name,
    required this.lastWriteTime,
    required this.subKeyCount,
    required this.valueCount,
  });

  final String name;
  final DateTime lastWriteTime;
  final int subKeyCount;
  final int valueCount;
}

/// 一个已打开的注册表键句柄。**必须**调用 `close()` 释放。
class RegKey {
  RegKey._(this._handle, this.fullPath, this.view);

  final int _handle;

  /// 该键的完整路径（含根，例如 `HKLM\SOFTWARE\Adobe`）。
  final String fullPath;
  final RegView view;

  bool _closed = false;

  /// 打开一个键。失败返回 null。
  static RegKey? open(
    RegRoot root,
    String subKey, {
    RegView view = RegView.v64,
  }) {
    if (!Platform.isWindows) return null;
    final lp = subKey.toNativeUtf16();
    final phk = calloc<HANDLE>();
    try {
      final rc = RegOpenKeyEx(
        root.handle,
        lp,
        0,
        KEY_READ | view.flag,
        phk,
      );
      if (rc != ERROR_SUCCESS) {
        return null;
      }
      final full = subKey.isEmpty ? root.prefix : '${root.prefix}\\$subKey';
      return RegKey._(phk.value, full, view);
    } finally {
      free(lp);
      calloc.free(phk);
    }
  }

  /// 枚举所有直接子键（仅一级）。
  List<RegSubKeyInfo> enumSubKeys() {
    if (!Platform.isWindows || _closed) return const [];
    final out = <RegSubKeyInfo>[];
    const bufLen = 512;
    final nameBuf = calloc<Uint16>(bufLen).cast<Utf16>();
    final nameLen = calloc<DWORD>();
    final ft = calloc<FILETIME>();

    var i = 0;
    try {
      while (true) {
        nameLen.value = bufLen;
        final rc = RegEnumKeyEx(
          _handle,
          i,
          nameBuf,
          nameLen,
          nullptr,
          nullptr,
          nullptr,
          ft,
        );
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc != ERROR_SUCCESS) {
          AppLogger.debug(
            'RegEnumKeyEx rc=$rc at $fullPath[$i]',
            tag: 'RegistryReader',
          );
          break;
        }
        final name = nameBuf.toDartString();

        // 二级信息：subKeyCount / valueCount，可选。
        final sub = openSubKey(name);
        var subKeyCount = 0;
        var valueCount = 0;
        var lastWrite = _filetimeToDart(ft.ref);
        if (sub != null) {
          final info = sub._queryInfo();
          if (info != null) {
            subKeyCount = info.$1;
            valueCount = info.$2;
            lastWrite = info.$3;
          }
          sub.close();
        }

        out.add(RegSubKeyInfo(
          name: name,
          lastWriteTime: lastWrite,
          subKeyCount: subKeyCount,
          valueCount: valueCount,
        ));
        i++;
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(nameLen);
      calloc.free(ft);
    }
    return out;
  }

  /// 仅枚举子键名称（不查 LastWriteTime / 子项计数），更轻量。
  List<String> enumSubKeyNames() {
    if (!Platform.isWindows || _closed) return const [];
    final out = <String>[];
    const bufLen = 512;
    final nameBuf = calloc<Uint16>(bufLen).cast<Utf16>();
    final nameLen = calloc<DWORD>();
    var i = 0;
    try {
      while (true) {
        nameLen.value = bufLen;
        final rc = RegEnumKeyEx(
          _handle, i, nameBuf, nameLen, nullptr, nullptr, nullptr, nullptr,
        );
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc != ERROR_SUCCESS) break;
        out.add(nameBuf.toDartString());
        i++;
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(nameLen);
    }
    return out;
  }

  RegKey? openSubKey(String name) {
    if (!Platform.isWindows || _closed) return null;
    final lp = name.toNativeUtf16();
    final phk = calloc<HANDLE>();
    try {
      final rc = RegOpenKeyEx(_handle, lp, 0, KEY_READ | view.flag, phk);
      if (rc != ERROR_SUCCESS) return null;
      return RegKey._(phk.value, '$fullPath\\$name', view);
    } finally {
      free(lp);
      calloc.free(phk);
    }
  }

  /// 读取 REG_SZ / REG_EXPAND_SZ 字符串值。其它类型返回 null。
  String? readString(String valueName) {
    if (!Platform.isWindows || _closed) return null;
    final lpName = valueName.toNativeUtf16();
    final type = calloc<DWORD>();
    final size = calloc<DWORD>();
    try {
      // 先探测大小
      final probe = RegQueryValueEx(
        _handle, lpName, nullptr, type, nullptr, size,
      );
      if (probe != ERROR_SUCCESS) return null;
      if (type.value != REG_SZ && type.value != REG_EXPAND_SZ) return null;
      if (size.value == 0) return '';
      // size 单位是字节；至少能容纳一个 wchar
      final byteLen = size.value;
      final buf = calloc<Uint8>(byteLen + 2);
      try {
        final rc = RegQueryValueEx(
          _handle, lpName, nullptr, type, buf, size,
        );
        if (rc != ERROR_SUCCESS) return null;
        // toDartString() 在 Utf16 上会按 \0 截断，无需手动 trim。
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      free(lpName);
      calloc.free(type);
      calloc.free(size);
    }
  }

  /// 读取 DWORD 值；不存在或类型不符返回 null。
  int? readDword(String valueName) {
    if (!Platform.isWindows || _closed) return null;
    final lpName = valueName.toNativeUtf16();
    final type = calloc<DWORD>();
    final data = calloc<DWORD>();
    final size = calloc<DWORD>()..value = sizeOf<DWORD>();
    try {
      final rc = RegQueryValueEx(_handle, lpName, nullptr, type, data, size);
      if (rc != ERROR_SUCCESS) return null;
      if (type.value != REG_DWORD) return null;
      return data.value;
    } finally {
      free(lpName);
      calloc.free(type);
      calloc.free(data);
      calloc.free(size);
    }
  }

  /// 查询 (subKeyCount, valueCount, lastWriteTime)。
  (int, int, DateTime)? _queryInfo() {
    if (!Platform.isWindows || _closed) return null;
    final subKeys = calloc<DWORD>();
    final values = calloc<DWORD>();
    final ft = calloc<FILETIME>();
    try {
      final rc = RegQueryInfoKey(
        _handle,
        nullptr,
        nullptr,
        nullptr,
        subKeys,
        nullptr,
        nullptr,
        values,
        nullptr,
        nullptr,
        nullptr,
        ft,
      );
      if (rc != ERROR_SUCCESS) return null;
      return (subKeys.value, values.value, _filetimeToDart(ft.ref));
    } finally {
      calloc.free(subKeys);
      calloc.free(values);
      calloc.free(ft);
    }
  }

  /// 公开版本。
  (int, int, DateTime)? queryInfo() => _queryInfo();

  /// 递归删除该键下名为 [name] 的子键。
  /// 返回是否成功；常见失败原因：权限不足、键不存在、键被占用。
  bool deleteSubTree(String name) {
    if (!Platform.isWindows || _closed) return false;
    final lp = name.toNativeUtf16();
    try {
      final rc = RegDeleteTree(_handle, lp);
      if (rc != ERROR_SUCCESS) {
        AppLogger.warn(
          'RegDeleteTree($fullPath\\$name) rc=$rc',
          tag: 'RegistryReader',
        );
        return false;
      }
      return true;
    } finally {
      free(lp);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (Platform.isWindows) {
      RegCloseKey(_handle);
    }
  }
}

/// Windows FILETIME（自 1601-01-01 UTC 起的 100ns 节拍）→ Dart DateTime。
DateTime _filetimeToDart(FILETIME ft) {
  // 64-bit composition
  final ticks = (ft.dwHighDateTime << 32) | (ft.dwLowDateTime & 0xFFFFFFFF);
  // 1601-01-01 UTC 与 1970-01-01 UTC 相差 11644473600 秒
  const epochDiffSeconds = 11644473600;
  final seconds = (ticks ~/ 10000000) - epochDiffSeconds;
  if (seconds < 0 || seconds > 0x7FFFFFFFFFFF) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
