import '../../../core/utils/logger.dart';

typedef ToolFn = Future<Map<String, Object?>> Function(Map<String, Object?> args);

/// 工具白名单 + 分发器。
///
/// 与云侧 [`app/ai/tools.py`](../../../../../dustman-cloud/app/ai/tools.py) 一一对应：
/// 云侧只下发名字与 args；端侧用 [register] 提前注册的 [ToolFn] 实际执行。
/// 任何不在白名单的工具名调用都会直接返回失败 —— 即便云侧穿越白名单（不会发生）
/// 也无法触发本机动作。
class ToolRegistry {
  ToolRegistry._();

  static final ToolRegistry _instance = ToolRegistry._();
  static ToolRegistry get instance => _instance;

  final Map<String, ToolFn> _byName = {};

  void register(String name, ToolFn fn) {
    if (_byName.containsKey(name)) {
      AppLogger.warn('tool $name re-registered', tag: 'ToolRegistry');
    }
    _byName[name] = fn;
  }

  bool has(String name) => _byName.containsKey(name);

  /// 执行某个工具。返回值结构：
  ///   { ok: bool, data?: Map, reason?: String }
  ///
  /// 异常会被吞掉转成 ok=false，避免崩端侧 AI 流程。
  Future<Map<String, Object?>> dispatch(String name, Map<String, Object?> args) async {
    final fn = _byName[name];
    if (fn == null) {
      return {'ok': false, 'reason': 'tool not registered: $name'};
    }
    try {
      final data = await fn(args);
      return {'ok': true, 'data': data};
    } on Object catch (e) {
      AppLogger.warn('tool $name failed: $e', tag: 'ToolRegistry');
      return {'ok': false, 'reason': e.toString()};
    }
  }
}
