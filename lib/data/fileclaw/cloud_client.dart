import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import 'api_exception.dart';
import 'dto.dart';

/// 与 dustman-cloud 对接的 HTTP 客户端。
///
/// - 只持有当前 access_token；refresh 由上层 AuthRepository 主导；
/// - 不自动重试，让 AuthRepository 决策（避免 race）；
/// - 所有方法在错误时抛 [ApiException]，调用方按 kind 处理。
class CloudClient {
  CloudClient({
    required this.baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  })  : _client = httpClient ?? http.Client(),
        _timeout = timeout;

  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;

  String? _accessToken;

  /// 只读暴露给 AiSession 复用同一个 access_token，避免双轨刷新。
  String? get currentAccessToken => _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  void close() {
    _client.close();
  }

  // ── 健康检查 ────────────────────────────────────

  Future<bool> health() async {
    try {
      final resp = await _client
          .get(_url('/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['status'] == 'ok';
    } on Object {
      return false;
    }
  }

  // ── 注册 / 验证 ─────────────────────────────────

  Future<void> register({
    String? email,
    String? phone,
    required String password,
  }) async {
    await _post('/auth/register', {
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      'password': password,
    });
  }

  Future<void> verify({required String target, required String code}) async {
    await _post('/auth/verify', {'target': target, 'code': code});
  }

  // ── 登录（密码 / 短信 OTP）──────────────────────

  Future<TokenPair> loginWithPassword({
    required String identifier,
    required String password,
    String? deviceLabel,
  }) async {
    final body = await _post('/auth/login', {
      'identifier': identifier,
      'password': password,
      if (deviceLabel != null) 'device_label': deviceLabel,
    });
    return TokenPair.fromJson(body);
  }

  Future<void> requestSmsCode({required String phone, required String purpose}) async {
    await _post('/auth/sms/request', {'phone': phone, 'purpose': purpose});
  }

  Future<TokenPair> loginWithSms({
    required String phone,
    required String code,
    String? deviceLabel,
  }) async {
    final body = await _post('/auth/sms/login', {
      'phone': phone,
      'code': code,
      if (deviceLabel != null) 'device_label': deviceLabel,
    });
    return TokenPair.fromJson(body);
  }

  // ── 刷新 / 登出 ─────────────────────────────────

  Future<TokenPair> refresh(String refreshToken) async {
    final body = await _post('/auth/refresh', {'refresh_token': refreshToken});
    return TokenPair.fromJson(body);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _post('/auth/logout', {'refresh_token': refreshToken});
    } on ApiException {
      // 登出失败不抛给上层 —— 本地清理优先
    }
  }

  // ── 找回密码 ────────────────────────────────────

  Future<void> forgotPassword(String identifier) async {
    await _post('/auth/password/forgot', {'identifier': identifier});
  }

  Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await _post('/auth/password/reset', {
      'identifier': identifier,
      'code': code,
      'new_password': newPassword,
    });
  }

  // ── /me 与绑定 ──────────────────────────────────

  Future<MeProfile> me() async {
    final body = await _get('/auth/me');
    return MeProfile.fromJson(body);
  }

  Future<void> requestBinding(String target) async {
    await _post('/auth/me/bindings/request', {'target': target});
  }

  Future<void> confirmBinding({required String target, required String code}) async {
    await _post('/auth/me/bindings/confirm', {'target': target, 'code': code});
  }

  Future<void> unbind(String kind) async {
    await _delete('/auth/me/bindings/$kind');
  }

  // ── 内部 ─────────────────────────────────────────

  Uri _url(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Dustman/${AppConstants.appVersion} (Pro)',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final resp = await _client
          .post(_url(path), headers: _headers(), body: jsonEncode(payload))
          .timeout(_timeout);
      return _decode(resp);
    } on TimeoutException {
      throw ApiException.offline();
    } on Object catch (e) {
      throw ApiException.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final resp = await _client.get(_url(path), headers: _headers()).timeout(_timeout);
      return _decode(resp);
    } on TimeoutException {
      throw ApiException.offline();
    } on Object catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    try {
      final resp = await _client.delete(_url(path), headers: _headers()).timeout(_timeout);
      return _decode(resp);
    } on TimeoutException {
      throw ApiException.offline();
    } on Object catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.network(e.toString());
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    final ct = resp.headers['content-type'] ?? '';
    final isJson = ct.contains('application/json');
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return const <String, dynamic>{};
      if (!isJson) return const <String, dynamic>{};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    String message = 'http ${resp.statusCode}';
    if (isJson && resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['detail'] is String) {
          message = decoded['detail'] as String;
        } else if (decoded is Map && decoded['detail'] is List) {
          // pydantic 校验错误
          final first = (decoded['detail'] as List).first;
          if (first is Map && first['msg'] is String) {
            message = first['msg'] as String;
          }
        }
      } on Object {
        // body 不是合法 JSON，回退 message
      }
    }
    throw ApiException(statusCode: resp.statusCode, message: message);
  }
}
