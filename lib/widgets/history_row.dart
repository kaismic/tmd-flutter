
import 'package:flutter/material.dart';
import 'package:tmd_prototype/models/prediction_entry.dart';
import 'package:tmd_prototype/widgets/confidence_chip.dart';

class HistoryRow extends StatelessWidget {
  final PredictionEntry entry;
  const HistoryRow(this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = entry.state;
    final t = entry.timestamp;
    final timeLabel =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          // SizedBox(
          //   width: 24,
          //   child: Text(
          //     '${index + 1}',
          //     style: theme.textTheme.labelSmall?.copyWith(
          //       color: theme.colorScheme.outline,
          //     ),
          //   ),
          // ),
          Text(state.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: ConfidenceChip(state)
          ),
          const SizedBox(width: 8),
          Text(
            timeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}