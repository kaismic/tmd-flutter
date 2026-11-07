import 'package:flutter/material.dart';
import '../models/prediction_entry.dart';
import 'confidence_chip.dart';

class HistoryRow extends StatelessWidget {
  const HistoryRow(this.entry, {super.key});
  final PredictionEntry entry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = entry.state, inference = state.vehicleInference;
    final t = entry.timestamp;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Text(state.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (inference != null) ...[
                  Text(
                    inference.window.model.name,
                    style: theme.textTheme.labelSmall,
                  ),
                  if (!inference.window.isWarm)
                    Text(
                      'Warm-up incomplete · ${inference.window.recordedDuration.inSeconds}/${inference.window.model.windowSeconds}s',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ],
            ),
          ),
          ConfidenceChip(state),
          const SizedBox(width: 8),
          Text(
            time,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
