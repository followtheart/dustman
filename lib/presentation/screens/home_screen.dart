import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/edition.dart';
import '../../core/i18n/app_localizations.dart';
import '../providers/schedule_provider.dart';
import '../widgets/sidebar_nav.dart';
import 'account_screen.dart';
import 'membership_screen.dart';
import 'disk_analysis_screen.dart';
import 'duplicate_files_screen.dart';
import 'installed_programs_screen.dart';
import 'junk_clean_screen.dart';
import 'large_file_screen.dart';
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
  bool _reminderChecked = false;

  static const _junkIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowReminder());
  }

  Future<void> _maybeShowReminder() async {
    if (_reminderChecked) return;
    _reminderChecked = true;
    final scheduler = context.read<ScheduleProvider>();
    // Provider 还没 load 完时 daysSinceLastRun 还是 null，但 isDue 看 enabled
    // 我们等一帧再判断一次。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (!scheduler.isDue) return;
    final t = AppLocalizations.of(context);
    final days = scheduler.daysSinceLastRun ?? scheduler.interval.days;
    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('schedule.reminderTitle')),
        content: Text(t.t('schedule.reminderBody', {'days': '$days'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.t('schedule.later')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.t('schedule.scanNow')),
          ),
        ],
      ),
    );
    if (picked == true) {
      await scheduler.markRanNow();
      if (!mounted) return;
      setState(() => _index = _junkIndex);
    } else {
      await scheduler.snooze();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final destinations = <NavDestinationItem>[
      NavDestinationItem(
        icon: Icons.cleaning_services_outlined,
        selectedIcon: Icons.cleaning_services,
        label: t.t('nav.junk'),
      ),
      NavDestinationItem(
        icon: Icons.app_registration_outlined,
        selectedIcon: Icons.app_registration,
        label: t.t('nav.residue'),
      ),
      NavDestinationItem(
        icon: Icons.find_in_page_outlined,
        selectedIcon: Icons.find_in_page,
        label: t.t('nav.largeFiles'),
      ),
      NavDestinationItem(
        icon: Icons.content_copy_outlined,
        selectedIcon: Icons.content_copy,
        label: t.t('nav.duplicates'),
      ),
      NavDestinationItem(
        icon: Icons.power_settings_new_outlined,
        selectedIcon: Icons.power_settings_new,
        label: t.t('nav.startup'),
      ),
      NavDestinationItem(
        icon: Icons.pie_chart_outline,
        selectedIcon: Icons.pie_chart,
        label: t.t('nav.disk'),
      ),
      NavDestinationItem(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: t.t('nav.programs'),
      ),
      if (kIsPro)
        NavDestinationItem(
          icon: Icons.account_circle_outlined,
          selectedIcon: Icons.account_circle,
          label: t.t('nav.account'),
        ),
      if (kIsPro)
        NavDestinationItem(
          icon: Icons.workspace_premium_outlined,
          selectedIcon: Icons.workspace_premium,
          label: t.t('nav.membership'),
        ),
      NavDestinationItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: t.t('nav.settings'),
      ),
    ];

    final screens = <Widget>[
      const JunkCleanScreen(),
      const UninstallResidueScreen(),
      const LargeFileScreen(),
      const DuplicateFilesScreen(),
      const StartupManagerScreen(),
      const DiskAnalysisScreen(),
      const InstalledProgramsScreen(),
      if (kIsPro) const AccountScreen(),
      if (kIsPro) const MembershipScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          SidebarNav(
            destinations: destinations,
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
