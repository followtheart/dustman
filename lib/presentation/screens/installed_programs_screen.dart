import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_localizations.dart';
import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/installed_program.dart';
import '../providers/installed_programs_provider.dart';

class InstalledProgramsScreen extends StatefulWidget {
  const InstalledProgramsScreen({super.key});

  @override
  State<InstalledProgramsScreen> createState() =>
      _InstalledProgramsScreenState();
}

class _InstalledProgramsScreenState extends State<InstalledProgramsScreen> {
  final _queryCtrl = TextEditingController();
  bool _autoLoaded = false;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Consumer<InstalledProgramsProvider>(
      builder: (context, provider, _) {
        if (!_autoLoaded && provider.status == ProgramsStatus.idle) {
          _autoLoaded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => provider.refresh());
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(t.t('programs.title')),
            centerTitle: false,
            actions: [
              FilledButton.icon(
                onPressed: provider.status == ProgramsStatus.loading
                    ? null
                    : provider.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(t.t('programs.refresh')),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              _Header(provider: provider, queryCtrl: _queryCtrl),
              const Divider(height: 1),
              Expanded(child: _buildBody(context, provider, t)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    InstalledProgramsProvider provider,
    AppLocalizations t,
  ) {
    switch (provider.status) {
      case ProgramsStatus.idle:
      case ProgramsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ProgramsStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(provider.error ?? t.t('common.failed')),
          ),
        );
      case ProgramsStatus.loaded:
        final list = provider.programs;
        if (list.isEmpty) {
          return Center(child: Text(t.t('common.empty')));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: list.length,
          itemBuilder: (ctx, i) => _ProgramTile(program: list[i]),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.provider, required this.queryCtrl});

  final InstalledProgramsProvider provider;
  final TextEditingController queryCtrl;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: queryCtrl,
              decoration: InputDecoration(
                hintText: t.t('programs.search'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: provider.setQuery,
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<ProgramsSort>(
            value: provider.sort,
            isDense: true,
            onChanged: (s) {
              if (s != null) provider.setSort(s);
            },
            items: [
              for (final s in ProgramsSort.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
          ),
          const SizedBox(width: 12),
          Text(
            t.t('programs.count', {'n': '${provider.filteredCount}'}),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.program});

  final InstalledProgram program;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final subtitleLines = <String>[
      if (program.publisher?.isNotEmpty ?? false)
        '${t.t('programs.publisher')}: ${program.publisher}',
      if (program.displayVersion?.isNotEmpty ?? false)
        '${t.t('programs.version')}: ${program.displayVersion}',
      if (program.installLocation?.isNotEmpty ?? false)
        '${t.t('programs.installLocation')}: ${program.installLocation}',
      if (program.installDateTime != null)
        '${t.t('programs.installDate')}: ${_fmtDate(program.installDateTime!)}',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(Icons.inventory_2_outlined, color: scheme.primary),
        title: Text(
          program.displayName,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitleLines.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitleLines.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
        isThreeLine: subtitleLines.length > 1,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (program.estimatedBytes != null)
              Text(
                FileSizeFormatter.format(program.estimatedBytes!),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: (program.uninstallString == null)
                  ? null
                  : () => _confirmUninstall(context, program),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t.t('programs.uninstall')),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'copyKey') {
                  await Clipboard.setData(
                    ClipboardData(text: program.registryKeyPath),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t.t('common.copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                } else if (v == 'copyCmd' && program.uninstallString != null) {
                  await Clipboard.setData(
                    ClipboardData(text: program.uninstallString!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t.t('common.copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'copyKey', child: Text('复制注册表键')),
                if (program.uninstallString != null)
                  const PopupMenuItem(value: 'copyCmd', child: Text('复制卸载命令')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _confirmUninstall(
    BuildContext context,
    InstalledProgram program,
  ) async {
    final t = AppLocalizations.of(context);
    final cmd = program.uninstallString ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('programs.uninstallTitle')),
        content: Text(t.t('programs.uninstallBody', {
          'name': program.displayName,
          'cmd': cmd,
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.t('programs.uninstall')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final provider = context.read<InstalledProgramsProvider>();
    final ok = await provider.uninstall(program);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? t.t('programs.uninstallStarted')
            : t.t('programs.uninstallFailed', {'err': '-'})),
      ),
    );
  }
}
