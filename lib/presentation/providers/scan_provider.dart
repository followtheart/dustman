import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/junk_category.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/scanners/junk_scanner.dart';

enum CategoryStatus { idle, scanning, scanned, cleaning, error }

class CategoryState {
  CategoryState({
    required this.type,
    this.status = CategoryStatus.idle,
    this.items = const [],
    this.selected = true,
    this.error,
  });

  final JunkCategoryType type;
  CategoryStatus status;
  List<JunkItem> items;
  bool selected;
  String? error;

  int get totalBytes => items.fold<int>(0, (s, it) => s + it.size);

  CategoryState copyWith({
    CategoryStatus? status,
    List<JunkItem>? items,
    bool? selected,
    String? error,
  }) =>
      CategoryState(
        type: type,
        status: status ?? this.status,
        items: items ?? this.items,
        selected: selected ?? this.selected,
        error: error,
      );
}

class ScanProvider extends ChangeNotifier {
  ScanProvider(this._scanners) {
    for (final s in _scanners) {
      _states[s.type] = CategoryState(type: s.type);
    }
  }

  final List<JunkScanner> _scanners;
  final Map<JunkCategoryType, CategoryState> _states = {};

  Map<JunkCategoryType, CategoryState> get states => _states;
  Iterable<JunkScanner> get scanners => _scanners;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  CleanReport? _lastReport;
  CleanReport? get lastReport => _lastReport;

  int get totalReclaimableBytes => _states.values
      .where((s) => s.selected && s.status == CategoryStatus.scanned)
      .fold<int>(0, (sum, s) => sum + s.totalBytes);

  bool get hasAnyScanned =>
      _states.values.any((s) => s.status == CategoryStatus.scanned);

  void toggleSelection(JunkCategoryType type, bool? value) {
    final s = _states[type];
    if (s == null) return;
    s.selected = value ?? false;
    notifyListeners();
  }

  Future<void> scanAll() async {
    if (_isBusy) return;
    _isBusy = true;
    _lastReport = null;
    notifyListeners();
    await Future.wait(_scanners.map(_scanOne));
    _isBusy = false;
    notifyListeners();
  }

  Future<void> _scanOne(JunkScanner scanner) async {
    final state = _states[scanner.type]!;
    state
      ..status = CategoryStatus.scanning
      ..items = const []
      ..error = null;
    notifyListeners();
    final collected = <JunkItem>[];
    try {
      await for (final item in scanner.scan()) {
        collected.add(item);
      }
      state
        ..items = collected
        ..status = CategoryStatus.scanned;
    } on Object catch (e, st) {
      AppLogger.error('scan ${scanner.type} failed',
          error: e, stack: st, tag: 'ScanProvider');
      state
        ..status = CategoryStatus.error
        ..error = e.toString();
    }
    notifyListeners();
  }

  Future<void> cleanSelected() async {
    if (_isBusy) return;
    _isBusy = true;
    notifyListeners();

    var report = CleanReport.empty();
    for (final scanner in _scanners) {
      final state = _states[scanner.type]!;
      if (!state.selected || state.status != CategoryStatus.scanned) continue;
      if (state.items.isEmpty) continue;
      state.status = CategoryStatus.cleaning;
      notifyListeners();
      try {
        final r = await scanner.clean(state.items);
        report = report.merge(r);
        state
          ..items = const []
          ..status = CategoryStatus.scanned;
      } on Object catch (e, st) {
        AppLogger.error('clean ${scanner.type} failed',
            error: e, stack: st, tag: 'ScanProvider');
        state
          ..status = CategoryStatus.error
          ..error = e.toString();
      }
      notifyListeners();
    }

    _lastReport = report;
    _isBusy = false;
    notifyListeners();
  }
}
