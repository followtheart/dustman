import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/residue_item.dart';
import '../providers/residue_provider.dart';
import '../widgets/residue_item_tile.dart';

class UninstallResidueScreen extends StatelessWidget {
  const UninstallResidueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ResidueKind.values.length,
      child: Consumer<ResidueProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('卸载残留'),
              centerTitle: false,
              actions: [
                FilledButton.icon(
                  onPressed:
                      provider.status == ResidueStatus.scanning ||
                              provider.status == ResidueStatus.cleaning
                          ? null
                          : provider.scan,
                  icon: const Icon(Icons.search),
                  label: const Text('开始扫描'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: (provider.selectedCount == 0 ||
                          provider.status == ResidueStatus.cleaning ||
                          provider.status == ResidueStatus.scanning)
                      ? null
                      : () => _confirmAndClean(context, provider),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(
                    '清理选中 (${provider.selectedCount})',
                  ),
                ),
                const SizedBox(width: 16),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final k in ResidueKind.values)
                      Tab(
                        text: '${k.displayName} (${provider.itemsByKind[k]!.length})',
                      ),
                  ],
                ),
              ),
            ),
            body: switch (provider.status) {
              ResidueStatus.idle => _IdleHint(onScan: provider.scan),
              ResidueStatus.scanning => const _Loading(message: '正在扫描…'),
              ResidueStatus.cleaning => const _Loading(message: '正在清理…'),
              ResidueStatus.error => _ErrorView(message: provider.error ?? '未知错误'),
              ResidueStatus.scanned ||
              ResidueStatus.reported =>
                _ScannedView(provider: provider),
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmAndClean(
    BuildContext context,
    ResidueProvider provider,
  ) async {
    final size = FileSizeFormatter.format(provider.selectedBytes);
    final hasRegistry = provider.itemsByKind[ResidueKind.registryKey]!
        .any((it) => provider.isSelected(it.id));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清理'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将处理 ${provider.selectedCount} 项 / 估算 $size：',
            ),
            const SizedBox(height: 12),
            const Text('· 文件 / 目录 / 失效快捷方式：移入回收站（可恢复）'),
            if (hasRegistry)
              const Text(
                '· 注册表项：先导出 .reg 备份到 %APPDATA%\\Dustman\\backups\\…，再删除',
              ),
            const SizedBox(height: 8),
            Text(
              '注册表中 HKLM 项的删除可能需要管理员权限。',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始清理'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.cleanSelected();
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
          Icon(
            Icons.cleaning_services_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '点击"开始扫描"，查找已卸载程序的遗留目录、注册表项与失效快捷方式。',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.search),
            label: const Text('开始扫描'),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('扫描失败：$message', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ScannedView extends StatelessWidget {
  const _ScannedView({required this.provider});
  final ResidueProvider provider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryCard(provider: provider),
        if (provider.lastReport != null)
          _ReportBanner(report: provider.lastReport!),
        Expanded(
          child: TabBarView(
            children: [
              for (final k in ResidueKind.values)
                _KindList(kind: k, provider: provider),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.provider});
  final ResidueProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现 ${provider.totalCandidates} 个候选 · 估算可释放 ${FileSizeFormatter.format(provider.totalBytes)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '按信心：高 ${provider.countByConfidence(ResidueConfidence.high)} · '
                  '中 ${provider.countByConfidence(ResidueConfidence.medium)} · '
                  '低 ${provider.countByConfidence(ResidueConfidence.low)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            '已选 ${provider.selectedCount} 项 / '
            '${FileSizeFormatter.format(provider.selectedBytes)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ReportBanner extends StatelessWidget {
  const _ReportBanner({required this.report});
  final ResidueCleanReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '清理完成：释放 ${FileSizeFormatter.format(report.bytesFreed)}，'
                  '处理 ${report.itemsDeleted} 项，失败 ${report.failures.length} 项',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (report.registryBackupDir != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '注册表备份：${report.registryBackupDir}',
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindList extends StatelessWidget {
  const _KindList({required this.kind, required this.provider});

  final ResidueKind kind;
  final ResidueProvider provider;

  @override
  Widget build(BuildContext context) {
    final items = provider.itemsSortedBy(kind);
    if (items.isEmpty) {
      return Center(
        child: Text(
          '未发现 ${kind.displayName} 残留',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => provider.toggleAll(kind, true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('全选'),
              ),
              TextButton.icon(
                onPressed: () => provider.toggleAll(kind, false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('全不选'),
              ),
              const Spacer(),
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 4),
              DropdownButton<ResidueSort>(
                value: provider.sort,
                isDense: true,
                underline: const SizedBox.shrink(),
                onChanged: (v) {
                  if (v != null) provider.setSort(v);
                },
                items: [
                  for (final s in ResidueSort.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              return ResidueItemTile(
                key: ValueKey(item.id),
                item: item,
                selected: provider.isSelected(item.id),
                onToggle: (v) => provider.toggleItem(item.id, v),
                onRemove: () => provider.removeItem(item.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
