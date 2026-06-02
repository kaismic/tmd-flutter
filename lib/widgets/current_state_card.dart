import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/models/transport_state.dart';
import 'package:tmd_prototype/widgets/confidence_chip.dart';
import 'package:tmd_prototype/widgets/warm_up_progress_indicator.dart';

class CurrentStateCard extends StatelessWidget {
  const CurrentStateCard(this.state, {super.key});
  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: state.isRunning
          ? Colors.green.withValues(alpha: 0.25)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: state.isRunning
          ? Row(
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
                    )
                  ],
                ),
              ),
              state.activityType == ActivityType.IN_VEHICLE && state.vehicleInference!.windowFill < 1.0
              ? WarmUpProgressIndicator(state) : ConfidenceChip(state),
            ],
          ) : const SizedBox(height: 50),
      ),
    );
  }
}
