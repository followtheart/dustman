import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../../core/utils/file_size_formatter.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/safety_guard.dart';
import 'tool_registry.dart';

const int _kListDirMax = 64;
const int _kReadHeadMaxBytes = 4096;

/// 把 filemcp 系列工具注册到 [ToolRegistry]。
void registerFileMcpTools() {
  final reg = ToolRegistry.instance;
  reg.register('filemcp.stat', _stat);
  reg.register('filemcp.list_dir', _listDir);
  reg.register('filemcp.read_text_head', _readTextHead);
  reg.register('filemcp.safe_delete', _safeDelete);
}

// ── stat ─────────────────────────────────────────


Future<Map<String, Object?>> _stat(Map<String, Object?> args) async {
  final path = _requirePath(args);
  final entity = FileSystemEntity.typeSync(path, followLinks: false);
  if (entity == FileSystemEntityType.notFound) {
    return {'exists': false, 'path': path};
  }
  try {
    final stat = await FileStat.stat(path);
    return {
      'exists': true,
      'path': path,
      'type': _typeName(entity),
      'size': stat.size,
      'mtime': stat.modified.toIso8601String(),
      'humanSize': FileSizeFormatter.format(stat.size),
    };
  } on FileSystemException catch (e) {
    return {'exists': true, 'path': path, 'error': e.message};
  }
}

// ── list_dir ─────────────────────────────────────


Future<Map<String, Object?>> _listDir(Map<String, Object?> args) async {
  final path = _requirePath(args);
  final maxRaw = args['max'];
  final max = (maxRaw is int && maxRaw > 0 && maxRaw <= 256) ? maxRaw : _kListDirMax;

  final dir = Directory(path);
  if (!dir.existsSync()) {
    return {'exists': false, 'path': path, 'entries': const []};
  }
  final entries = <Map<String, Object?>>[];
  try {
    final stream = dir.list(followLinks: false);
    await for (final e in stream) {
      if (entries.length >= max) break;
      final type = await FileSystemEntity.type(e.path, followLinks: false);
      int size = 0;
      String? mtime;
      try {
        final stat = await FileStat.stat(e.path);
        size = stat.size;
        mtime = stat.modified.toIso8601String();
      } on FileSystemException {
        // skip stat
      }
      entries.add({
        'name': p.basename(e.path),
        'path': e.path,
        'type': _typeName(type),
        'size': size,
        if (mtime != null) 'mtime': mtime,
      });
    }
  } on FileSystemException catch (e) {
    return {'exists': true, 'path': path, 'error': e.message, 'entries': entries};
  }
  return {
    'exists': true,
    'path': path,
    'entries': entries,
    'truncated': entries.length >= max,
  };
}

// ── read_text_head ──────────────────────────────


Future<Map<String, Object?>> _readTextHead(Map<String, Object?> args) async {
  final path = _requirePath(args);
  final maxRaw = args['max_bytes'];
  final maxBytes =
      (maxRaw is int && maxRaw >= 128 && maxRaw <= 16384) ? maxRaw : _kReadHeadMaxBytes;

  final file = File(path);
  if (!file.existsSync()) {
    return {'exists': false, 'path': path};
  }
  try {
    final raf = await file.open();
    try {
      final bytes = await raf.read(maxBytes);
      // 试 UTF-8；失败回退 hex preview
      try {
        final text = utf8.decode(bytes, allowMalformed: false);
        return {
          'exists': true,
          'path': path,
          'encoding': 'utf-8',
          'text': text,
          'bytes_read': bytes.length,
        };
      } on FormatException {
        // ignore
      }
      // 二进制：给前 64 字节的 hex
      final preview = bytes.take(64).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return {
        'exists': true,
        'path': path,
        'encoding': 'binary',
        'hex_preview': preview,
        'bytes_read': bytes.length,
      };
    } finally {
      await raf.close();
    }
  } on FileSystemException catch (e) {
    return {'exists': true, 'path': path, 'error': e.message};
  }
}

// ── safe_delete（写工具）─────────────────────────


Future<Map<String, Object?>> _safeDelete(Map<String, Object?> args) async {
  final path = _requirePath(args);
  // SafetyGuard 是硬拦截：AI 即便穿越 needs_user_consent 也不能删除受保护路径
  if (!SafetyGuard.isSafeToDelete(path)) {
    AppLogger.warn('AI tried to delete protected path: $path', tag: 'filemcp');
    return {'ok': false, 'reason': 'protected_path'};
  }
  if (!Platform.isWindows) {
    return {'ok': false, 'reason': 'not_windows'};
  }
  final ok = _shellMoveToRecycleBin(path);
  AppLogger.info(
    ok ? 'safe_delete ok: $path' : 'safe_delete failed: $path',
    tag: 'filemcp',
  );
  return {'ok': ok, 'path': path};
}

bool _shellMoveToRecycleBin(String path) {
  final bytes = path.codeUnits;
  final ptr = calloc<Uint16>(bytes.length + 2);
  for (var i = 0; i < bytes.length; i++) {
    ptr[i] = bytes[i];
  }
  ptr[bytes.length] = 0;
  ptr[bytes.length + 1] = 0;
  final op = calloc<SHFILEOPSTRUCT>()
    ..ref.wFunc = FO_DELETE
    ..ref.pFrom = ptr.cast<Utf16>()
    ..ref.fFlags =
        FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
  try {
    final rc = SHFileOperation(op);
    if (rc != 0) return false;
    return op.ref.fAnyOperationsAborted == 0;
  } finally {
    calloc.free(ptr);
    calloc.free(op);
  }
}

// ── 内部 ─────────────────────────────────────────


String _requirePath(Map<String, Object?> args) {
  final v = args['path'];
  if (v is! String || v.isEmpty) {
    throw ArgumentError('missing arg: path');
  }
  return v;
}

String _typeName(FileSystemEntityType t) {
  if (t == FileSystemEntityType.file) return 'file';
  if (t == FileSystemEntityType.directory) return 'dir';
  if (t == FileSystemEntityType.link) return 'symlink';
  return 'unknown';
}

