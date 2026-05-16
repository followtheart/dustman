import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/platform/installed_programs.dart';
import '../../data/services/residue_cleaner_service.dart';
import '../../domain/entities/installed_program.dart';
import '../../domain/entities/residue_item.dart';
import '../../domain/scanners/residue_scanner.dart';

enum ResidueStatus { idle, scanning, scanned, cleaning, reported, error }

enum ResidueSort {
  defaultOrder('默认'),
  sizeDesc('按大小 ↓'),
  sizeAsc('按大小 ↑');

  const ResidueSort(this.label);
  final String label;
}

class ResidueProvider extends ChangeNotifier {
  ResidueProvider({
    required List<ResidueScanner> scanners,
    InstalledProgramsRepository? installedRepository,
    Future<ResidueCleanReport> Function(List<ResidueItem>)? cleaner,
  })  : _scanners = scanners,
        _installedRepository = installedRepository ?? InstalledProgramsRepository(),
        _cleaner = cleaner ?? ResidueCleanerService.clean;

  final List<ResidueScanner> _scanners;
  final InstalledProgramsRepository _installedRepository;
  final Future<ResidueCleanReport> Function(List<ResidueItem>) _cleaner;

  ResidueStatus _status = ResidueStatus.idle;
  ResidueStatus get status => _status;

  String? _error;
  String? get error => _error;

  final Map<ResidueKind, List<ResidueItem>> _items = {
    for (final k in ResidueKind.values) k: const [],
  };
  Map<ResidueKind, List<ResidueItem>> get itemsByKind => _items;

  ResidueSort _sort = ResidueSort.sizeDesc;
  ResidueSort get sort => _sort;

  void setSort(ResidueSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  List<ResidueItem> itemsSortedBy(ResidueKind kind) {
    final list = _items[kind] ?? const <ResidueItem>[];
    if (_sort == ResidueSort.defaultOrder || list.length < 2) return list;
    final copy = [...list];
    copy.sort(
      (a, b) => _sort == ResidueSort.sizeDesc
          ? b.size.compareTo(a.size)
          : a.size.compareTo(b.size),
    );
    return copy;
  }

  /// 选中状态：id → bool。
  final Map<String, bool> _selected = {};
  bool isSelected(String id) => _selected[id] ?? false;

  ResidueCleanReport? _lastReport;
  ResidueCleanReport? get lastReport => _lastReport;

  int get totalCandidates =>
      _items.values.fold<int>(0, (s, list) => s + list.length);

  int get selectedCount =>
      _selected.entries.where((e) => e.value).length;

  int get selectedBytes {
    var sum = 0;
    for (final list in _items.values) {
      for (final it in list) {
        if (_selected[it.id] == true) sum += it.size;
      }
    }
    return sum;
  }

  int get totalBytes {
    var sum = 0;
    for (final list in _items.values) {
      for (final it in list) {
        sum += it.size;
      }
    }
    return sum;
  }

  int countByConfidence(ResidueConfidence c) {
    var sum = 0;
    for (final list in _items.values) {
      for (final it in list) {
        if (it.confidence == c) sum++;
      }
    }
    return sum;
  }

  Future<void> scan() async {
    if (_status == ResidueStatus.scanning || _status == ResidueStatus.cleaning) {
      return;
    }
    _status = ResidueStatus.scanning;
    _error = null;
    _lastReport = null;
    for (final k in ResidueKind.values) {
      _items[k] = const [];
    }
    _selected.clear();
    notifyListeners();

    try {
      final index = await _installedRepository.build();
      // 并行 3 个 scanner
      final futures = _scanners.map((s) => _runOne(s, index)).toList();
      await Future.wait(futures);
      _status = ResidueStatus.scanned;
    } on Object catch (e, st) {
      AppLogger.error('residue scan failed', error: e, stack: st,
          tag: 'ResidueProvider');
      _status = ResidueStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> _runOne(
    ResidueScanner scanner,
    InstalledProgramIndex index,
  ) async {
    final list = <ResidueItem>[];
    try {
      await for (final item in scanner.scan(index)) {
        list.add(item);
        // 默认勾选 high
        _selected[item.id] = item.confidence == ResidueConfidence.high;
      }
    } on Object catch (e, st) {
      AppLogger.warn(
        '${scanner.kind} scan errored: $e\n$st',
        tag: 'ResidueProvider',
      );
    }
    _items[scanner.kind] = list;
    notifyListeners();
  }

  void toggleItem(String id, bool? value) {
    _selected[id] = value ?? false;
    notifyListeners();
  }

  void toggleAll(ResidueKind kind, bool value) {
    final list = _items[kind] ?? const <ResidueItem>[];
    for (final it in list) {
      _selected[it.id] = value;
    }
    notifyListeners();
  }

  /// 移出清理列表（不再展示）。
  void removeItem(String id) {
    _selected.remove(id);
    for (final kind in ResidueKind.values) {
      _items[kind] = _items[kind]!.where((it) => it.id != id).toList();
    }
    notifyListeners();
  }

  Future<void> cleanSelected() async {
    if (_status == ResidueStatus.cleaning) return;
    final toClean = <ResidueItem>[];
    for (final list in _items.values) {
      for (final it in list) {
        if (_selected[it.id] == true) toClean.add(it);
      }
    }
    if (toClean.isEmpty) return;

    _status = ResidueStatus.cleaning;
    notifyListeners();

    try {
      final report = await _cleaner(toClean);
      _lastReport = report;
      // 清掉已成功删除的 item（按 path 匹配，失败项保留以便重试）
      final failedIds = report.failures.map((f) => f.path).toSet();
      for (final kind in ResidueKind.values) {
        _items[kind] = _items[kind]!
            .where(
                (it) => !_selected[it.id]! || failedIds.contains(it.path))
            .toList();
      }
      // 重置 selected 为新 items 的状态
      _selected.removeWhere((id, _) {
        for (final list in _items.values) {
          if (list.any((it) => it.id == id)) return false;
        }
        return true;
      });
      _status = ResidueStatus.reported;
    } on Object catch (e, st) {
      AppLogger.error('residue clean failed', error: e, stack: st,
          tag: 'ResidueProvider');
      _status = ResidueStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }
}
