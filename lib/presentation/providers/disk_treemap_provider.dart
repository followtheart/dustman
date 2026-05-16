import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/scanners/disk_treemap_scanner.dart';
import '../../domain/entities/disk_node.dart';

enum DiskTreemapStatus { idle, scanning, scanned, error }

class DiskTreemapProvider extends ChangeNotifier {
  DiskTreemapProvider({DiskTreemapScanner? scanner})
      : _scanner = scanner ?? DiskTreemapScanner();

  DiskTreemapScanner _scanner;

  DiskTreemapStatus _status = DiskTreemapStatus.idle;
  DiskTreemapStatus get status => _status;

  String? _error;
  String? get error => _error;

  String? _rootPath;
  String? get rootPath => _rootPath;

  DiskNode? _tree;
  DiskNode? get tree => _tree;

  /// 当前下钻路径：从根到当前节点的栈（含根）。
  final List<DiskNode> _drillStack = [];
  List<DiskNode> get breadcrumb => List.unmodifiable(_drillStack);
  DiskNode? get current => _drillStack.isEmpty ? null : _drillStack.last;

  int _entriesScanned = 0;
  int get entriesScanned => _entriesScanned;
  int _bytesAccumulated = 0;
  int get bytesAccumulated => _bytesAccumulated;
  String _currentScanPath = '';
  String get currentScanPath => _currentScanPath;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  Future<void> scan(String root, {int maxDepth = 6}) async {
    if (_status == DiskTreemapStatus.scanning) return;
    _scanner = DiskTreemapScanner(maxDepth: maxDepth);
    _status = DiskTreemapStatus.scanning;
    _rootPath = root;
    _tree = null;
    _drillStack.clear();
    _error = null;
    _entriesScanned = 0;
    _bytesAccumulated = 0;
    _currentScanPath = root;
    _elapsed = Duration.zero;
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      final node = await _scanner.scan(root, onProgress: (p) {
        _entriesScanned = p.entriesScanned;
        _bytesAccumulated = p.bytesAccumulated;
        _currentScanPath = p.currentPath;
        notifyListeners();
      });
      sw.stop();
      _elapsed = sw.elapsed;
      if (node == null) {
        _status = DiskTreemapStatus.error;
        _error = '目录不存在或扫描被取消';
      } else {
        _tree = node;
        _drillStack
          ..clear()
          ..add(node);
        _status = DiskTreemapStatus.scanned;
      }
    } on Object catch (e, st) {
      AppLogger.error('disk treemap scan failed',
          error: e, stack: st, tag: 'DiskTreemapProvider');
      _status = DiskTreemapStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  void cancelScan() {
    if (_status != DiskTreemapStatus.scanning) return;
    _scanner.cancel();
  }

  void drillInto(DiskNode node) {
    if (!node.isDirectory) return;
    if (node.children == null || node.children!.isEmpty) return;
    _drillStack.add(node);
    notifyListeners();
  }

  void drillUp() {
    if (_drillStack.length <= 1) return;
    _drillStack.removeLast();
    notifyListeners();
  }

  void reset() {
    if (_tree == null) return;
    _drillStack
      ..clear()
      ..add(_tree!);
    notifyListeners();
  }
}
