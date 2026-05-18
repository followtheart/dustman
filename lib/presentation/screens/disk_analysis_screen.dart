import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/edition.dart';
import '../../core/i18n/app_localizations.dart';
import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/disk_node.dart';
import '../providers/disk_treemap_provider.dart';
import '../widgets/ai_action_button.dart';
import '../widgets/treemap_view.dart';

class DiskAnalysisScreen extends StatefulWidget {
  const DiskAnalysisScreen({super.key});

  @override
  State<DiskAnalysisScreen> createState() => _DiskAnalysisScreenState();
}

class _DiskAnalysisScreenState extends State<DiskAnalysisScreen> {
  final _rootCtrl = TextEditingController();
  int _maxDepth = 6;
  DiskNode? _hover;

  @override
  void dispose() {
    _rootCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Consumer<DiskTreemapProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(t.t('disk.title')),
            centerTitle: false,
            actions: [
              if (provider.status == DiskTreemapStatus.scanning)
                FilledButton.tonalIcon(
                  onPressed: provider.cancelScan,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(t.t('common.cancel')),
                )
              else
                FilledButton.icon(
                  onPressed: () => _start(provider, t),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t.t('disk.start')),
                ),
              if (kIsPro)
                IconButton(
                  tooltip: 'AI 解读当前目录',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: provider.current == null
                      ? null
                      : () => _runAi(context, provider.current!),
                ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              _ControlBar(
                rootCtrl: _rootCtrl,
                provider: provider,
                maxDepth: _maxDepth,
                onMaxDepthChanged: (v) => setState(() => _maxDepth = v),
                onStart: () => _start(provider, t),
              ),
              const Divider(height: 1),
              Expanded(child: _buildBody(provider, t)),
              _StatusBar(provider: provider, hover: _hover),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(DiskTreemapProvider provider, AppLocalizations t) {
    switch (provider.status) {
      case DiskTreemapStatus.idle:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pie_chart_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  t.t('disk.rootHint'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  t.t('disk.help'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        );
      case DiskTreemapStatus.scanning:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
              const SizedBox(height: 16),
              Text(t.t('disk.scanning')),
              const SizedBox(height: 8),
              Text(
                provider.currentScanPath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${provider.entriesScanned} ${t.t('disk.entries')} · '
                '${FileSizeFormatter.format(provider.bytesAccumulated)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case DiskTreemapStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(provider.error ?? t.t('common.failed')),
              ],
            ),
          ),
        );
      case DiskTreemapStatus.scanned:
        final current = provider.current;
        if (current == null) return const SizedBox.shrink();
        return Column(
          children: [
            _Breadcrumb(provider: provider, t: t),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TreemapView(
                  root: current,
                  onTap: provider.drillInto,
                  onSecondaryTap: provider.drillUp,
                  hoverPathChanged: (n) => setState(() => _hover = n),
                ),
              ),
            ),
          ],
        );
    }
  }

  void _start(DiskTreemapProvider provider, AppLocalizations t) {
    final root = _rootCtrl.text.trim();
    if (root.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('disk.rootHint'))),
      );
      return;
    }
    provider.scan(root, maxDepth: _maxDepth);
  }

  Future<void> _runAi(BuildContext context, DiskNode node) async {
    final children = (node.children ?? const <DiskNode>[]).take(8).toList();
    await runAiAnalysis(
      context,
      intent: 'summarize_dir',
      title: 'AI 解读：${node.path.split(r'\').last}',
      ctx: {
        'dir': node.path,
        'top_children': [
          for (final c in children)
            {'name': c.path.split(r'\').last, 'size': c.size, 'is_dir': c.isDirectory},
        ],
      },
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.rootCtrl,
    required this.provider,
    required this.maxDepth,
    required this.onMaxDepthChanged,
    required this.onStart,
  });

  final TextEditingController rootCtrl;
  final DiskTreemapProvider provider;
  final int maxDepth;
  final ValueChanged<int> onMaxDepthChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enabled = provider.status != DiskTreemapStatus.scanning;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: rootCtrl,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: t.t('disk.rootLabel'),
                hintText: r'例如 D:\ 或 C:\Users\me\Downloads',
                isDense: true,
                prefixIcon: const Icon(Icons.folder_outlined),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => onStart(),
            ),
          ),
          const SizedBox(width: 12),
          Text('${t.t('disk.depth')}:'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: maxDepth,
            isDense: true,
            onChanged: enabled ? (v) => onMaxDepthChanged(v ?? 6) : null,
            items: const [
              DropdownMenuItem(value: 3, child: Text('3')),
              DropdownMenuItem(value: 4, child: Text('4')),
              DropdownMenuItem(value: 6, child: Text('6')),
              DropdownMenuItem(value: 8, child: Text('8')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.provider, required this.t});
  final DiskTreemapProvider provider;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final stack = provider.breadcrumb;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: scheme.surfaceContainerLowest,
      child: Row(
        children: [
          IconButton(
            tooltip: t.t('disk.zoomOut'),
            onPressed: stack.length > 1 ? provider.drillUp : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: t.t('disk.zoomReset'),
            onPressed: stack.length > 1 ? provider.reset : null,
            icon: const Icon(Icons.home_outlined),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < stack.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 16),
                      ),
                    Text(
                      stack[i].name,
                      style: TextStyle(
                        fontWeight: i == stack.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (provider.current != null) ...[
            const SizedBox(width: 8),
            Text(
              FileSizeFormatter.format(provider.current!.size),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.provider, required this.hover});
  final DiskTreemapProvider provider;
  final DiskNode? hover;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tree = provider.tree;
    String text;
    if (hover != null) {
      text = '${hover!.path}  ·  ${FileSizeFormatter.format(hover!.size)}';
    } else if (tree != null) {
      text = '${t.t('disk.totalSize')} ${FileSizeFormatter.format(tree.size)}  ·  '
          '${provider.entriesScanned} ${t.t('disk.entries')}  ·  '
          '${t.t('disk.elapsed')} ${provider.elapsed.inMilliseconds} ms';
    } else {
      text = t.t('disk.help');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      color: scheme.surfaceContainerLow,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
