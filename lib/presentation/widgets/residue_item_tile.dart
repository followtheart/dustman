import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/residue_item.dart';
import 'confidence_chip.dart';

class ResidueItemTile extends StatelessWidget {
  const ResidueItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
    this.onAnalyze,
  });

  final ResidueItem item;
  final bool selected;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onRemove;

  /// 仅 Pro 版传入；为 null 时不渲染 ✦ 按钮。
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        // 折叠面板默认带分割线，去掉以贴合卡片
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.only(left: 4, right: 12, top: 4, bottom: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(56, 0, 16, 12),
          leading: Checkbox(
            value: selected,
            onChanged: onToggle,
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.path,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FileSizeFormatter.format(item.size),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  ConfidenceChip(confidence: item.confidence),
                ],
              ),
              if (onAnalyze != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'AI 分析',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: onAnalyze,
                ),
              ],
              const SizedBox(width: 4),
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
                  PopupMenuItem(
                    value: _TileAction.copy,
                    child: Text('复制路径'),
                  ),
                  PopupMenuItem(
                    value: _TileAction.remove,
                    child: Text('从清理列表移除'),
                  ),
                ],
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.reason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.8),
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          children: [
            if (item.evidence.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '证据',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  for (final ev in item.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('· '),
                          Expanded(
                            child: Text(
                              ev,
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _TileAction { copy, remove }
