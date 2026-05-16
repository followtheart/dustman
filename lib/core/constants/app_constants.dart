class AppConstants {
  AppConstants._();

  static const appName = 'Dustman';
  static const appVersion = '0.3.0';

  /// 受保护路径关键字 —— 命中任意一个的绝对路径都禁止删除。
  /// 比较时统一转小写后做 contains 判断。
  static const protectedPathSegments = <String>[
    r'\windows\system32',
    r'\windows\syswow64',
    r'\windows\winsxs',
    r'\windows\servicing',
    r'\program files\windowsapps',
    r'\program files\modifiablewindowsapps',
    r'\program files\common files',
    r'\program files (x86)\common files',
    r'\program files\internet explorer',
    r'\program files (x86)\internet explorer',
    r'\program files\windows defender',
    r'\program files\windows nt',
    r'\program files (x86)\windows nt',
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

  /// 残留扫描：文件系统一级目录白名单（直接跳过，不视为残留）。
  /// 全部以"basename 小写"形式存储；比较时同样转小写。
  static const residueDirWhitelist = <String>[
    'common files',
    'internet explorer',
    'windows defender',
    'windows nt',
    'windowsapps',
    'modifiablewindowsapps',
    'microsoft',
    'microsoftedge',
    'microsoft edge',
    'microsoft edgeupdate',
    'microsoft edgewebview',
    'microsoft office',
    'microsoft visual studio',
    'microsoft sdks',
    'microsoft sql server',
    'microsoft.net',
    'reference assemblies',
    'package cache',
    'packages',
    'msbuild',
    'intel',
    'nvidia corporation',
    'nvidia',
    'amd',
    'realtek',
    'windowspowershell',
    'dotnet',
    'usoshared',
    'usoprivate',
    'application data',
    'desktop',
    'documents',
    'start menu',
    'templates',
  ];

  /// 残留扫描：注册表一级 Publisher 键黑名单（永不删除）。
  /// 全部小写。
  static const registryPublisherBlacklist = <String>[
    'microsoft',
    'windows',
    'classes',
    'clients',
    'registeredapplications',
    'policies',
    'wow6432node',
    'intel',
    'amd',
    'nvidia corporation',
    'nvidia',
    'realtek',
    'realtek semiconductor corp.',
    'khronos',
    'khronos group',
    'odbc',
    'openssl',
    'rapport',
    'thinpoint',
    'wow6432',
  ];
}
