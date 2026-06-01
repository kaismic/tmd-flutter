import 'dart:math';
import 'sensor_reading.dart';

class FeatureExtractor {
  /// Extracts a flat feature vector matching the Python training pipeline exactly.
  /// Output order: [accel#mean, accel#std, accel#min, accel#max,
  ///                gyro#mean,  gyro#std,  gyro#min,  gyro#max,
  ///                linearAccel#mean, ..., magnetometer#mean, ...]
  /// Total: 4 sensors × 4 features = 16 features
  static List<double> extract(List<SensorReading> window) {
    return [
      ..._sensorFeatures(window, (r) => r.accelerometer),
      ..._sensorFeatures(window, (r) => r.gyroscope),
      ..._sensorFeatures(window, (r) => r.linearAccel),
      ..._sensorFeatures(window, (r) => r.magnetometer),
    ];
  }

  /// Computes magnitude of each reading, then returns [mean, std, min, max]
  /// of the magnitude series — exactly matching the Python pipeline.
  static List<double> _sensorFeatures(
    List<SensorReading> window,
    List<double> Function(SensorReading) accessor,
  ) {
    final magnitudes = window.map((r) {
      final v = accessor(r);
      return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    }).toList();
    return _stats(magnitudes);
  }

  static List<double> _stats(List<double> values) {
    if (values.isEmpty) return [0.0, 0.0, 0.0, 0.0];
    final n = values.length;
    final mean = values.reduce((a, b) => a + b) / n;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final std = sqrt(
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n,
    );
    return [mean, std, min, max];
  }
}