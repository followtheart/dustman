import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/platform/installed_programs.dart';
import '../../data/services/uninstaller_service.dart';
import '../../domain/entities/installed_program.dart';

enum ProgramsStatus { idle, loading, loaded, error }

enum ProgramsSort {
  name('按名称'),
  sizeDesc('按占用 ↓'),
  installDateDesc('按安装日期 ↓'),
  publisher('按发行商');

  const ProgramsSort(this.label);
  final String label;
}

class InstalledProgramsProvider extends ChangeNotifier {
  InstalledProgramsProvider({InstalledProgramsRepository? repo})
      : _repo = repo ?? InstalledProgramsRepository();

  final InstalledProgramsRepository _repo;

  ProgramsStatus _status = ProgramsStatus.idle;
  ProgramsStatus get status => _status;

  String? _error;
  String? get error => _error;

  List<InstalledProgram> _programs = const [];
  String _query = '';
  ProgramsSort _sort = ProgramsSort.name;

  ProgramsSort get sort => _sort;
  String get query => _query;

  /// 应用过滤 + 排序后的视图。
  List<InstalledProgram> get programs {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<InstalledProgram>.from(_programs)
        : _programs.where((p) {
            if (p.displayName.toLowerCase().contains(q)) return true;
            if (p.publisher?.toLowerCase().contains(q) ?? false) return true;
            return false;
          }).toList();
    filtered.sort(_comparator);
    return List.unmodifiable(filtered);
  }

  int get totalCount => _programs.length;
  int get filteredCount => programs.length;

  int Function(InstalledProgram, InstalledProgram) get _comparator {
    switch (_sort) {
      case ProgramsSort.name:
        return (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      case ProgramsSort.sizeDesc:
        return (a, b) {
          final sa = a.estimatedBytes ?? -1;
          final sb = b.estimatedBytes ?? -1;
          return sb.compareTo(sa);
        };
      case ProgramsSort.installDateDesc:
        return (a, b) {
          final da = a.installDateTime?.millisecondsSinceEpoch ?? -1;
          final db = b.installDateTime?.millisecondsSinceEpoch ?? -1;
          return db.compareTo(da);
        };
      case ProgramsSort.publisher:
        return (a, b) => (a.publisher ?? '').compareTo(b.publisher ?? '');
    }
  }

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void setSort(ProgramsSort s) {
    if (_sort == s) return;
    _sort = s;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_status == ProgramsStatus.loading) return;
    _status = ProgramsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final idx = await _repo.build();
      _programs = List.unmodifiable(idx.programs);
      _status = ProgramsStatus.loaded;
    } on Object catch (e, st) {
      AppLogger.error('installed programs refresh failed',
          error: e, stack: st, tag: 'InstalledProgramsProvider');
      _status = ProgramsStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<bool> uninstall(InstalledProgram program, {bool silent = false}) {
    return UninstallerService.launch(program, silent: silent);
  }
}
