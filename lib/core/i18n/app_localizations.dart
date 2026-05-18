import 'package:flutter/widgets.dart';

/// 简易 i18n。当 `key` 缺失时回落到中文版本，避免抛异常。
class AppLocalizations {
  AppLocalizations(this.localeCode);

  final String localeCode;

  static const supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];

  static const Map<String, Map<String, String>> _table = {
    // 通用
    'app.name': {'zh': 'Dustman', 'en': 'Dustman'},
    'common.scan': {'zh': '扫描', 'en': 'Scan'},
    'common.cancel': {'zh': '取消', 'en': 'Cancel'},
    'common.confirm': {'zh': '确认', 'en': 'Confirm'},
    'common.refresh': {'zh': '刷新', 'en': 'Refresh'},
    'common.copy': {'zh': '复制', 'en': 'Copy'},
    'common.copied': {'zh': '已复制', 'en': 'Copied'},
    'common.loading': {'zh': '正在加载…', 'en': 'Loading…'},
    'common.empty': {'zh': '暂无数据', 'en': 'No data'},
    'common.failed': {'zh': '失败', 'en': 'Failed'},

    // 侧边栏
    'nav.junk': {'zh': '垃圾清理', 'en': 'Junk Cleaner'},
    'nav.residue': {'zh': '卸载残留', 'en': 'Uninstall Residue'},
    'nav.largeFiles': {'zh': '大文件查找', 'en': 'Large Files'},
    'nav.duplicates': {'zh': '重复文件', 'en': 'Duplicates'},
    'nav.startup': {'zh': '启动项', 'en': 'Startup'},
    'nav.disk': {'zh': '磁盘分析', 'en': 'Disk Map'},
    'nav.programs': {'zh': '已安装程序', 'en': 'Programs'},
    'nav.account': {'zh': '账户', 'en': 'Account'},
    'nav.membership': {'zh': '会员', 'en': 'Membership'},
    'nav.settings': {'zh': '设置', 'en': 'Settings'},

    // 磁盘分析
    'disk.title': {'zh': '磁盘空间分析', 'en': 'Disk Space Analysis'},
    'disk.rootHint': {
      'zh': r'选择一个根目录（如 D:\）进行 TreeMap 可视化',
      'en': r'Pick a root (e.g. D:\) to visualize as a treemap',
    },
    'disk.rootLabel': {'zh': '分析根目录', 'en': 'Root directory'},
    'disk.start': {'zh': '开始分析', 'en': 'Start'},
    'disk.scanning': {'zh': '正在统计目录大小…', 'en': 'Scanning directory sizes…'},
    'disk.totalSize': {'zh': '合计', 'en': 'Total'},
    'disk.entries': {'zh': '条目数', 'en': 'Entries'},
    'disk.elapsed': {'zh': '耗时', 'en': 'Elapsed'},
    'disk.zoomOut': {'zh': '返回上层', 'en': 'Up'},
    'disk.zoomReset': {'zh': '回到根', 'en': 'Reset'},
    'disk.help': {
      'zh': '点击矩形进入子目录，右键返回上层。矩形面积与占用大小成正比。',
      'en': 'Click a rectangle to drill in, right-click to go up. Area maps to size.',
    },
    'disk.depth': {'zh': '最大深度', 'en': 'Max depth'},

    // 已安装程序
    'programs.title': {'zh': '已安装程序', 'en': 'Installed Programs'},
    'programs.search': {'zh': '搜索程序名称或发行商', 'en': 'Search by name or publisher'},
    'programs.count': {'zh': '共 {n} 个程序', 'en': '{n} programs'},
    'programs.refresh': {'zh': '刷新列表', 'en': 'Refresh'},
    'programs.uninstall': {'zh': '卸载', 'en': 'Uninstall'},
    'programs.uninstallTitle': {'zh': '确认卸载', 'en': 'Confirm uninstall'},
    'programs.uninstallBody': {
      'zh': '即将运行 {name} 的卸载程序：\n\n{cmd}\n\n卸载向导将打开。',
      'en': 'About to launch the uninstaller for {name}:\n\n{cmd}\n\nThe uninstall wizard will open.',
    },
    'programs.uninstallStarted': {'zh': '已启动卸载向导', 'en': 'Uninstall wizard started'},
    'programs.uninstallFailed': {'zh': '启动卸载失败：{err}', 'en': 'Failed to start uninstall: {err}'},
    'programs.noUninstallString': {
      'zh': '该程序未提供卸载命令',
      'en': 'No uninstall command available',
    },
    'programs.publisher': {'zh': '发行商', 'en': 'Publisher'},
    'programs.installLocation': {'zh': '安装位置', 'en': 'Install location'},
    'programs.estimatedSize': {'zh': '占用', 'en': 'Size'},
    'programs.installDate': {'zh': '安装日期', 'en': 'Installed'},
    'programs.version': {'zh': '版本', 'en': 'Version'},

    // 计划
    'schedule.title': {'zh': '清理计划', 'en': 'Cleanup Schedule'},
    'schedule.enabled': {'zh': '启用定期提醒', 'en': 'Enable reminder'},
    'schedule.interval': {'zh': '提醒频率', 'en': 'Frequency'},
    'schedule.intervalDaily': {'zh': '每天', 'en': 'Daily'},
    'schedule.intervalWeekly': {'zh': '每周', 'en': 'Weekly'},
    'schedule.intervalMonthly': {'zh': '每月', 'en': 'Monthly'},
    'schedule.lastRun': {'zh': '上次提醒', 'en': 'Last reminder'},
    'schedule.never': {'zh': '从未', 'en': 'Never'},
    'schedule.reminderTitle': {'zh': '该清理一下啦', 'en': 'Time to tidy up'},
    'schedule.reminderBody': {
      'zh': '距离上次扫描已经过去 {days} 天，是否立即扫描垃圾？',
      'en': "It's been {days} day(s) since the last scan. Run a scan now?",
    },
    'schedule.scanNow': {'zh': '立即扫描', 'en': 'Scan now'},
    'schedule.later': {'zh': '稍后', 'en': 'Later'},

    // 设置
    'settings.theme': {'zh': '主题', 'en': 'Theme'},
    'settings.themeSystem': {'zh': '跟随系统', 'en': 'System'},
    'settings.themeLight': {'zh': '浅色', 'en': 'Light'},
    'settings.themeDark': {'zh': '深色', 'en': 'Dark'},
    'settings.language': {'zh': '语言', 'en': 'Language'},
    'settings.languageZh': {'zh': '中文（简体）', 'en': 'Chinese (Simplified)'},
    'settings.languageEn': {'zh': 'English', 'en': 'English'},
    'settings.portable': {'zh': '便携模式', 'en': 'Portable mode'},
    'settings.portableOn': {
      'zh': '已启用：偏好与日志保存在程序目录',
      'en': 'On: prefs and logs in the app folder',
    },
    'settings.portableOff': {
      'zh': '未启用：数据保存在 %APPDATA%\\Dustman',
      'en': 'Off: data stored in %APPDATA%\\Dustman',
    },
    'settings.about': {'zh': '关于', 'en': 'About'},
    'settings.dataDir': {'zh': '数据目录', 'en': 'Data directory'},
    'settings.cli': {'zh': '命令行', 'en': 'Command line'},
    'settings.cliHint': {
      'zh': '运行 dustman.exe --help 查看 scan/clean 等命令。',
      'en': 'Run dustman.exe --help to see scan/clean commands.',
    },
  };

  String t(String key, [Map<String, String>? params]) {
    final entry = _table[key];
    if (entry == null) return key;
    var s = entry[_lang] ?? entry['zh'] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        s = s.replaceAll('{$k}', v);
      });
    }
    return s;
  }

  String get _lang => localeCode.startsWith('en') ? 'en' : 'zh';

  static AppLocalizations of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_LocalizationScope>();
    return inherited?.localizations ?? AppLocalizations('zh');
  }
}

class LocalizationScope extends StatelessWidget {
  const LocalizationScope({
    super.key,
    required this.localeCode,
    required this.child,
  });

  final String localeCode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _LocalizationScope(
      localizations: AppLocalizations(localeCode),
      child: child,
    );
  }
}

class _LocalizationScope extends InheritedWidget {
  const _LocalizationScope({
    required this.localizations,
    required super.child,
  });

  final AppLocalizations localizations;

  @override
  bool updateShouldNotify(_LocalizationScope oldWidget) =>
      oldWidget.localizations.localeCode != localizations.localeCode;
}
