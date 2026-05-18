import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import 'api_exception.dart';
import 'fileclaw_logger.dart';
import 'tool_runtime/tool_registry.dart';

/// 端侧 AI 会话。生命周期与一次 ✦ 点击对应。
///
/// 流程：
///   1) POST /ai/sessions 拿 session_id；
///   2) GET /ai/sessions/{id}/stream 订阅 SSE；
///   3) 收到 tool_call 帧 → 用 [ToolRegistry] 执行 → POST /ai/sessions/{id}/tool-result；
///   4) 收到 final / error → 通过 [events] 流出对应事件 → close。
/// 写工具二次确认回调。返回 true=允许执行；false=用户拒绝。
typedef ConsentResolver = Future<bool> Function(String tool, Map<String, Object?> args);

class AiSessionClient {
  AiSessionClient({
    required this.baseUrl,
    required this.accessToken,
    this.consentResolver,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String accessToken;
  final ConsentResolver? consentResolver;
  final http.Client _client;

  final _events = StreamController<AiEvent>.broadcast();
  Stream<AiEvent> get events => _events.stream;

  String? _sessionId;
  String? get sessionId => _sessionId;

  bool _closed = false;
  StreamSubscription<String>? _sseSub;

  /// 启动会话并开始 SSE 监听。立即返回；事件通过 [events] 持续推送。
  Future<void> start({
    required String intent,
    required Map<String, Object?> ctx,
  }) async {
    try {
      _sessionId = await _createSession(intent: intent, ctx: ctx);
      _events.add(AiEvent.session(_sessionId!));
      await _subscribe(_sessionId!);
    } on ApiException catch (e) {
      _events.add(AiEvent.error(e.message));
      await close();
    }
  }

  Future<void> abort() async {
    if (_sessionId == null || _closed) return;
    try {
      await _client.post(
        Uri.parse('$baseUrl/ai/sessions/$_sessionId/abort'),
        headers: _authHeaders(),
      );
    } on Object {
      // 忽略 abort 自身的错误
    }
    await close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sseSub?.cancel();
    await _events.close();
  }

  // ── 内部 ─────────────────────────────────────────

  Map<String, String> _authHeaders({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'User-Agent': 'Dustman/${AppConstants.appVersion} (Pro)',
      };

  Future<String> _createSession({
    required String intent,
    required Map<String, Object?> ctx,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/ai/sessions'),
      headers: _authHeaders(),
      body: jsonEncode({'intent': intent, 'ctx': ctx}),
    );
    if (resp.statusCode != 201) {
      throw ApiException(
        statusCode: resp.statusCode,
        message: _extractDetail(resp.body) ?? 'create session failed',
      );
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['session_id'] as String;
  }

  Future<void> _subscribe(String id) async {
    final req = http.Request('GET', Uri.parse('$baseUrl/ai/sessions/$id/stream'));
    req.headers.addAll({
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Authorization': 'Bearer $accessToken',
    });
    final response = await _client.send(req);
    if (response.statusCode != 200) {
      _events.add(AiEvent.error('stream failed: HTTP ${response.statusCode}'));
      await close();
      return;
    }
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final buffer = <String>[];
    _sseSub = lines.listen((line) {
      if (line.isEmpty) {
        _consumeSseEvent(buffer);
        buffer.clear();
      } else {
        buffer.add(line);
      }
    }, onDone: close, onError: (Object e) {
      _events.add(AiEvent.error('stream error: $e'));
      close();
    });
  }

  void _consumeSseEvent(List<String> lines) {
    String? data;
    for (final l in lines) {
      if (l.startsWith(':')) continue; // SSE comment / keepalive
      if (l.startsWith('data:')) {
        data = (data ?? '') + l.substring(5).trimLeft();
      }
      // 忽略 event:/id:/retry: 等
    }
    if (data == null) return;
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    _handleFrame(frame);
  }

  void _handleFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    switch (type) {
      case 'hello':
        // 协议握手；不暴露给 UI
        break;
      case 'usage':
        _events.add(AiEvent.usage(
          tokensIn: frame['tokens_in'] as int? ?? 0,
          tokensOut: frame['tokens_out'] as int? ?? 0,
        ));
      case 'tool_call':
        _executeTool(frame);
      case 'final':
        _events.add(AiEvent.finalText(frame['text'] as String? ?? ''));
        close();
      case 'error':
        _events.add(AiEvent.error(frame['message'] as String? ?? 'unknown error'));
        close();
      default:
        AppLogger.debug('unknown frame: $type', tag: 'AiSession');
    }
  }

  Future<void> _executeTool(Map<String, dynamic> frame) async {
    final callId = frame['call_id'] as String;
    final tool = frame['tool'] as String;
    final args = (frame['args'] as Map?)?.cast<String, Object?>() ?? const {};
    final needsConsent = frame['needs_user_consent'] as bool? ?? false;

    _events.add(AiEvent.toolStart(tool: tool, needsConsent: needsConsent));
    FileClawLogger.writeEvent({
      'session_id': _sessionId,
      'event': 'tool_call',
      'tool': tool,
      'args': args,
      'needs_consent': needsConsent,
    });

    if (needsConsent) {
      final resolver = consentResolver;
      if (resolver == null) {
        FileClawLogger.writeEvent({
          'session_id': _sessionId,
          'event': 'consent_no_handler',
          'tool': tool,
        });
        _events.add(AiEvent.error('no consent handler registered for write tools'));
        await _postResult(callId, ok: false, reason: 'no_consent_handler');
        return;
      }
      final approved = await resolver(tool, args);
      FileClawLogger.writeEvent({
        'session_id': _sessionId,
        'event': approved ? 'consent_approved' : 'consent_declined',
        'tool': tool,
      });
      if (!approved) {
        _events.add(AiEvent.toolDone(tool: tool, ok: false));
        await _postResult(callId, ok: false, reason: 'user_declined');
        return;
      }
    }

    final result = await ToolRegistry.instance.dispatch(tool, args);
    final ok = result['ok'] as bool? ?? false;
    final data = ok ? result['data'] as Map<String, Object?>? : null;
    final reason = !ok ? result['reason'] as String? : null;

    FileClawLogger.writeEvent({
      'session_id': _sessionId,
      'event': 'tool_result',
      'tool': tool,
      'ok': ok,
      if (reason != null) 'reason': reason,
    });
    _events.add(AiEvent.toolDone(tool: tool, ok: ok));
    await _postResult(callId, ok: ok, data: data, reason: reason);
  }

  Future<void> _postResult(
    String callId, {
    required bool ok,
    Map<String, Object?>? data,
    String? reason,
  }) async {
    if (_sessionId == null) return;
    try {
      await _client.post(
        Uri.parse('$baseUrl/ai/sessions/$_sessionId/tool-result'),
        headers: _authHeaders(),
        body: jsonEncode({
          'call_id': callId,
          'ok': ok,
          if (data != null) 'data': data,
          if (reason != null) 'reason': reason,
        }),
      );
    } on Object catch (e) {
      AppLogger.warn('tool-result post failed: $e', tag: 'AiSession');
    }
  }

  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } on Object {
      // ignore
    }
    return null;
  }
}

// ── 事件模型 ─────────────────────────────────────


sealed class AiEvent {
  const AiEvent();

  factory AiEvent.session(String id) = AiSessionEvent;
  factory AiEvent.usage({required int tokensIn, required int tokensOut}) = AiUsageEvent;
  factory AiEvent.toolStart({required String tool, required bool needsConsent}) =
      AiToolStartEvent;
  factory AiEvent.toolDone({required String tool, required bool ok}) = AiToolDoneEvent;
  factory AiEvent.finalText(String text) = AiFinalEvent;
  factory AiEvent.error(String message) = AiErrorEvent;
}

final class AiSessionEvent extends AiEvent {
  const AiSessionEvent(this.sessionId);
  final String sessionId;
}

final class AiUsageEvent extends AiEvent {
  const AiUsageEvent({required this.tokensIn, required this.tokensOut});
  final int tokensIn;
  final int tokensOut;
}

final class AiToolStartEvent extends AiEvent {
  const AiToolStartEvent({required this.tool, required this.needsConsent});
  final String tool;
  final bool needsConsent;
}

final class AiToolDoneEvent extends AiEvent {
  const AiToolDoneEvent({required this.tool, required this.ok});
  final String tool;
  final bool ok;
}

final class AiFinalEvent extends AiEvent {
  const AiFinalEvent(this.text);
  final String text;
}

final class AiErrorEvent extends AiEvent {
  const AiErrorEvent(this.message);
  final String message;
}
