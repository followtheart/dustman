class AppConstants {
  AppConstants._();

  static const appName = 'Dustman';
  static const appVersion = '0.1.0';

  /// 受保护路径关键字 —— 命中任意一个的绝对路径都禁止删除。
  /// 比较时统一转小写后做 contains 判断。
  static const protectedPathSegments = <String>[
    r'\windows\system32',
    r'\windows\syswow64',
    r'\program files\windowsapps',
    r'\users\public\desktop',
    r'\$recycle.bin',
  ];

  /// 当前用户下不可触碰的子目录（Documents、Desktop 等）
  static const userProtectedSubdirs = <String>[
    'Documents',
    'Desktop',
    'Pictures',
    'Videos',
    'Music',
  ];
}
