import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/scanners/startup_item_scanner.dart';
import '../../data/services/startup_cleaner_service.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/entities/startup_item.dart';

enum StartupStatus { idle, scanning, scanned, removing, reported, error }

class StartupProvider extends ChangeNotifier {
  StartupProvider({
    StartupItemScanner? scanner,
    Future<CleanReport> Function(List<StartupItem>)? remover,
  })  : _scanner = scanner ?? StartupItemScanner(),
        _remover = remover ?? StartupCleanerService.remove;

  final StartupItemScanner _scanner;
  final Future<CleanReport> Function(List<StartupItem>) _remover;

  StartupStatus _status = StartupStatus.idle;
  StartupStatus get status => _status;

  String? _error;
  String? get error => _error;

  final List<StartupItem> _items = [];
  List<StartupItem> get items => List.unmodifiable(_items);

  /// id → 是否勾选。
  final Map<String, bool> _selected = {};
  bool isSelected(String id) => _selected[id] ?? false;

  CleanReport? _lastReport;
  CleanReport? get lastReport => _lastReport;

  int get totalCount => _items.length;
  int get selectedCount =>
      _selected.entries.where((e) => e.value).length;
  int get registryCount =>
      _items.where((it) => it.source.isRegistry).length;
  int get folderCount => _items.where((it) => !it.source.isRegistry).length;
  bool get hasElevationRequiredSelection {
    return _items.any(
      (it) => _selected[it.id] == true && it.source.requiresElevation,
    );
  }

  /// 按来源分组（保留 enum 顺序）。
  Map<StartupSource, List<StartupItem>> groupBySource() {
    final out = <StartupSource, List<StartupItem>>{
      for (final s in StartupSource.values) s: <StartupItem>[],
    };
    for (final it in _items) {
      out[it.source]!.add(it);
    }
    return out;
  }

  Future<void> scan() async {
    if (_status == StartupStatus.scanning ||
        _status == StartupStatus.removing) {
      return;
    }
    _status = StartupStatus.scanning;
    _items.clear();
    _selected.clear();
    _lastReport = null;
    _error = null;
    notifyListeners();

    try {
      final list = await _scanner.scan();
      _items.addAll(list);
      _status = StartupStatus.scanned;
    } on Object catch (e, st) {
      AppLogger.error('startup scan failed', error: e, stack: st,
          tag: 'StartupProvider');
      _status = StartupStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  void toggle(String id, bool? v) {
    _selected[id] = v ?? false;
    notifyListeners();
  }

  void toggleSource(StartupSource source, bool v) {
    for (final it in _items) {
      if (it.source == source) _selected[it.id] = v;
    }
    notifyListeners();
  }

  Future<void> removeSelected() async {
    if (_status == StartupStatus.removing) return;
    final toRemove =
        _items.where((it) => _selected[it.id] == true).toList();
    if (toRemove.isEmpty) return;

    _status = StartupStatus.removing;
    notifyListeners();
    try {
      final report = await _remover(toRemove);
      _lastReport = report;
      final failed = report.failures.map((f) => f.path).toSet();
      _items.removeWhere((it) {
        if (_selected[it.id] != true) return false;
        // 注册表项的"路径"是 full\value，快捷方式的是 .lnk path
        if (it.source.isRegistry) {
          final fullPath =
              '${it.registryFullKeyPath}\\${it.registryValueName}';
          return !failed.contains(fullPath);
        }
        return !failed.contains(it.shortcutPath);
      });
      _selected.removeWhere((id, _) => !_items.any((it) => it.id == id));
      _status = StartupStatus.reported;
    } on Object catch (e, st) {
      AppLogger.error('startup remove failed', error: e, stack: st,
          tag: 'StartupProvider');
      _status = StartupStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }
}
