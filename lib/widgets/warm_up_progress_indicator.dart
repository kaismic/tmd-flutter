import 'package:flutter/material.dart';
import '../models/inference_window.dart';

class WarmUpProgressIndicator extends StatelessWidget {
  const WarmUpProgressIndicator(this.window, {super.key});
  final InferenceWindow window;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Warm-up incomplete · ${window.recordedDuration.inSeconds}/${window.model.windowSeconds}s',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: window.fill,
        semanticsLabel: 'Recording duration',
        semanticsValue: '${(window.fill * 100).round()}%',
      ),
      const SizedBox(height: 4),
    ],
  );
}
