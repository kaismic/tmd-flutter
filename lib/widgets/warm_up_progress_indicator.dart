import 'package:flutter/material.dart';
import 'package:tmd_prototype/models/transport_state.dart';

class WarmUpProgressIndicator extends StatelessWidget {
  const WarmUpProgressIndicator(this.state, {super.key});
  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
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
  }
}
