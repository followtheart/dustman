import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger.dart';
import '../../core/utils/safety_guard.dart';
import '../../data/scanners/duplicate_file_scanner.dart';
import '../../domain/entities/duplicate_group.dart';
import '../../domain/entities/junk_item.dart';

enum DuplicateStatus { idle, scanning, scanned, cleaning, reported, error }

class DuplicateProvider extends ChangeNotifier {
  DuplicateProvider({
    DuplicateFileScanner? scanner,
    Future<CleanReport> Function(List<String>)? cleaner,
  })  : _scanner = scanner,
        _cleaner = cleaner ?? _defaultClean;

  final DuplicateFileScanner? _scanner;
  final Future<CleanReport> Function(List<String>) _cleaner;

  DuplicateStatus _status = DuplicateStatus.idle;
  DuplicateStatus get status => _status;

  String? _error;
  String? get error => _error;

  /// 当前扫描的根目录列表（多根用 `;` 或换行分隔输入）。
  List<String> _roots = const [];
  List<String> get roots => _roots;

  int _minBytes = 1 * 1024 * 1024;
  int get minBytes => _minBytes;

  final List<DuplicateGroup> _groups = [];
  List<DuplicateGroup> get groups => List.unmodifiable(_groups);

  /// 文件路径 → 是否勾选。
  final Map<String, bool> _selected = {};
  bool isSelected(String path) => _selected[path] ?? false;

  DuplicateScanProgress? _progress;
  DuplicateScanProgress? get progress => _progress;

  CleanReport? _lastReport;
  CleanReport? get lastReport => _lastReport;

  StreamSubscription<DuplicateGroup>? _sub;

  int get totalGroups => _groups.length;
  int get totalDuplicateFiles =>
      _groups.fold<int>(0, (s, g) => s + g.count);
  int get reclaimableBytes =>
      _groups.fold<int>(0, (s, g) => s + g.reclaimableBytes);

  int get selectedCount =>
      _selected.entries.where((e) => e.value).length;
  int get selectedBytes {
    var sum = 0;
    for (final g in _groups) {
      for (final path in g.paths) {
        if (_selected[path] == true) sum += g.size;
      }
    }
    return sum;
  }

  void setMinBytes(int value) {
    if (_minBytes == value) return;
    _minBytes = value;
    notifyListeners();
  }

  Future<void> scan(List<String> roots) async {
    if (_status == DuplicateStatus.scanning ||
        _status == DuplicateStatus.cleaning) {
      return;
    }
    await _sub?.cancel();
    _groups.clear();
    _selected.clear();
    _lastReport = null;
    _error = null;
    _progress = null;
    _roots = roots;
    _status = DuplicateStatus.scanning;
    notifyListeners();

    final scanner = _scanner ?? DuplicateFileScanner(minBytes: _minBytes);
    final completer = Completer<void>();
    _sub = scanner.scan(
      roots,
      onProgress: (p) {
        _progress = p;
        notifyListeners();
      },
    ).listen(
      (group) {
        _groups.add(group);
        // 默认保留首项 → 其余勾选
        for (var i = 0; i < group.paths.length; i++) {
          _selected[group.paths[i]] = i > 0;
        }
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        AppLogger.error('dup scan failed', error: e, stack: st,
            tag: 'DupProvider');
      },
      onDone: () {
        _status = DuplicateStatus.scanned;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );
    return completer.future;
  }

  Future<void> cancelScan() async {
    if (_status != DuplicateStatus.scanning) return;
    await _sub?.cancel();
    _sub = null;
    _status = DuplicateStatus.scanned;
    notifyListeners();
  }

  void toggle(String path, bool? v) {
    _selected[path] = v ?? false;
    notifyListeners();
  }

  /// 每组保留首项，勾选其余副本。
  void selectKeepFirstInEachGroup() {
    _selected.clear();
    for (final g in _groups) {
      for (var i = 0; i < g.paths.length; i++) {
        _selected[g.paths[i]] = i > 0;
      }
    }
    notifyListeners();
  }

  /// 每组保留最旧的（最早修改时间）一份。
  Future<void> selectKeepOldestInEachGroup() async {
    _selected.clear();
    for (final g in _groups) {
      final stats = <String, DateTime>{};
      for (final p in g.paths) {
        try {
          stats[p] = await File(p).stat().then((s) => s.modified);
        } on FileSystemException {
          stats[p] = DateTime.now();
        }
      }
      String? keep;
      DateTime? keepTime;
      for (final entry in stats.entries) {
        if (keepTime == null || entry.value.isBefore(keepTime)) {
          keep = entry.key;
          keepTime = entry.value;
        }
      }
      for (final p in g.paths) {
        _selected[p] = p != keep;
      }
    }
    notifyListeners();
  }

  void deselectAll() {
    for (final g in _groups) {
      for (final p in g.paths) {
        _selected[p] = false;
      }
    }
    notifyListeners();
  }

  /// 强制安全检查：每组至少保留一份未勾选。
  bool hasUnsafeSelection() {
    for (final g in _groups) {
      final allSelected =
          g.paths.every((p) => _selected[p] == true);
      if (allSelected) return true;
    }
    return false;
  }

  Future<void> cleanSelected() async {
    if (_status == DuplicateStatus.cleaning) return;
    if (hasUnsafeSelection()) {
      _error = '存在某组所有副本都被勾选 —— 至少需保留一份';
      _status = DuplicateStatus.error;
      notifyListeners();
      return;
    }
    final toDel = <String>[];
    for (final g in _groups) {
      for (final p in g.paths) {
        if (_selected[p] == true) toDel.add(p);
      }
    }
    if (toDel.isEmpty) return;
    _status = DuplicateStatus.cleaning;
    notifyListeners();

    try {
      final report = await _cleaner(toDel);
      _lastReport = report;
      final failed = report.failures.map((f) => f.path).toSet();

      // 从 group 中清掉已删除路径，并 prune 空组
      for (final g in [..._groups]) {
        g.paths.removeWhere(
          (p) => _selected[p] == true && !failed.contains(p),
        );
        if (g.paths.length < 2) _groups.remove(g);
      }
      _selected.removeWhere((path, _) {
        return !_groups.any((g) => g.paths.contains(path));
      });
      _status = DuplicateStatus.reported;
    } on Object catch (e, st) {
      AppLogger.error('dup clean failed', error: e, stack: st,
          tag: 'DupProvider');
      _status = DuplicateStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static Future<CleanReport> _defaultClean(List<String> paths) async {
    var freed = 0;
    var deleted = 0;
    final failures = <CleanFailure>[];
    for (final path in paths) {
      if (!SafetyGuard.isSafeToDelete(path)) {
        failures.add(CleanFailure(path, '受保护路径，已跳过'));
        continue;
      }
      try {
        final f = File(path);
        int size = 0;
        try {
          size = (await f.stat()).size;
        } on FileSystemException {
          // 不影响删除流程
        }
        if (Platform.isWindows) {
          final ok = _shellMoveToRecycleBin(path);
          if (!ok) {
            failures.add(CleanFailure(path, '移入回收站失败'));
            continue;
          }
        } else {
          if (await f.exists()) await f.delete();
        }
        freed += size;
        deleted++;
      } on FileSystemException catch (e) {
        failures.add(CleanFailure(path, e.osError?.message ?? e.message));
      } on Object catch (e) {
        failures.add(CleanFailure(path, e.toString()));
      }
    }
    return CleanReport(
      bytesFreed: freed,
      itemsDeleted: deleted,
      failures: failures,
    );
  }

  static bool _shellMoveToRecycleBin(String path) {
    final units = path.codeUnits;
    final ptr = calloc<Uint16>(units.length + 2);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    ptr[units.length + 1] = 0;
    final op = calloc<SHFILEOPSTRUCT>()
      ..ref.wFunc = FO_DELETE
      ..ref.pFrom = ptr.cast<Utf16>()
      ..ref.fFlags =
          FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
    try {
      final rc = SHFileOperation(op);
      if (rc != 0) {
        AppLogger.warn('SHFileOperation($path) rc=$rc', tag: 'DupProvider');
        return false;
      }
      return op.ref.fAnyOperationsAborted == 0;
    } finally {
      calloc.free(ptr);
      calloc.free(op);
    }
  }
}
