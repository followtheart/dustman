import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/large_file_item.dart';
import '../providers/large_file_provider.dart';

class LargeFileScreen extends StatefulWidget {
  const LargeFileScreen({super.key});

  @override
  State<LargeFileScreen> createState() => _LargeFileScreenState();
}

class _LargeFileScreenState extends State<LargeFileScreen> {
  final _rootCtrl = TextEditingController();
  final _extCtrl = TextEditingController();

  @override
  void dispose() {
    _rootCtrl.dispose();
    _extCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LargeFileProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('大文件查找'),
            centerTitle: false,
            actions: [
              if (provider.status == LargeFileStatus.scanning)
                FilledButton.tonalIcon(
                  onPressed: provider.cancelScan,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('停止扫描'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _startScan(context, provider),
                  icon: const Icon(Icons.search),
                  label: const Text('开始扫描'),
                ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: (provider.selectedCount == 0 ||
                        provider.status == LargeFileStatus.scanning ||
                        provider.status == LargeFileStatus.cleaning)
                    ? null
                    : () => _confirmAndClean(context, provider),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text('清理选中 (${provider.selectedCount})'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              _FilterCard(
                rootCtrl: _rootCtrl,
                extCtrl: _extCtrl,
                provider: provider,
                onScan: () => _startScan(context, provider),
              ),
              _SummaryBar(provider: provider),
              if (provider.lastReport != null)
                _ReportBanner(provider: provider),
              const Divider(height: 1),
              Expanded(child: _ResultList(provider: provider)),
            ],
          ),
        );
      },
    );
  }

  void _startScan(BuildContext context, LargeFileProvider provider) {
    final root = _rootCtrl.text.trim();
    if (root.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写扫描根目录')),
      );
      return;
    }
    provider.setExtensionsFromText(_extCtrl.text);
    provider.scan(root);
  }

  Future<void> _confirmAndClean(
    BuildContext context,
    LargeFileProvider provider,
  ) async {
    final size = FileSizeFormatter.format(provider.selectedBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清理'),
        content: Text(
          '将处理 ${provider.selectedCount} 个文件 / ${size}。\n\n'
          '文件会移入回收站，可在系统回收站中恢复。',
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

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.rootCtrl,
    required this.extCtrl,
    required this.provider,
    required this.onScan,
  });

  final TextEditingController rootCtrl;
  final TextEditingController extCtrl;
  final LargeFileProvider provider;
  final VoidCallback onScan;

  static const _presets = <int, String>{
    50 * 1024 * 1024: '≥ 50 MB',
    100 * 1024 * 1024: '≥ 100 MB',
    500 * 1024 * 1024: '≥ 500 MB',
    1024 * 1024 * 1024: '≥ 1 GB',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = provider.status != LargeFileStatus.scanning &&
        provider.status != LargeFileStatus.cleaning;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: rootCtrl,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: '扫描根目录',
                    hintText: r'例如 D:\ 或 C:\Users\me\Downloads',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  onSubmitted: (_) => onScan(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: extCtrl,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: '后缀过滤（可选）',
                    hintText: '如 iso, mp4, zip',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  onSubmitted: (_) => onScan(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('最小尺寸：'),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in _presets.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: provider.minBytes == entry.key,
                      onSelected: enabled
                          ? (_) => provider.setMinBytes(entry.key)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.provider});
  final LargeFileProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = switch (provider.status) {
      LargeFileStatus.idle =>
        '设置好根目录与阈值后点击"开始扫描"。${provider.describeFilter()}',
      LargeFileStatus.scanning => '正在扫描 ${provider.rootPath ?? ""} … '
          '已发现 ${provider.totalCount} 个 / ${FileSizeFormatter.format(provider.totalBytes)}',
      LargeFileStatus.scanned ||
      LargeFileStatus.reported =>
        '扫描完成：${provider.totalCount} 个文件 · '
            '合计 ${FileSizeFormatter.format(provider.totalBytes)}（${provider.describeFilter()}）',
      LargeFileStatus.cleaning => '正在清理…',
      LargeFileStatus.error => '出错：${provider.error}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (provider.status == LargeFileStatus.scanning)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (provider.status == LargeFileStatus.scanning)
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (provider.totalCount > 0) ...[
            Text(
              '已选 ${provider.selectedCount} / '
              '${FileSizeFormatter.format(provider.selectedBytes)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportBanner extends StatelessWidget {
  const _ReportBanner({required this.provider});
  final LargeFileProvider provider;

  @override
  Widget build(BuildContext context) {
    final report = provider.lastReport!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
            child: Text(
              '清理完成：释放 ${FileSizeFormatter.format(report.bytesFreed)}，'
              '${report.itemsDeleted} 个文件已移入回收站，失败 ${report.failures.length} 项',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.provider});
  final LargeFileProvider provider;

  @override
  Widget build(BuildContext context) {
    final items = provider.items;
    if (items.isEmpty) {
      if (provider.status == LargeFileStatus.scanning) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Text(
          provider.status == LargeFileStatus.idle
              ? '尚未扫描'
              : '未找到符合条件的大文件',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => provider.toggleAll(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('全选'),
              ),
              TextButton.icon(
                onPressed: () => provider.toggleAll(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('全不选'),
              ),
              TextButton.icon(
                onPressed: () => provider.selectTopN(10),
                icon: const Icon(Icons.format_list_numbered, size: 18),
                label: const Text('选前 10'),
              ),
              const Spacer(),
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 4),
              DropdownButton<LargeFileSort>(
                value: provider.sort,
                isDense: true,
                underline: const SizedBox.shrink(),
                onChanged: (v) {
                  if (v != null) provider.setSort(v);
                },
                items: [
                  for (final s in LargeFileSort.values)
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
              return _LargeFileTile(
                item: item,
                selected: provider.isSelected(item.path),
                onToggle: (v) => provider.toggle(item.path, v),
                onRemove: () => provider.removeItem(item.path),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LargeFileTile extends StatelessWidget {
  const _LargeFileTile({
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
  });

  final LargeFileItem item;
  final bool selected;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Checkbox(value: selected, onChanged: onToggle),
        title: Text(
          item.path.split(RegExp(r'[\\/]')).last,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.path,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FileSizeFormatter.format(item.size),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _fmtDate(item.lastModified),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            PopupMenuButton<_TileAction>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) async {
                switch (action) {
                  case _TileAction.copy:
                    await Clipboard.setData(
                      ClipboardData(text: item.path),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制路径'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  case _TileAction.remove:
                    onRemove();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: _TileAction.copy, child: Text('复制路径')),
                PopupMenuItem(value: _TileAction.remove, child: Text('从列表移除')),
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
}

enum _TileAction { copy, remove }
