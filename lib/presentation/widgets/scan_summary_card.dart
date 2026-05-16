import 'package:flutter/material.dart';

import '../../core/utils/file_size_formatter.dart';

class ScanSummaryCard extends StatelessWidget {
  const ScanSummaryCard({
    super.key,
    required this.totalBytes,
    required this.isBusy,
    required this.hasScanned,
    required this.onScan,
    required this.onClean,
  });

  final int totalBytes;
  final bool isBusy;
  final bool hasScanned;
  final VoidCallback onScan;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasScanned ? '可释放空间' : '准备就绪',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasScanned
                        ? FileSizeFormatter.format(totalBytes)
                        : '点击右侧"开始扫描"了解你的磁盘',
                    style: textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: isBusy ? null : onScan,
              icon: const Icon(Icons.search),
              label: const Text('开始扫描'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: (isBusy || !hasScanned || totalBytes <= 0)
                  ? null
                  : onClean,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('清理选中'),
            ),
          ],
        ),
      ),
    );
  }
}
