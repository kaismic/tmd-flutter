import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/models/transport_state.dart';

class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.state, {super.key});
  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color dark;
    Color light;
    String text;
    if (state.activityType == ActivityType.IN_VEHICLE) {
      (dark, light) = state.vehicleInference!.confidence >= 0.8
          ? (Colors.green.shade700, Colors.green.shade100)
          : state.vehicleInference!.confidence >= 0.5
          ? (Colors.orange.shade700, Colors.orange.shade100)
          : (Colors.red.shade700, Colors.red.shade100);
      text = (state.vehicleInference!.confidence * 100).toInt().toString();
    } else {
      if (state.activityConfidence != null) {
        switch (state.activityConfidence!) {
          case ActivityConfidence.HIGH:
            (dark, light) = (Colors.green.shade700, Colors.green.shade100);
            text = 'High';
            break;
          case ActivityConfidence.MEDIUM:
            (dark, light) = (Colors.orange.shade700, Colors.orange.shade100);
            text = 'Medium';
            break;
          case ActivityConfidence.LOW:
            (dark, light) = (Colors.red.shade700, Colors.red.shade100);
            text = 'Low';
            break;
        }
      } else {
        (dark, light) = (Colors.grey.shade700, Colors.grey.shade100);
        text = '-';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: light),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: light,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
