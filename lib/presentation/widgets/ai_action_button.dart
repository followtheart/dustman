import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ai_provider.dart';
import 'ai_analysis_panel.dart';

/// 启动 FileClaw AI 分析的统一入口。
///
/// 6 个功能页用同一份 helper 触发：构造 ctx → AiProvider.start → 弹 [AiAnalysisPanel]。
/// 调用方仅在 kIsPro 分支引用本函数。
Future<void> runAiAnalysis(
  BuildContext context, {
  required String intent,
  required Map<String, Object?> ctx,
  required String title,
}) async {
  final ai = context.read<AiProvider>();
  await ai.start(intent: intent, ctx: ctx);
  if (!context.mounted) return;
  await AiAnalysisPanel.show(context, title: title);
}

/// 一个统一的 ✦ 图标按钮，用于行尾 / 工具栏。
class AiSparkleButton extends StatelessWidget {
  const AiSparkleButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.auto_awesome_outlined),
      onPressed: onPressed,
    );
  }
}
