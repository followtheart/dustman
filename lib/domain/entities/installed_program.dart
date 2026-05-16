import 'package:path/path.dart' as p;

/// 一条已安装程序记录（来自 Uninstall 注册表项）。
class InstalledProgram {
  InstalledProgram({
    required this.displayName,
    required this.registryKeyPath,
    this.publisher,
    this.installLocation,
    this.systemComponent = false,
  });

  final String displayName;
  final String? publisher;

  /// 已规范化的绝对路径（小写、去尾部斜杠）。可能为 null（卸载条目未填写）。
  final String? installLocation;

  /// 来源键完整路径，便于追溯。形如 `HKLM\SOFTWARE\Microsoft\...\Uninstall\{GUID}`。
  final String registryKeyPath;

  /// `SystemComponent=1` 标识由 Windows 安装的"系统组件"，扫描时整体忽略。
  final bool systemComponent;

  /// 用于模糊匹配的小写、去空格、去标点 key。
  late final String matchKey = _normalize(displayName);

  /// Publisher 的模糊匹配 key。
  late final String? publisherKey =
      publisher == null ? null : _normalize(publisher!);

  static String _normalize(String s) {
    final buf = StringBuffer();
    for (final code in s.toLowerCase().codeUnits) {
      // a-z 0-9 保留，其余视为分隔
      if ((code >= 0x30 && code <= 0x39) || (code >= 0x61 && code <= 0x7a)) {
        buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }
}

/// 已安装程序索引：一次构建，供所有 Scanner 复用。
class InstalledProgramIndex {
  InstalledProgramIndex(List<InstalledProgram> programs)
      : _programs = List.unmodifiable(programs);

  final List<InstalledProgram> _programs;

  List<InstalledProgram> get programs => _programs;
  int get length => _programs.length;
  bool get isEmpty => _programs.isEmpty;

  /// 计算 [path] 的 basename 与所有 program 的 [InstalledProgram.matchKey]
  /// 模糊匹配。命中即视为"非残留"。
  ///
  /// 同时检查 InstallLocation 的双向包含关系：
  /// - `InstallLocation ⊇ path` 或 `path ⊇ InstallLocation`。
  bool matchesPath(String absolutePath) {
    final normalizedPath =
        p.normalize(absolutePath).toLowerCase().replaceAll('/', '\\');
    final baseKey = InstalledProgram._normalize(p.basename(absolutePath));
    if (baseKey.isEmpty) return false;

    for (final prog in _programs) {
      if (prog.installLocation != null) {
        final loc = prog.installLocation!;
        if (loc.isNotEmpty) {
          if (normalizedPath == loc ||
              _isWithin(loc, normalizedPath) ||
              _isWithin(normalizedPath, loc)) {
            return true;
          }
        }
      }
      if (_fuzzyMatch(baseKey, prog.matchKey)) return true;
      final pk = prog.publisherKey;
      if (pk != null && pk.isNotEmpty && _fuzzyMatch(baseKey, pk)) return true;
    }
    return false;
  }

  /// 判断注册表 publisher key（如 `Adobe`）是否与已安装程序的 publisher 模糊匹配。
  bool matchesPublisherKey(String publisherKeyName) {
    final key = InstalledProgram._normalize(publisherKeyName);
    if (key.isEmpty) return false;
    for (final prog in _programs) {
      final pk = prog.publisherKey;
      if (pk != null && pk.isNotEmpty && _fuzzyMatch(key, pk)) return true;
      if (_fuzzyMatch(key, prog.matchKey)) return true;
    }
    return false;
  }

  static bool _fuzzyMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    // 一方包含另一方且较短串长度 >= 4，避免 "as" 命中 "asus"
    if (a.length >= 4 && b.contains(a)) return true;
    if (b.length >= 4 && a.contains(b)) return true;
    return false;
  }

  static bool _isWithin(String parent, String child) {
    final pa = parent.endsWith('\\') ? parent : '$parent\\';
    return child.startsWith(pa);
  }
}
