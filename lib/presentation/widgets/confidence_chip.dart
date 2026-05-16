import 'package:flutter/material.dart';

import '../../domain/entities/residue_item.dart';

class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidence});

  final ResidueConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, label) = switch (confidence) {
      ResidueConfidence.high => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          '高信心',
        ),
      ResidueConfidence.medium => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          '中信心',
        ),
      ResidueConfidence.low => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          '低信心',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
