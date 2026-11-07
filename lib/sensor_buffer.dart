import 'dart:collection';
import 'feature_extractor.dart';
import 'models/classification_model.dart';
import 'models/inference_window.dart';
import 'models/sensor_reading.dart';

/// One shared time-bounded buffer, independent of the selected model.
class SensorBuffer {
  SensorBuffer({Duration? retention})
    : retention = retention ?? ClassificationModel.maximumDuration;
  final Duration retention;
  final _samples = {
    for (final kind in SensorKind.values) kind: ListQueue<SensorReading>(),
  };
  int get length => _samples.values.fold(0, (n, samples) => n + samples.length);

  void add(SensorKind kind, SensorReading reading) {
    if (!reading.isFinite) return;
    final samples = _samples[kind]!;
    if (samples.isNotEmpty && reading.timestamp < samples.last.timestamp) {
      throw ArgumentError('Sensor timestamps must be ordered');
    }
    samples.addLast(reading);
    evict(reading.timestamp);
  }

  void evict(Duration now) {
    final cutoff = now - retention;
    for (final samples in _samples.values) {
      while (samples.isNotEmpty && samples.first.timestamp < cutoff) {
        samples.removeFirst();
      }
    }
  }

  InferenceWindow snapshot(ClassificationModel model, Duration now) {
    evict(now);
    final start = now - model.windowDuration;
    final window = <SensorKind, List<SensorReading>>{};
    final issues = <String>[];
    for (final kind in SensorKind.values) {
      final samples = _samples[kind]!
          .where((r) => r.timestamp >= start && r.timestamp < now)
          .toList();
      window[kind] = samples;
      if (samples.isEmpty) {
        issues.add('${kind.name}: no readings');
        continue;
      }
      if (samples.length < kind.minimumHz * model.windowSeconds) {
        issues.add('${kind.name}: sparse readings');
      }
      var previous = start;
      var hasGap = false;
      for (final sample in samples) {
        if (sample.timestamp - previous > const Duration(milliseconds: 500)) {
          hasGap = true;
        }
        previous = sample.timestamp;
      }
      if (now - previous > const Duration(milliseconds: 500)) hasGap = true;
      if (hasGap) issues.add('${kind.name}: recording gaps');
    }
    return InferenceWindow(
      model: model,
      capturedAt: now,
      recordedDuration: now < model.windowDuration ? now : model.windowDuration,
      features: FeatureExtractor.extract(window),
      coverageIssues: issues,
    );
  }

  void clear() {
    for (final samples in _samples.values) {
      samples.clear();
    }
  }
}
