import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/app_paths.dart';
import '../../core/utils/logger.dart';

/// 用 Windows DPAPI 加密 / 解密 refresh_token 并落到 [AppPaths.authFile]。
///
/// - 加密密钥由 Windows 按当前用户登录凭据派生 → 跨用户 / 跨机器无法解；
/// - 文件存在但解密失败（迁机器、SID 变化）→ 视为未登录，清空；
/// - 不存 access_token，那个只在内存里。
class AuthStore {
  AuthStore({String? filePath}) : _path = filePath ?? AppPaths.authFile();

  final String _path;

  static const _tag = 'AuthStore';

  /// 写入加密后的 refresh_token。
  Future<bool> save(String refreshToken) async {
    final cipher = _dpapiProtect(refreshToken);
    if (cipher == null) {
      AppLogger.warn('protect failed', tag: _tag);
      return false;
    }
    try {
      await File(_path).writeAsBytes(cipher, flush: true);
      return true;
    } on FileSystemException catch (e) {
      AppLogger.warn('write $_path failed: ${e.message}', tag: _tag);
      return false;
    }
  }

  /// 读取并解密 refresh_token；任何失败返回 null。
  Future<String?> load() async {
    final file = File(_path);
    if (!file.existsSync()) return null;
    try {
      final cipher = await file.readAsBytes();
      return _dpapiUnprotect(cipher);
    } on FileSystemException catch (e) {
      AppLogger.warn('read $_path failed: ${e.message}', tag: _tag);
      return null;
    }
  }

  /// 删除文件。登出 / 解密失败 / 用户主动注销时调用。
  Future<void> clear() async {
    try {
      final file = File(_path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException catch (e) {
      AppLogger.warn('delete $_path failed: ${e.message}', tag: _tag);
    }
  }

  // ── DPAPI 封装 ──────────────────────────────────

  Uint8List? _dpapiProtect(String plaintext) {
    if (!Platform.isWindows) return null;
    final bytes = Uint8List.fromList(utf8.encode(plaintext));

    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inBuf = calloc<Uint8>(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        inBuf[i] = bytes[i];
      }
      inBlob.ref.cbData = bytes.length;
      inBlob.ref.pbData = inBuf;

      final ok = CryptProtectData(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        0,
        outBlob,
      );
      if (ok == 0) return null;

      final size = outBlob.ref.cbData;
      final result = Uint8List(size);
      for (var i = 0; i < size; i++) {
        result[i] = outBlob.ref.pbData[i];
      }
      // outBlob.pbData 由 LocalAlloc 分配，需 LocalFree
      LocalFree(outBlob.ref.pbData);
      return result;
    } finally {
      calloc.free(inBuf);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  String? _dpapiUnprotect(Uint8List cipher) {
    if (!Platform.isWindows) return null;
    final inBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<CRYPT_INTEGER_BLOB>();
    final inBuf = calloc<Uint8>(cipher.length);
    try {
      for (var i = 0; i < cipher.length; i++) {
        inBuf[i] = cipher[i];
      }
      inBlob.ref.cbData = cipher.length;
      inBlob.ref.pbData = inBuf;

      final ok = CryptUnprotectData(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        0,
        outBlob,
      );
      if (ok == 0) return null;

      final size = outBlob.ref.cbData;
      final result = Uint8List(size);
      for (var i = 0; i < size; i++) {
        result[i] = outBlob.ref.pbData[i];
      }
      LocalFree(outBlob.ref.pbData);
      try {
        return utf8.decode(result);
      } on FormatException {
        return null;
      }
    } finally {
      calloc.free(inBuf);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }
}
