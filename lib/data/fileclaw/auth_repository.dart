import 'dart:async';

import '../../core/utils/logger.dart';
import 'api_exception.dart';
import 'auth_store.dart';
import 'cloud_client.dart';
import 'dto.dart';

/// 把 CloudClient（远端）与 AuthStore（本地持久化）编排成应用可用的接口。
///
/// 状态由 [AuthProvider] 维护，本类无状态、纯方法。
class AuthRepository {
  AuthRepository({required this.client, required this.store});

  final CloudClient client;
  final AuthStore store;

  static const _tag = 'AuthRepo';

  // ── 启动期：尝试用本地 refresh 恢复会话 ────────

  /// 启动时调用。返回 (accessToken, refreshToken) 或 null。
  Future<TokenPair?> tryAutoRefresh() async {
    final refresh = await store.load();
    if (refresh == null) return null;
    try {
      final pair = await client.refresh(refresh);
      await store.save(pair.refreshToken);
      client.setAccessToken(pair.accessToken);
      AppLogger.info('auto-refresh ok', tag: _tag);
      return pair;
    } on ApiException catch (e) {
      AppLogger.warn('auto-refresh failed: $e', tag: _tag);
      if (e.kind == ApiErrorKind.network) {
        // 网络问题不清除本地凭证 —— 用户可能只是断网
        return null;
      }
      // 401 / 403 / 其它服务端拒绝 → 清除本地凭证
      await store.clear();
      return null;
    }
  }

  // ── 注册 ────────────────────────────────────────

  Future<void> register({
    String? email,
    String? phone,
    required String password,
  }) async {
    await client.register(email: email, phone: phone, password: password);
  }

  Future<void> verify({required String target, required String code}) async {
    await client.verify(target: target, code: code);
  }

  // ── 登录（密码 / SMS OTP）──────────────────────

  Future<TokenPair> loginWithPassword({
    required String identifier,
    required String password,
    String? deviceLabel,
  }) async {
    final pair = await client.loginWithPassword(
      identifier: identifier,
      password: password,
      deviceLabel: deviceLabel,
    );
    await _persist(pair);
    return pair;
  }

  Future<void> requestSmsCode({required String phone, required String purpose}) async {
    await client.requestSmsCode(phone: phone, purpose: purpose);
  }

  Future<TokenPair> loginWithSms({
    required String phone,
    required String code,
    String? deviceLabel,
  }) async {
    final pair = await client.loginWithSms(
      phone: phone, code: code, deviceLabel: deviceLabel,
    );
    await _persist(pair);
    return pair;
  }

  // ── 刷新 / 登出 ─────────────────────────────────

  Future<TokenPair?> refreshNow() async {
    final refresh = await store.load();
    if (refresh == null) return null;
    try {
      final pair = await client.refresh(refresh);
      await _persist(pair);
      return pair;
    } on ApiException catch (e) {
      AppLogger.warn('refresh failed: $e', tag: _tag);
      if (e.isAuth) {
        await store.clear();
        client.setAccessToken(null);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final refresh = await store.load();
    if (refresh != null) {
      await client.logout(refresh);
    }
    await store.clear();
    client.setAccessToken(null);
  }

  // ── 找回密码 ────────────────────────────────────

  Future<void> forgotPassword(String identifier) async {
    await client.forgotPassword(identifier);
  }

  Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await client.resetPassword(
      identifier: identifier, code: code, newPassword: newPassword,
    );
  }

  // ── /me ─────────────────────────────────────────

  Future<MeProfile> me() => client.me();

  // ── 内部 ─────────────────────────────────────────

  Future<void> _persist(TokenPair pair) async {
    client.setAccessToken(pair.accessToken);
    await store.save(pair.refreshToken);
  }
}
