import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/edition.dart';
import '../../core/i18n/app_localizations.dart';
import '../../core/utils/app_paths.dart';
import '../providers/locale_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final scheduleProvider = context.watch<ScheduleProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(t.t('nav.settings')), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SectionCard(
            title: t.t('settings.theme'),
            child: ListTile(
              title: Text(t.t('settings.theme')),
              subtitle: Text(_themeLabel(themeProvider.themeMode, t)),
              trailing: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto),
                    label: Text(t.t('settings.themeSystem')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode),
                    label: Text(t.t('settings.themeLight')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode),
                    label: Text(t.t('settings.themeDark')),
                  ),
                ],
                selected: {themeProvider.themeMode},
                onSelectionChanged: (s) => themeProvider.setMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('settings.language'),
            child: ListTile(
              title: Text(t.t('settings.language')),
              subtitle: Text(_languageLabel(localeProvider.stored, t)),
              trailing: SegmentedButton<String>(
                segments: [
                  const ButtonSegment(
                    value: 'system',
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Auto'),
                  ),
                  ButtonSegment(
                    value: 'zh',
                    label: Text(t.t('settings.languageZh')),
                  ),
                  ButtonSegment(
                    value: 'en',
                    label: Text(t.t('settings.languageEn')),
                  ),
                ],
                selected: {localeProvider.stored},
                onSelectionChanged: (s) => localeProvider.setLocale(s.first),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('schedule.title'),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(t.t('schedule.enabled')),
                  subtitle: Text(_scheduleSubtitle(scheduleProvider, t)),
                  value: scheduleProvider.enabled,
                  onChanged: scheduleProvider.setEnabled,
                ),
                if (scheduleProvider.enabled)
                  ListTile(
                    title: Text(t.t('schedule.interval')),
                    trailing: DropdownButton<ScheduleInterval>(
                      value: scheduleProvider.interval,
                      onChanged: (v) {
                        if (v != null) scheduleProvider.setInterval(v);
                      },
                      items: [
                        for (final s in ScheduleInterval.values)
                          DropdownMenuItem(
                            value: s,
                            child: Text(t.t(s.i18nKey)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('settings.portable'),
            child: ListTile(
              title: Text(t.t('settings.portable')),
              subtitle: Text(
                AppPaths.isPortable
                    ? t.t('settings.portableOn')
                    : t.t('settings.portableOff'),
              ),
              trailing: Icon(
                AppPaths.isPortable
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                color: AppPaths.isPortable
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('settings.dataDir'),
            child: ListTile(
              title: Text(t.t('settings.dataDir')),
              subtitle: SelectableText(
                AppPaths.dataDir,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                tooltip: t.t('common.copy'),
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: AppPaths.dataDir),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t.t('common.copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('settings.cli'),
            child: ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(t.t('settings.cli')),
              subtitle: Text(t.t('settings.cliHint')),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: t.t('settings.about'),
            child: ListTile(
              title: Text(t.t('settings.about')),
              subtitle: Text(
                '${AppConstants.appName} v${AppConstants.appVersion} (${kEdition.label})\n'
                '一个安全、可视化的 Windows 桌面清理工具。',
              ),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode, AppLocalizations t) => switch (mode) {
        ThemeMode.system => t.t('settings.themeSystem'),
        ThemeMode.light => t.t('settings.themeLight'),
        ThemeMode.dark => t.t('settings.themeDark'),
      };

  String _languageLabel(String stored, AppLocalizations t) {
    if (stored == 'zh') return t.t('settings.languageZh');
    if (stored == 'en') return t.t('settings.languageEn');
    return t.t('settings.themeSystem');
  }

  String _scheduleSubtitle(ScheduleProvider provider, AppLocalizations t) {
    final last = provider.lastRun;
    final lastStr = last == null
        ? t.t('schedule.never')
        : '${last.year}-${_two(last.month)}-${_two(last.day)}';
    return '${t.t('schedule.lastRun')}: $lastStr';
  }

  String _two(int v) => v < 10 ? '0$v' : '$v';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  // 仅用于自我说明；当前 Card 由内部 ListTile 自带标题。
  // ignore: unused_element_parameter
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}
