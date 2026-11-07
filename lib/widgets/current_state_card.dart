import 'package:flutter/material.dart';
import '../models/transport_state.dart';
import 'confidence_chip.dart';
import 'warm_up_progress_indicator.dart';

class CurrentStateCard extends StatelessWidget {
  const CurrentStateCard(this.state, {super.key});
  final TransportState state;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inference = state.vehicleInference;
    return Card(
      elevation: 0,
      color: state.isRunning
          ? Colors.green.withValues(alpha: 0.15)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(state.emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(state.label, style: theme.textTheme.titleLarge),
                ),
                if (state.hasPrediction || state.activityConfidence != null)
                  ConfidenceChip(state),
              ],
            ),
            if (inference != null) ...[
              const SizedBox(height: 8),
              Text(
                inference.window.model.name,
                style: theme.textTheme.labelMedium,
              ),
              if (!inference.window.isWarm) ...[
                const SizedBox(height: 8),
                WarmUpProgressIndicator(inference.window),
                if (inference.window.coverageIssues.isNotEmpty)
                  Text(
                    inference.window.coverageIssues.join('; '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(state.message!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
