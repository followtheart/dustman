import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/safety_guard.dart';
import '../../data/scanners/large_file_scanner.dart';
import '../../domain/entities/junk_item.dart';
import '../../domain/entities/large_file_item.dart';

enum LargeFileStatus { idle, scanning, scanned, cleaning, reported, error }

enum LargeFileSort {
  sizeDesc('按大小 ↓'),
  sizeAsc('按大小 ↑'),
  mtimeDesc('按修改时间 ↓'),
  mtimeAsc('按修改时间 ↑');

  const LargeFileSort(this.label);
  final String label;
}

/// 大文件查找的状态机。
///
/// 文件清理走系统回收站（`SHFileOperationW + FOF_ALLOWUNDO`）；
/// 非 Windows 平台直接 `File.delete()`，便于单元测试。
class LargeFileProvider extends ChangeNotifier {
  LargeFileProvider({
    LargeFileScanner? scanner,
    Future<CleanReport> Function(List<LargeFileItem>)? cleaner,
  })  : _scanner = scanner,
        _cleaner = cleaner ?? _defaultClean;

  final LargeFileScanner? _scanner;
  final Future<CleanReport> Function(List<LargeFileItem>) _cleaner;

  LargeFileStatus _status = LargeFileStatus.idle;
  LargeFileStatus get status => _status;

  String? _error;
  String? get error => _error;

  /// 当前扫描的根目录（用于状态卡片展示）。
  String? _rootPath;
  String? get rootPath => _rootPath;

  /// 阈值（字节）。
  int _minBytes = 100 * 1024 * 1024;
  int get minBytes => _minBytes;

  /// 后缀过滤（含点、小写）。
  Set<String> _extensions = <String>{};
  Set<String> get extensions => _extensions;

  final List<LargeFileItem> _items = [];
  List<LargeFileItem> get items => List.unmodifiable(_sortedItems());

  final Map<String, bool> _selected = {};
  bool isSelected(String path) => _selected[path] ?? false;

  LargeFileSort _sort = LargeFileSort.sizeDesc;
  LargeFileSort get sort => _sort;

  CleanReport? _lastReport;
  CleanReport? get lastReport => _lastReport;

  int get totalCount => _items.length;
  int get totalBytes => _items.fold<int>(0, (s, it) => s + it.size);
  int get selectedCount =>
      _selected.entries.where((e) => e.value).length;
  int get selectedBytes {
    var sum = 0;
    for (final it in _items) {
      if (_selected[it.path] == true) sum += it.size;
    }
    return sum;
  }

  StreamSubscription<LargeFileItem>? _sub;

  void setMinBytes(int value) {
    if (_minBytes == value) return;
    _minBytes = value;
    notifyListeners();
  }

  /// [raw] 是用户输入的逗号 / 空格分隔字符串，例如 `iso, .mp4 zip`。
  void setExtensionsFromText(String raw) {
    final set = <String>{};
    for (final tok in raw.split(RegExp(r'[,\s;]+'))) {
      final t = tok.trim().toLowerCase();
      if (t.isEmpty) continue;
      set.add(t.startsWith('.') ? t : '.$t');
    }
    if (_extensions.length == set.length && _extensions.containsAll(set)) {
      return;
    }
    _extensions = set;
    notifyListeners();
  }

  void setSort(LargeFileSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  Future<void> scan(String root) async {
    if (_status == LargeFileStatus.scanning ||
        _status == LargeFileStatus.cleaning) {
      return;
    }
    await _sub?.cancel();
    _items.clear();
    _selected.clear();
    _lastReport = null;
    _error = null;
    _rootPath = root;
    _status = LargeFileStatus.scanning;
    notifyListeners();

    final scanner = _scanner ??
        LargeFileScanner(
          minBytes: _minBytes,
          extensions: _extensions,
        );

    final completer = Completer<void>();
    _sub = scanner.scan(root).listen(
      (item) {
        _items.add(item);
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        AppLogger.error('large file scan failed', error: e, stack: st,
            tag: 'LargeFileProvider');
      },
      onDone: () {
        _status = LargeFileStatus.scanned;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );
    return completer.future;
  }

  /// 用户主动中止扫描（保留已收集的结果）。
  Future<void> cancelScan() async {
    if (_status != LargeFileStatus.scanning) return;
    await _sub?.cancel();
    _sub = null;
    _status = LargeFileStatus.scanned;
    notifyListeners();
  }

  void toggle(String path, bool? value) {
    _selected[path] = value ?? false;
    notifyListeners();
  }

  void toggleAll(bool value) {
    for (final it in _items) {
      _selected[it.path] = value;
    }
    notifyListeners();
  }

  /// 仅勾选可见列表里前 N 项。
  void selectTopN(int n) {
    final list = _sortedItems();
    final keep = list.take(n).map((e) => e.path).toSet();
    _selected.clear();
    for (final path in keep) {
      _selected[path] = true;
    }
    notifyListeners();
  }

  void removeItem(String path) {
    _selected.remove(path);
    _items.removeWhere((it) => it.path == path);
    notifyListeners();
  }

  Future<void> cleanSelected() async {
    if (_status == LargeFileStatus.cleaning) return;
    final toDel = _items.where((it) => _selected[it.path] == true).toList();
    if (toDel.isEmpty) return;

    _status = LargeFileStatus.cleaning;
    notifyListeners();

    try {
      final report = await _cleaner(toDel);
      _lastReport = report;
      final failed = report.failures.map((f) => f.path).toSet();
      _items.removeWhere(
        (it) => _selected[it.path] == true && !failed.contains(it.path),
      );
      _selected.removeWhere((id, _) => !_items.any((it) => it.path == id));
      _status = LargeFileStatus.reported;
    } on Object catch (e, st) {
      AppLogger.error('large file clean failed', error: e, stack: st,
          tag: 'LargeFileProvider');
      _status = LargeFileStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  List<LargeFileItem> _sortedItems() {
    final copy = [..._items];
    copy.sort((a, b) {
      switch (_sort) {
        case LargeFileSort.sizeDesc:
          return b.size.compareTo(a.size);
        case LargeFileSort.sizeAsc:
          return a.size.compareTo(b.size);
        case LargeFileSort.mtimeDesc:
          return b.lastModified.compareTo(a.lastModified);
        case LargeFileSort.mtimeAsc:
          return a.lastModified.compareTo(b.lastModified);
      }
    });
    return copy;
  }

  /// 状态卡片：人类可读的当前过滤条件描述。
  String describeFilter() {
    final parts = <String>[
      '≥ ${FileSizeFormatter.format(_minBytes)}',
    ];
    if (_extensions.isNotEmpty) {
      parts.add('后缀 ${_extensions.join(", ")}');
    }
    return parts.join(' · ');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 默认的清理实现：Windows → 移入回收站；其它平台 → 直接删除。
  static Future<CleanReport> _defaultClean(List<LargeFileItem> items) async {
    var freed = 0;
    var deleted = 0;
    final failures = <CleanFailure>[];

    for (final item in items) {
      if (!SafetyGuard.isSafeToDelete(item.path)) {
        failures.add(CleanFailure(item.path, '受保护路径，已跳过'));
        continue;
      }
      try {
        if (Platform.isWindows) {
          final ok = _shellMoveToRecycleBin(item.path);
          if (!ok) {
            failures.add(CleanFailure(item.path, '移入回收站失败'));
            continue;
          }
        } else {
          final f = File(item.path);
          if (await f.exists()) await f.delete();
        }
        freed += item.size;
        deleted++;
      } on FileSystemException catch (e) {
        failures.add(CleanFailure(item.path, e.osError?.message ?? e.message));
      } on Object catch (e) {
        failures.add(CleanFailure(item.path, e.toString()));
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
        AppLogger.warn(
          'SHFileOperation($path) rc=$rc',
          tag: 'LargeFileProvider',
        );
        return false;
      }
      return op.ref.fAnyOperationsAborted == 0;
    } finally {
      calloc.free(ptr);
      calloc.free(op);
    }
  }
}
