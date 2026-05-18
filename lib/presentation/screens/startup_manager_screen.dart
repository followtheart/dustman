import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/edition.dart';
import '../../domain/entities/startup_item.dart';
import '../providers/startup_provider.dart';
import '../widgets/ai_action_button.dart';

class StartupManagerScreen extends StatelessWidget {
  const StartupManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StartupProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('启动项管理'),
            centerTitle: false,
            actions: [
              FilledButton.icon(
                onPressed: (provider.status == StartupStatus.scanning ||
                        provider.status == StartupStatus.removing)
                    ? null
                    : provider.scan,
                icon: const Icon(Icons.search),
                label: const Text('扫描启动项'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: (provider.selectedCount == 0 ||
                        provider.status == StartupStatus.scanning ||
                        provider.status == StartupStatus.removing)
                    ? null
                    : () => _confirmAndRemove(context, provider),
                icon: const Icon(Icons.power_settings_new),
                label: Text('禁用选中 (${provider.selectedCount})'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: switch (provider.status) {
            StartupStatus.idle => _IdleHint(onScan: provider.scan),
            StartupStatus.scanning => const _Loading('正在扫描启动项…'),
            StartupStatus.removing => const _Loading('正在禁用…'),
            StartupStatus.error => _ErrorView(provider.error ?? '未知错误'),
            StartupStatus.scanned ||
            StartupStatus.reported =>
              _ScannedView(provider: provider),
          },
        );
      },
    );
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    StartupProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认禁用'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将禁用 ${provider.selectedCount} 个启动项：'),
            const SizedBox(height: 12),
            const Text('· 注册表项：删除对应值（Run / RunOnce 子项的值名）'),
            const Text('· 启动文件夹快捷方式：移入回收站（可恢复）'),
            if (provider.hasElevationRequiredSelection) ...[
              const SizedBox(height: 8),
              Text(
                '含 HKLM / 全局启动项 —— 若 Dustman 非管理员启动，删除会失败。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('禁用'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.removeSelected();
    }
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.onScan});
  final VoidCallback onScan;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.power_settings_new,
              size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('扫描注册表 Run / RunOnce 及启动文件夹，统一管理开机启动项'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.search),
            label: const Text('扫描启动项'),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text(msg),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('扫描失败：$msg', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ScannedView extends StatelessWidget {
  const _ScannedView({required this.provider});
  final StartupProvider provider;

  @override
  Widget build(BuildContext context) {
    final grouped = provider.groupBySource();
    final scheme = Theme.of(context).colorScheme;

    if (provider.totalCount == 0) {
      return const Center(child: Text('未发现启动项'));
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${provider.totalCount} 项 · '
                  '注册表 ${provider.registryCount} · '
                  '启动文件夹 ${provider.folderCount}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text('已选 ${provider.selectedCount} 项'),
            ],
          ),
        ),
        if (provider.lastReport != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已禁用 ${provider.lastReport!.itemsDeleted} 项，'
                    '失败 ${provider.lastReport!.failures.length} 项',
                    style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final entry in grouped.entries)
                if (entry.value.isNotEmpty)
                  _SourceSection(
                    source: entry.key,
                    items: entry.value,
                    provider: provider,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceSection extends StatelessWidget {
  const _SourceSection({
    required this.source,
    required this.items,
    required this.provider,
  });

  final StartupSource source;
  final List<StartupItem> items;
  final StartupProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                source.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 6),
              if (source.requiresElevation)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '需管理员',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => provider.toggleSource(source, true),
                child: const Text('本组全选'),
              ),
              TextButton(
                onPressed: () => provider.toggleSource(source, false),
                child: const Text('本组全不选'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Checkbox(
                  value: provider.isSelected(item.id),
                  onChanged: (v) => provider.toggle(item.id, v),
                ),
                title: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.command,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.shortcutPath != null)
                        Text(
                          '.lnk: ${item.shortcutPath}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.outline,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.registryFullKeyPath != null)
                        Text(
                          '${item.registryFullKeyPath}\\${item.registryValueName}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.outline,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kIsPro)
                      IconButton(
                        tooltip: 'AI 分析',
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        onPressed: () => runAiAnalysis(
                          context,
                          intent: 'explain_startup_item',
                          title: 'AI 分析：${item.name}',
                          ctx: {
                            'name': item.name,
                            'command': item.command,
                            'source': item.source.name,
                            if (item.targetPath != null) 'target_path': item.targetPath,
                            if (item.registryFullKeyPath != null)
                              'registry_key': item.registryFullKeyPath,
                          },
                        ),
                      ),
                    IconButton(
                      tooltip: '复制命令',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: item.command),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制命令'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
