import 'package:flutter/material.dart';

import '../widgets/sidebar_nav.dart';
import 'duplicate_files_screen.dart';
import 'junk_clean_screen.dart';
import 'large_file_screen.dart';
import 'placeholder_screen.dart';
import 'settings_screen.dart';
import 'startup_manager_screen.dart';
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
      icon: Icons.content_copy_outlined,
      selectedIcon: Icons.content_copy,
      label: '重复文件',
    ),
    NavDestinationItem(
      icon: Icons.power_settings_new_outlined,
      selectedIcon: Icons.power_settings_new,
      label: '启动项',
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
      const LargeFileScreen(),
      const DuplicateFilesScreen(),
      const StartupManagerScreen(),
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
