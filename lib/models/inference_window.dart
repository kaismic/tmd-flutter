import 'classification_model.dart';

class InferenceWindow {
  InferenceWindow({
    required this.model,
    required this.capturedAt,
    required this.recordedDuration,
    required List<double> features,
    required List<String> coverageIssues,
  }) : features = List.unmodifiable(features),
       coverageIssues = List.unmodifiable(coverageIssues);
  final ClassificationModel model;
  final Duration capturedAt;
  final Duration recordedDuration;
  final List<double> features;
  final List<String> coverageIssues;
  bool get hasData => features.any((f) => f.isFinite);
  double get fill =>
      (recordedDuration.inMicroseconds / model.windowDuration.inMicroseconds)
          .clamp(0.0, 1.0);
  bool get isWarm => fill == 1 && coverageIssues.isEmpty;
}
