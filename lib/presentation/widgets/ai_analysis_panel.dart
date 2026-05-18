import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ai_provider.dart';

/// AI 分析进度 + 结果面板。
///
/// 作为 modal bottom sheet 弹出，订阅 [AiProvider] 状态实时刷新：
/// 进度日志 → token 用量 → 最终结论 / 错误。
///
/// 同时担任 [AiProvider.consentResolver] 的承载：展示期间任何写工具
/// 调用都会弹端侧 AlertDialog 让用户决定；面板关闭后 resolver 清空。
class AiAnalysisPanel extends StatefulWidget {
  const AiAnalysisPanel({super.key, required this.title});

  final String title;

  static Future<void> show(BuildContext context, {required String title}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ChangeNotifierProvider<AiProvider>.value(
          value: context.read<AiProvider>(),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: AiAnalysisPanel(title: title),
          ),
        );
      },
    );
  }

  @override
  State<AiAnalysisPanel> createState() => _AiAnalysisPanelState();
}

class _AiAnalysisPanelState extends State<AiAnalysisPanel> {
  @override
  void initState() {
    super.initState();
    final ai = context.read<AiProvider>();
    ai.consentResolver = _askConsent;
  }

  @override
  void dispose() {
    // 面板关闭后立刻清空，避免下一次会话误用
    final ai = context.read<AiProvider>();
    if (identical(ai.consentResolver, _askConsent)) {
      ai.consentResolver = null;
    }
    super.dispose();
  }

  Future<bool> _askConsent(String tool, Map<String, Object?> args) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('AI 请求执行写操作'),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '工具：$tool',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                const Text('参数：'),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    args.toString(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '此操作不可撤销前已 AI 引导。删除走回收站，启动项可重新启用；'
                  '但请确认操作目标确实是你想动的。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('允许执行'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AiProvider>(
      builder: (context, ai, _) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (ai.isRunning)
                    IconButton(
                      tooltip: '终止',
                      icon: const Icon(Icons.stop_circle_outlined),
                      onPressed: () => ai.stop(),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (ai.isRunning) ...[
                const SizedBox(height: 4),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              _TokenRow(tokensIn: ai.tokensIn, tokensOut: ai.tokensOut),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._logRows(ai.log),
                      if (ai.finalText != null) ...[
                        const SizedBox(height: 16),
                        _ResultCard(text: ai.finalText!),
                      ],
                      if (ai.error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorCard(message: ai.error!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _logRows(List<String> log) {
    return [
      for (final line in log)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(line, style: const TextStyle(fontFamily: 'monospace')),
        ),
    ];
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.tokensIn, required this.tokensOut});
  final int tokensIn;
  final int tokensOut;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Icon(Icons.bolt, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text('用量', style: style),
        const SizedBox(width: 12),
        Text('in: $tokensIn', style: style),
        const SizedBox(width: 12),
        Text('out: $tokensOut', style: style),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 18),
                const SizedBox(width: 6),
                Text('结论', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(text),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(message, style: TextStyle(color: color))),
          ],
        ),
      ),
    );
  }
}
