import 'package:flutter/material.dart';

import '../widgets/sidebar_nav.dart';
import 'junk_clean_screen.dart';
import 'placeholder_screen.dart';
import 'settings_screen.dart';
import 'uninstall_residue_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _destinations = <NavDestinationItem>[
    NavDestinationItem(
      icon: Icons.cleaning_services_outlined,
      selectedIcon: Icons.cleaning_services,
      label: '垃圾清理',
    ),
    NavDestinationItem(
      icon: Icons.app_registration_outlined,
      selectedIcon: Icons.app_registration,
      label: '卸载残留',
    ),
    NavDestinationItem(
      icon: Icons.find_in_page_outlined,
      selectedIcon: Icons.find_in_page,
      label: '大文件查找',
    ),
    NavDestinationItem(
      icon: Icons.pie_chart_outline,
      selectedIcon: Icons.pie_chart,
      label: '磁盘分析',
    ),
    NavDestinationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const JunkCleanScreen(),
      const UninstallResidueScreen(),
      const PlaceholderScreen(
        title: '大文件查找',
        message: '即将上线：递归扫描指定目录，按文件大小排序定位"空间大户"。',
      ),
      const PlaceholderScreen(
        title: '磁盘分析',
        message: '即将上线：以 TreeMap 可视化每个目录的占用比例。',
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          SidebarNav(
            destinations: _destinations,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: screens[_index]),
        ],
      ),
    );
  }
}
