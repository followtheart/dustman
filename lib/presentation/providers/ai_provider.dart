import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/fileclaw/ai_session_client.dart';

/// 管理当前活跃的 AI 分析会话。
///
/// UI 通过 [start] 触发一次新会话；通过 listen 订阅 [progress] 与 [finalText] / [error]
/// 来渲染进度与最终结果。同一时刻只允许一个活跃会话（保持简单）。
class AiProvider extends ChangeNotifier {
  AiProvider({required this.baseUrl, required this.accessTokenProvider});

  final String baseUrl;
  final String Function() accessTokenProvider;

  AiSessionClient? _active;
  StreamSubscription<AiEvent>? _sub;

  bool _running = false;
  bool _writeRequested = false;
  String _intent = '';
  final List<String> _log = [];
  int _tokensIn = 0;
  int _tokensOut = 0;
  String? _finalText;
  String? _error;

  bool get isRunning => _running;
  String get intent => _intent;
  List<String> get log => List.unmodifiable(_log);
  int get tokensIn => _tokensIn;
  int get tokensOut => _tokensOut;
  String? get finalText => _finalText;
  String? get error => _error;
  bool get writeRequested => _writeRequested;

  /// 启动一次新会话。如果当前有活跃会话，先 abort 再启动。
  Future<void> start({
    required String intent,
    required Map<String, Object?> ctx,
  }) async {
    await stop();
    _running = true;
    _writeRequested = false;
    _intent = intent;
    _log
      ..clear()
      ..add('开始分析…');
    _tokensIn = 0;
    _tokensOut = 0;
    _finalText = null;
    _error = null;
    notifyListeners();

    final client = AiSessionClient(
      baseUrl: baseUrl,
      accessToken: accessTokenProvider(),
    );
    _active = client;
    _sub = client.events.listen(_handle);
    try {
      await client.start(intent: intent, ctx: ctx);
    } on Object catch (e) {
      AppLogger.warn('AiProvider start failed: $e', tag: 'AiProvider');
      _error = e.toString();
      _running = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final active = _active;
    final sub = _sub;
    _active = null;
    _sub = null;
    if (active != null) {
      await active.abort();
    }
    await sub?.cancel();
    if (_running) {
      _running = false;
      notifyListeners();
    }
  }

  void _handle(AiEvent event) {
    switch (event) {
      case AiSessionEvent():
        _log.add('会话已建立');
      case AiUsageEvent(tokensIn: final ti, tokensOut: final to):
        _tokensIn = ti;
        _tokensOut = to;
      case AiToolStartEvent(tool: final tool, needsConsent: final consent):
        _writeRequested = consent;
        _log.add(consent ? '🔒 等待确认：$tool' : '🔧 调用工具：$tool');
      case AiToolDoneEvent(tool: final tool, ok: final ok):
        _log.add(ok ? '✓ $tool 完成' : '✗ $tool 失败');
      case AiFinalEvent(text: final text):
        _finalText = text;
        _running = false;
        _log.add('✅ 分析完成');
      case AiErrorEvent(message: final msg):
        _error = msg;
        _running = false;
        _log.add('❌ $msg');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
