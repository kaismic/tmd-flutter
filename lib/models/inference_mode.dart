enum InferenceMode {
  activityRecognitionFirst(
    'Activity recognition first',
    'Use activity recognition, then classify bus, car or train when in a vehicle.',
  ),
  alwaysOnnx(
    'Always use ONNX',
    'Assume a vehicle and continuously classify bus, car or train while detection runs.',
  );

  const InferenceMode(this.label, this.description);
  final String label;
  final String description;
}
