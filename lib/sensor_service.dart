import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
// import 'package:geolocator/geolocator.dart';
import 'sensor_reading.dart';
import 'feature_extractor.dart';

/// Collects raw sensor data into a sliding window and emits a computed
/// feature vector on a fixed [inferenceInterval].
///
/// Window behaviour:
///   - Raw samples are collected at [samplingInterval] (default 50ms = 20Hz).
///   - The window holds the last [windowDuration] of samples.
///   - Every [inferenceInterval], features are extracted from
///     the full window and emitted via [featureStream].
///
/// This means inference always operates on a rolling window of recent data
/// rather than waiting for a full non-overlapping window to accumulate.
class SensorService {
  SensorService({
    this.windowDuration = const Duration(seconds: 5),
    this.samplingInterval = const Duration(milliseconds: 50),
    this.inferenceInterval = const Duration(seconds: 2),
  });

  final Duration windowDuration;
  final Duration samplingInterval;
  final Duration inferenceInterval;

  // Current latest values for each sensor stream
  List<double> _accel = [0, 0, 0];
  List<double> _gyro = [0, 0, 0];
  List<double> _linearAccel = [0, 0, 0];
  List<double> _magnetometer = [0, 0, 0];
  double? _speed;

  // Circular buffer of raw readings
  final List<SensorReading> _window = [];

  // Active stream subscriptions
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _samplingTimer;
  Timer? _inferenceTimer;

  // Emits a feature vector each inference interval, once the window is full
  final _featureController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get featureStream => _featureController.stream;

  // Emits the current window size for UI feedback (0.0 → 1.0)
  final _windowFillController = StreamController<double>.broadcast();
  Stream<double> get windowFillStream => _windowFillController.stream;

  bool get isRunning => _samplingTimer != null;
  bool _isWindowFilled = false;

  int get _maxSamples =>
      windowDuration.inMilliseconds ~/ samplingInterval.inMilliseconds;

  Future<void> start() async {
    if (isRunning) return;

    // await _checkLocationPermission();

    // Subscribe to each sensor stream — only update the latest value
    _subscriptions.addAll([
      accelerometerEventStream().listen((e) => _accel = [e.x, e.y, e.z]),
      gyroscopeEventStream().listen((e) => _gyro = [e.x, e.y, e.z]),
      userAccelerometerEventStream().listen(
        (e) => _linearAccel = [e.x, e.y, e.z],
      ),
      magnetometerEventStream().listen((e) => _magnetometer = [e.x, e.y, e.z]),
    ]);

    // // GPS — ~1Hz update, negative speed means invalid reading
    // _subscriptions.add(
    //   Geolocator.getPositionStream(
    //     locationSettings: const LocationSettings(
    //       accuracy: LocationAccuracy.high,
    //       distanceFilter: 0,
    //     ),
    //   ).listen((pos) => _speed = pos.speed < 0 ? 0.0 : pos.speed),
    // );

    // Sampling timer — snapshot all sensor values at fixed rate
    _samplingTimer = Timer.periodic(samplingInterval, (_) => _snapshot());

    // Inference timer — extract features from the current window every second
    _inferenceTimer = Timer.periodic(inferenceInterval, (_) => _emitFeatures());
  }

  void _snapshot() {
    _window.add(
      SensorReading(
        timestamp: DateTime.now(),
        accelerometer: List.unmodifiable(_accel),
        gyroscope: List.unmodifiable(_gyro),
        linearAccel: List.unmodifiable(_linearAccel),
        magnetometer: List.unmodifiable(_magnetometer),
        speed: _speed,
      ),
    );

    // Evict samples older than windowDuration (sliding window)
    if (_window.length > _maxSamples) {
      _window.removeRange(0, _window.length - _maxSamples);
    }

    // Emit fill progress for UI if not filled yet
    final fill = (_window.length / _maxSamples).clamp(0.0, 1.0);
    if (!_isWindowFilled) {
      _windowFillController.add(fill);
      if (fill == 1.0) {
        _isWindowFilled = true;
      }
    }
  }

  void _emitFeatures() {
    if (_window.length < _maxSamples) return;

    final features = FeatureExtractor.extract(List.unmodifiable(_window));
    _featureController.add(features);
  }

  void stop() {
    _samplingTimer?.cancel();
    _inferenceTimer?.cancel();
    _samplingTimer = null;
    _inferenceTimer = null;
    _isWindowFilled = false;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _window.clear();
  }

  // Future<void> _checkLocationPermission() async {
  //   LocationPermission permission = await Geolocator.checkPermission();
  //   if (permission == LocationPermission.denied) {
  //     permission = await Geolocator.requestPermission();
  //   }
  // }

  void dispose() {
    stop();
    _featureController.close();
    _windowFillController.close();
  }
}
