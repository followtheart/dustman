import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/fileclaw/api_exception.dart';
import '../../data/fileclaw/auth_repository.dart';
import '../../data/fileclaw/dto.dart';

/// FileClaw 账户状态机。
enum AuthState {
  /// 启动期，正在尝试用本地 refresh_token 静默登录。
  loading,

  /// 未登录（包含从未登录、refresh 失效、用户主动登出）。
  unauthenticated,

  /// 正在执行登录 / 注册 / 验证等动作。
  busy,

  /// 已登录。[AuthProvider.profile] 可用。
  authenticated,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo);

  final AuthRepository _repo;

  AuthState _state = AuthState.loading;
  MeProfile? _profile;
  String? _lastError;

  static const _tag = 'AuthProvider';

  AuthState get state => _state;
  MeProfile? get profile => _profile;
  String? get lastError => _lastError;
  bool get isAuthenticated => _state == AuthState.authenticated;

  // ── 启动 ────────────────────────────────────────

  /// 启动时调用：用本地 refresh 静默换 access；失败则进入未登录态。
  Future<void> bootstrap() async {
    _set(AuthState.loading);
    final pair = await _repo.tryAutoRefresh();
    if (pair == null) {
      _set(AuthState.unauthenticated);
      return;
    }
    try {
      _profile = await _repo.me();
      _set(AuthState.authenticated);
    } on Object catch (e) {
      AppLogger.warn('bootstrap /me failed: $e', tag: _tag);
      _set(AuthState.unauthenticated);
    }
  }

  // ── 注册 / 验证 ────────────────────────────────

  Future<bool> register({
    String? email,
    String? phone,
    required String password,
  }) async {
    return _run(() async {
      await _repo.register(email: email, phone: phone, password: password);
    });
  }

  Future<bool> verify({required String target, required String code}) async {
    return _run(() async {
      await _repo.verify(target: target, code: code);
    });
  }

  // ── 登录 ────────────────────────────────────────

  Future<bool> loginWithPassword({
    required String identifier,
    required String password,
    String? deviceLabel,
  }) async {
    return _run(() async {
      await _repo.loginWithPassword(
        identifier: identifier, password: password, deviceLabel: deviceLabel,
      );
      _profile = await _repo.me();
      _state = AuthState.authenticated;
    });
  }

  Future<bool> requestSmsCode({required String phone, required String purpose}) async {
    return _run(() async {
      await _repo.requestSmsCode(phone: phone, purpose: purpose);
    });
  }

  Future<bool> loginWithSms({
    required String phone,
    required String code,
    String? deviceLabel,
  }) async {
    return _run(() async {
      await _repo.loginWithSms(phone: phone, code: code, deviceLabel: deviceLabel);
      _profile = await _repo.me();
      _state = AuthState.authenticated;
    });
  }

  // ── 找回密码 ────────────────────────────────────

  Future<bool> forgotPassword(String identifier) async {
    return _run(() async {
      await _repo.forgotPassword(identifier);
    });
  }

  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    return _run(() async {
      await _repo.resetPassword(
        identifier: identifier, code: code, newPassword: newPassword,
      );
    });
  }

  // ── 登出 ────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _repo.logout();
    } on Object catch (e) {
      AppLogger.warn('logout failed: $e', tag: _tag);
    }
    _profile = null;
    _set(AuthState.unauthenticated);
  }

  // ── /me 刷新（绑定 / 解绑后调用）───────────────

  Future<void> reloadProfile() async {
    try {
      _profile = await _repo.me();
      notifyListeners();
    } on Object catch (e) {
      AppLogger.warn('reloadProfile failed: $e', tag: _tag);
    }
  }

  // ── 内部 ─────────────────────────────────────────

  /// 包一层 busy/notify + 错误捕获。
  /// 注意：成功路径里不强行覆盖 state（让具体方法控制最终态）。
  Future<bool> _run(Future<void> Function() action) async {
    _lastError = null;
    final prev = _state;
    _state = AuthState.busy;
    notifyListeners();
    try {
      await action();
      // 若 action 内已经把 state 改成 authenticated，保留；否则回到 prev。
      if (_state == AuthState.busy) _state = prev;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      _state = prev;
      notifyListeners();
      return false;
    } on Object catch (e) {
      _lastError = e.toString();
      _state = prev;
      notifyListeners();
      return false;
    }
  }

  void _set(AuthState s) {
    _state = s;
    notifyListeners();
  }
}
