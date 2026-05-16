import 'package:flutter/material.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/junk_category.dart';
import '../providers/scan_provider.dart';

class JunkCategoryTile extends StatelessWidget {
  const JunkCategoryTile({
    super.key,
    required this.state,
    required this.onToggle,
  });

  final CategoryState state;
  final ValueChanged<bool?> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = state.type;
    final isScanned = state.status == CategoryStatus.scanned;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: state.selected,
              onChanged: isScanned && state.totalBytes > 0 ? onToggle : null,
            ),
            const SizedBox(width: 4),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(type.icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 130, child: _trailing(context)),
          ],
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    switch (state.status) {
      case CategoryStatus.idle:
        return Align(
          alignment: Alignment.centerRight,
          child: Text('待扫描',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey)),
        );
      case CategoryStatus.scanning:
        return const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case CategoryStatus.cleaning:
        return Align(
          alignment: Alignment.centerRight,
          child: Text('清理中…', style: textTheme.bodySmall),
        );
      case CategoryStatus.error:
        return Tooltip(
          message: state.error ?? '未知错误',
          child: const Align(
            alignment: Alignment.centerRight,
            child: Icon(Icons.error_outline, color: Colors.redAccent),
          ),
        );
      case CategoryStatus.scanned:
        return Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FileSizeFormatter.format(state.totalBytes),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${state.items.length} 项',
                style: textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        );
    }
  }
}
