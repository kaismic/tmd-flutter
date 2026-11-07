import 'dart:math';
import 'dart:typed_data';
import 'models/sensor_reading.dart';

class FeatureExtractor {
  /// First finite vector at each timestamp, population std, float32 rounding.
  /// Missing sensors produce NaNs for the model's fitted imputer. No time padding.
  static List<double> extract(Map<SensorKind, List<SensorReading>> window) {
    final features = <double>[];
    for (final kind in SensorKind.values) {
      final seen = <Duration>{};
      final values = [
        for (final r in window[kind] ?? <SensorReading>[])
          if (r.isFinite && seen.add(r.timestamp))
            sqrt(r.x * r.x + r.y * r.y + r.z * r.z),
      ];
      if (values.isEmpty) {
        features.addAll(
          List.filled(kind == SensorKind.magnetometer ? 3 : 4, double.nan),
        );
        continue;
      }
      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.fold<double>(0, (s, x) => s + (x - mean) * (x - mean)) /
          values.length;
      final low = values.reduce(min), high = values.reduce(max);
      if (kind != SensorKind.magnetometer) features.add(mean);
      features.addAll([sqrt(variance), high - low, low]);
    }
    return List.unmodifiable(Float32List.fromList(features));
  }
}
