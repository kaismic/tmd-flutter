import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/transport_state.dart';
import 'package:tmd_prototype/widgets/confidence_chip.dart';

class CurrentStateCard extends StatelessWidget {
  const CurrentStateCard(this.state, {super.key});
  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final (runningStateLabel, runningStatecolor) = state.isRunning
    //     ? ('Active', theme.colorScheme.primary)
    //     : ('Idle', theme.colorScheme.outline);
    Widget tail;
    if (state.activityType == ActivityType.IN_VEHICLE &&
        state.vehicleInference!.windowFill < 1.0) {
      tail = SizedBox(
        width: 80,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${(state.vehicleInference!.windowFill * 100).toInt()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: state.vehicleInference!.windowFill),
          ],
        ),
      );
    } else {
      tail = ConfidenceChip(state);
    }
    return Card(
      elevation: 0,
      color: state.isRunning
          ? Colors.green.withValues(alpha: 0.25)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Text(state.emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // const SizedBox(height: 2),
                  // Text(
                  //   runningStateLabel,
                  //   style: theme.textTheme.labelSmall?.copyWith(color: runningStatecolor),
                  // ),
                ],
              ),
            ),
            tail,
          ],
        ),
      ),
    );
  }
}
