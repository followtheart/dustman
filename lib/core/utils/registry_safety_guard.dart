import 'logger.dart';

/// 注册表删除前的最后一道守门人。
///
/// 与文件系统 SafetyGuard 类似，对超敏感的根键做硬性拦截。
/// 优先级高于黑名单：哪怕用户主动勾选，也不会被删除。
class RegistrySafetyGuard {
  RegistrySafetyGuard._();

  /// 任何"以这些前缀开头"的完整键路径都禁止删除。
  /// 比较时统一转小写。
  static const _protectedPrefixes = <String>[
    r'hklm\software\microsoft',
    r'hklm\software\wow6432node\microsoft',
    r'hklm\software\classes',
    r'hklm\software\wow6432node\classes',
    r'hklm\software\clients',
    r'hklm\software\wow6432node\clients',
    r'hklm\software\policies',
    r'hklm\software\wow6432node\policies',
    r'hklm\software\registeredapplications',
    r'hklm\software\wow6432node\registeredapplications',
    r'hklm\system',
    r'hklm\security',
    r'hklm\sam',
    r'hklm\hardware',
    r'hkcu\software\microsoft',
    r'hkcu\software\classes',
    r'hkcu\software\policies',
    r'hkcu\software\registeredapplications',
  ];

  /// 这些完整键禁止删除（避免删除一级容器本身）。
  static const _protectedExact = <String>[
    r'hklm',
    r'hkcu',
    r'hklm\software',
    r'hklm\software\wow6432node',
    r'hkcu\software',
  ];

  static bool isSafeToDelete(String fullKeyPath) {
    final lower = fullKeyPath.toLowerCase().replaceAll('/', '\\').trim();
    if (lower.isEmpty) return false;

    // 只允许 HKLM\SOFTWARE\* 和 HKCU\SOFTWARE\* 下的项目（一级以下，至少 3 段）。
    final segments = lower.split('\\').where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) {
      AppLogger.warn(
        'blocked: registry key too shallow ($lower)',
        tag: 'RegistrySafetyGuard',
      );
      return false;
    }
    if (segments[0] != 'hklm' && segments[0] != 'hkcu') {
      AppLogger.warn(
        'blocked: only HKLM/HKCU allowed ($lower)',
        tag: 'RegistrySafetyGuard',
      );
      return false;
    }
    if (segments[1] != 'software') {
      AppLogger.warn(
        'blocked: only SOFTWARE branch allowed ($lower)',
        tag: 'RegistrySafetyGuard',
      );
      return false;
    }

    for (final exact in _protectedExact) {
      if (lower == exact) {
        AppLogger.warn(
          'blocked: protected exact key ($lower)',
          tag: 'RegistrySafetyGuard',
        );
        return false;
      }
    }

    for (final prefix in _protectedPrefixes) {
      if (lower == prefix || lower.startsWith('$prefix\\')) {
        AppLogger.warn(
          'blocked: protected prefix "$prefix" ($lower)',
          tag: 'RegistrySafetyGuard',
        );
        return false;
      }
    }
    return true;
  }
}
