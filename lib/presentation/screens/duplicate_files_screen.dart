import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/duplicate_group.dart';
import '../providers/duplicate_provider.dart';

class DuplicateFilesScreen extends StatefulWidget {
  const DuplicateFilesScreen({super.key});

  @override
  State<DuplicateFilesScreen> createState() => _DuplicateFilesScreenState();
}

class _DuplicateFilesScreenState extends State<DuplicateFilesScreen> {
  final _rootsCtrl = TextEditingController();

  @override
  void dispose() {
    _rootsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DuplicateProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('重复文件检测'),
            centerTitle: false,
            actions: [
              if (provider.status == DuplicateStatus.scanning)
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
                        provider.status == DuplicateStatus.scanning ||
                        provider.status == DuplicateStatus.cleaning)
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
                rootsCtrl: _rootsCtrl,
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

  void _startScan(BuildContext context, DuplicateProvider provider) {
    final roots = _rootsCtrl.text
        .split(RegExp(r'[;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (roots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写至少一个扫描目录')),
      );
      return;
    }
    provider.scan(roots);
  }

  Future<void> _confirmAndClean(
    BuildContext context,
    DuplicateProvider provider,
  ) async {
    if (provider.hasUnsafeSelection()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('某组所有副本都被勾选 —— 至少保留一份')),
      );
      return;
    }
    final size = FileSizeFormatter.format(provider.selectedBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清理'),
        content: Text(
          '将处理 ${provider.selectedCount} 个文件 / $size。\n\n'
          '文件会移入回收站，可在系统回收站中恢复。\n'
          '每组至少保留一份未勾选副本。',
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
    required this.rootsCtrl,
    required this.provider,
    required this.onScan,
  });
  final TextEditingController rootsCtrl;
  final DuplicateProvider provider;
  final VoidCallback onScan;

  static const _presets = <int, String>{
    256 * 1024: '≥ 256 KB',
    1024 * 1024: '≥ 1 MB',
    10 * 1024 * 1024: '≥ 10 MB',
    100 * 1024 * 1024: '≥ 100 MB',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = provider.status != DuplicateStatus.scanning &&
        provider.status != DuplicateStatus.cleaning;
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
          TextField(
            controller: rootsCtrl,
            enabled: enabled,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '扫描目录（多个用 ; 或换行分隔）',
              hintText:
                  r'例如：D:\Downloads;D:\Photos 或 C:\Users\me\Documents',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.folder_copy_outlined),
            ),
            onSubmitted: (_) => onScan(),
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
              const Spacer(),
              Text(
                '基于 size 预筛 + SHA1 哈希。小于阈值的文件忽略。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
  final DuplicateProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = provider.progress;
    final text = switch (provider.status) {
      DuplicateStatus.idle =>
        '填好目录后点击"开始扫描"。先按文件大小分桶预筛，再对候选做 SHA1。',
      DuplicateStatus.scanning => '扫描中：'
            '${p == null ? '正在枚举…' : '已索引 ${p.filesIndexed} · '
                '候选 ${p.candidatePairs} · '
                '组 ${p.groupsFound} · '
                '已 hash ${FileSizeFormatter.format(p.bytesHashed)}'}',
      DuplicateStatus.scanned ||
      DuplicateStatus.reported =>
        '${provider.totalGroups} 组 / ${provider.totalDuplicateFiles} 文件 · '
            '可释放 ${FileSizeFormatter.format(provider.reclaimableBytes)}',
      DuplicateStatus.cleaning => '正在清理…',
      DuplicateStatus.error => '出错：${provider.error}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (provider.status == DuplicateStatus.scanning)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (provider.status == DuplicateStatus.scanning)
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (provider.totalGroups > 0) ...[
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
  final DuplicateProvider provider;

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
  final DuplicateProvider provider;

  @override
  Widget build(BuildContext context) {
    final groups = provider.groups;
    if (groups.isEmpty) {
      if (provider.status == DuplicateStatus.scanning) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Text(
          provider.status == DuplicateStatus.idle ? '尚未扫描' : '未发现重复文件',
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
                onPressed: provider.selectKeepFirstInEachGroup,
                icon: const Icon(Icons.first_page, size: 18),
                label: const Text('保留首项'),
              ),
              TextButton.icon(
                onPressed: provider.selectKeepOldestInEachGroup,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('保留最旧'),
              ),
              TextButton.icon(
                onPressed: provider.deselectAll,
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('全不选'),
              ),
              const Spacer(),
              Text(
                '共 ${groups.length} 组',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: groups.length,
            itemBuilder: (ctx, i) {
              return _DuplicateGroupTile(group: groups[i], provider: provider);
            },
          ),
        ),
      ],
    );
  }
}

class _DuplicateGroupTile extends StatelessWidget {
  const _DuplicateGroupTile({required this.group, required this.provider});
  final DuplicateGroup group;
  final DuplicateProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${group.count} 份相同 · '
                  '${FileSizeFormatter.format(group.size)} / 份',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                '可省 ${FileSizeFormatter.format(group.reclaimableBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'SHA1 ${group.hash.substring(0, 12)}…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
          children: [
            for (final path in group.paths)
              ListTile(
                dense: true,
                leading: Checkbox(
                  value: provider.isSelected(path),
                  onChanged: (v) => provider.toggle(path, v),
                ),
                title: Text(
                  path,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: '复制路径',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: path));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制路径'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
