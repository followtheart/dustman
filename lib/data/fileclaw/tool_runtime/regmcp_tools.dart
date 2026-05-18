import 'dart:io';

import '../../platform/registry_reader.dart';
import 'tool_registry.dart';

/// 把 regmcp 系列只读工具注册到 [ToolRegistry]。
///
/// 应用启动时（仅 Pro 分支）调用 [registerRegMcpTools] 一次。
void registerRegMcpTools() {
  final reg = ToolRegistry.instance;
  reg.register('regmcp.read_key', _readKey);
  reg.register('regmcp.read_values', _readValues);
}

// ── 实现 ─────────────────────────────────────────


Future<Map<String, Object?>> _readKey(Map<String, Object?> args) async {
  final (root, sub, view) = _parseKeyArg(args);
  if (!Platform.isWindows) {
    return {'values': [], 'subkeys': [], 'note': 'not Windows'};
  }
  final key = RegKey.open(root, sub, view: view);
  if (key == null) {
    return {'values': [], 'subkeys': [], 'note': 'key not found or denied'};
  }
  try {
    final values = _formatValues(key);
    final subkeys = key
        .enumSubKeys()
        .take(64) // 上限避免噪音
        .map((s) => s.name)
        .toList(growable: false);
    return {
      'key': key.fullPath,
      'values': values,
      'subkeys': subkeys,
    };
  } finally {
    key.close();
  }
}

Future<Map<String, Object?>> _readValues(Map<String, Object?> args) async {
  final (root, sub, view) = _parseKeyArg(args);
  if (!Platform.isWindows) {
    return {'values': []};
  }
  final key = RegKey.open(root, sub, view: view);
  if (key == null) {
    return {'values': [], 'note': 'key not found or denied'};
  }
  try {
    return {
      'key': key.fullPath,
      'values': _formatValues(key),
    };
  } finally {
    key.close();
  }
}

// ── 内部 ─────────────────────────────────────────


List<Map<String, Object?>> _formatValues(RegKey key) {
  final out = <Map<String, Object?>>[];
  for (final v in key.enumValues().take(64)) {
    final entry = <String, Object?>{
      'name': v.name,
      'type': _typeName(v.type),
    };
    final data = _readDataIfTextual(key, v.name, v.type);
    if (data != null) entry['data'] = data;
    out.add(entry);
  }
  return out;
}

Object? _readDataIfTextual(RegKey key, String name, int type) {
  // REG_SZ=1, REG_EXPAND_SZ=2, REG_DWORD=4
  if (type == 1 || type == 2) return key.readString(name);
  if (type == 4) return key.readDword(name);
  return null; // binary / multi_sz 等暂不返回原始值
}

String _typeName(int t) => switch (t) {
      1 => 'REG_SZ',
      2 => 'REG_EXPAND_SZ',
      3 => 'REG_BINARY',
      4 => 'REG_DWORD',
      7 => 'REG_MULTI_SZ',
      11 => 'REG_QWORD',
      _ => 'REG_$t',
    };

/// 把云侧传来的 'HKCU\\Software\\Foo' 解析为 (root, subpath, view)。
///
/// view 默认 v64。后续可让 LLM 显式传 view 参数。
(RegRoot, String, RegView) _parseKeyArg(Map<String, Object?> args) {
  final raw = (args['key'] as String?)?.trim() ?? '';
  if (raw.isEmpty) {
    throw ArgumentError('missing arg: key');
  }
  // 统一分隔符
  final normalized = raw.replaceAll('/', r'\');
  final parts = normalized.split(r'\');
  final head = parts.first.toUpperCase();
  final tail = parts.skip(1).join(r'\');
  final root = switch (head) {
    'HKEY_CURRENT_USER' || 'HKCU' => RegRoot.hkcu,
    'HKEY_LOCAL_MACHINE' || 'HKLM' => RegRoot.hklm,
    _ => throw ArgumentError('unsupported root: $head'),
  };
  return (root, tail, RegView.v64);
}
