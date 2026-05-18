import '../../../core/utils/logger.dart';
import '../../scanners/startup_item_scanner.dart';
import '../../services/startup_cleaner_service.dart';
import '../../../domain/entities/startup_item.dart';
import 'tool_registry.dart';

/// 把 procmcp 系列工具注册到 [ToolRegistry]。
void registerProcMcpTools() {
  final reg = ToolRegistry.instance;
  reg.register('procmcp.list_startup_items', _listStartupItems);
  reg.register('procmcp.disable_startup_item', _disableStartupItem);
}

// 进程内缓存：list 一次后 disable 凭 id 查回原 item
final Map<String, StartupItem> _itemsById = {};

// ── list_startup_items ─────────────────────────


Future<Map<String, Object?>> _listStartupItems(Map<String, Object?> args) async {
  final scanner = StartupItemScanner();
  final items = await scanner.scan();
  _itemsById
    ..clear()
    ..addEntries(items.map((it) => MapEntry(it.id, it)));

  return {
    'items': [
      for (final it in items)
        {
          'id': it.id,
          'name': it.name,
          'command': it.command,
          'source': it.source.name,
          if (it.targetPath != null) 'target_path': it.targetPath,
          if (it.registryFullKeyPath != null)
            'registry_key': it.registryFullKeyPath,
        },
    ],
    'count': items.length,
  };
}

// ── disable_startup_item（写工具）──────────────


Future<Map<String, Object?>> _disableStartupItem(Map<String, Object?> args) async {
  final id = args['id'];
  if (id is! String || id.isEmpty) {
    throw ArgumentError('missing arg: id');
  }

  // 必须在同一进程内先 list 过；否则 LLM 给了无效 id
  var item = _itemsById[id];
  if (item == null) {
    // 兜底：重新扫一次
    final scanner = StartupItemScanner();
    for (final it in await scanner.scan()) {
      _itemsById[it.id] = it;
    }
    item = _itemsById[id];
  }
  if (item == null) {
    return {'ok': false, 'reason': 'unknown startup id'};
  }

  final report = await StartupCleanerService.remove([item]);
  final ok = report.failures.isEmpty && report.itemsDeleted == 1;
  AppLogger.info(
    ok ? 'disabled startup: ${item.name}' : 'failed disable: ${item.name}',
    tag: 'procmcp',
  );
  if (!ok) {
    return {
      'ok': false,
      'reason': report.failures.isNotEmpty
          ? report.failures.first.reason
          : 'no item deleted',
    };
  }
  _itemsById.remove(id);
  return {'ok': true, 'name': item.name};
}
