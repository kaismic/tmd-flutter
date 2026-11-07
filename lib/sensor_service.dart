import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'models/classification_model.dart';
import 'models/inference_window.dart';
import 'models/sensor_reading.dart';
import 'sensor_buffer.dart';

class SensorService {
  final buffer = SensorBuffer();
  final _clock = Stopwatch();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _lastAccepted = <SensorKind, Duration>{};
  bool get isRunning => _clock.isRunning;

  Future<void> start() async {
    if (isRunning) return;
    buffer.clear();
    _lastAccepted.clear();
    _clock.reset();
    _clock.start();
    try {
      // Register each subscription immediately so partial initialization can
      // still cancel everything if a subsequent sensor cannot be subscribed.
      _subscriptions.add(
        accelerometerEventStream(
          samplingPeriod: const Duration(microseconds: 16667),
        ).listen(
          (e) => _add(SensorKind.accelerometer, e.x, e.y, e.z),
          onError: (Object _) {},
        ),
      );
      _subscriptions.add(
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (e) => _add(SensorKind.gyroscope, e.x, e.y, e.z),
          onError: (Object _) {},
        ),
      );
      _subscriptions.add(
        magnetometerEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (e) => _add(SensorKind.magnetometer, e.x, e.y, e.z),
          onError: (Object _) {},
        ),
      );
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  void _add(SensorKind kind, double x, double y, double z) {
    if (!isRunning) return;
    final now = _clock.elapsed;
    final period = kind == SensorKind.accelerometer
        ? const Duration(microseconds: 16667)
        : const Duration(milliseconds: 200);
    final previous = _lastAccepted[kind];
    // Allow delivery jitter; cap at twice the request to bound buffer memory.
    if (previous != null && now - previous < period ~/ 2) return;
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    _lastAccepted[kind] = now;
    buffer.add(kind, SensorReading(now, x, y, z));
  }

  InferenceWindow snapshot(ClassificationModel model) =>
      buffer.snapshot(model, _clock.elapsed);

  Future<void> stop() async {
    _clock.stop();
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    buffer.clear();
    _lastAccepted.clear();
    try {
      await Future.wait(subscriptions.map((s) => s.cancel()));
    } finally {
      _clock.reset();
    }
  }
}
