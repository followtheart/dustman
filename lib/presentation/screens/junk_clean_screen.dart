import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/junk_item.dart';
import '../providers/scan_provider.dart';
import '../widgets/junk_category_tile.dart';
import '../widgets/scan_summary_card.dart';

class JunkCleanScreen extends StatelessWidget {
  const JunkCleanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('垃圾清理'),
        centerTitle: false,
      ),
      body: Consumer<ScanProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScanSummaryCard(
                  totalBytes: provider.totalReclaimableBytes,
                  isBusy: provider.isBusy,
                  hasScanned: provider.hasAnyScanned,
                  onScan: provider.scanAll,
                  onClean: () => _confirmAndClean(context, provider),
                ),
                const SizedBox(height: 24),
                Text(
                  '清理分类',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                for (final entry in provider.states.entries) ...[
                  JunkCategoryTile(
                    state: entry.value,
                    onToggle: (v) =>
                        provider.toggleSelection(entry.key, v),
                  ),
                  const SizedBox(height: 8),
                ],
                if (provider.lastReport != null) ...[
                  const SizedBox(height: 16),
                  _ReportCard(report: provider.lastReport!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmAndClean(
      BuildContext context, ScanProvider provider) async {
    final size = FileSizeFormatter.format(provider.totalReclaimableBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清理'),
        content: Text(
          '将释放约 $size 空间，删除操作不可撤销（回收站类别例外）。是否继续？',
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

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final CleanReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  '清理完成',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '已释放 ${FileSizeFormatter.format(report.bytesFreed)}，'
              '删除 ${report.itemsDeleted} 项，'
              '失败 ${report.failures.length} 项。',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
