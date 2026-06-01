import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'sensor_service.dart';
import 'vehicle_classifier.dart';
import 'transport_state.dart';

/// Coordinates between [FlutterActivityRecognition] and the ONNX inference
/// pipeline.
///
/// Behaviour:
///   - Activity recognition runs continuously in the background.
///   - Non-vehicle activities are
///     passed straight through to [stateStream] using [DetectionSource.activityRecognition].
///   - When IN_VEHICLE is detected, [SensorService] starts collecting data
///     and [VehicleClassifier] fires every second on the sliding window.
///   - When the activity leaves IN_VEHICLE, [SensorService] is stopped and
///     ONNX inference halts immediately.
class DetectionOrchestrator {
  DetectionOrchestrator({
    SensorService? sensorService,
    VehicleClassifier? classifier,
  }) : _sensorService =
           sensorService ??
           SensorService(
             windowDuration: const Duration(seconds: 10),
             samplingInterval: const Duration(milliseconds: 50),
             inferenceInterval: const Duration(seconds: 1),
           ),
       _classifier = classifier ?? VehicleClassifier();

  final SensorService _sensorService;
  final VehicleClassifier _classifier;

  final _stateController = StreamController<TransportState>.broadcast();
  Stream<TransportState> get stateStream => _stateController.stream;

  StreamSubscription<Activity>? _activitySub;
  StreamSubscription<List<double>>? _featureSub;
  StreamSubscription<double>? _fillSub;

  bool _inVehicle = false;
  bool _running = false;

  ClassificationModel get selectedModel => _classifier.selected;

  void setSelectedModel(ClassificationModel cm) {
    _classifier.selected = cm;
  }

  /// Start the orchestrator. Activity recognition begins immediately.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _classifier.load();
    await _subscribeActivityStream();
  }

  /// Stop everything — activity recognition, sensor collection, inference.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _activitySub?.cancel();
    _activitySub = null;
    await _stopVehicleInference();
    _emit(TransportState.idle);
  }

  // ── Activity recognition callback ──────────────────────────────────────

  void _onActivity(Activity activity) {
    final isVehicle = activity.type == ActivityType.IN_VEHICLE;

  // TODO uncomment after testing
    // if (isVehicle && !_inVehicle) {
    //   // Transitioned INTO a vehicle — start ONNX pipeline
    //   _inVehicle = true;
    //   _startVehicleInference();
    // }
    // if (!isVehicle) {
    //   if (_inVehicle) {
    //     // Left the vehicle — stop ONNX pipeline
    //     _inVehicle = false;
    //     _stopVehicleInference();
    //   }
    //   _emit(TransportState.activity(activity.type, activity.confidence));
    // }
    // If still in vehicle, let the ONNX inference stream drive the UI.
  }

  void _onActivityError(Object error) {
    // Activity recognition failure — fall back to unknown
    debugPrint(StackTrace.current.toString());
    debugPrint(error.runtimeType.toString());
    debugPrint(error.toString());
    _emit(TransportState.activity(ActivityType.UNKNOWN, null));
  }

  // ── ONNX inference pipeline ────────────────────────────────────────────

  Future<void> _startVehicleInference() async {
    // Show IN_VEHICLE immediately while the window warms up

    await _sensorService.start();

    // Track window fill progress
    _fillSub = _sensorService.windowFillStream.listen((fill) {
      _emit(
        TransportState.vehicleInference(
          VehicleInference(VehicleMode.bus, 0.0, fill),
        ),
      );
    });

    // Run inference on each emitted feature vector
    _featureSub = _sensorService.featureStream.listen((features) async {
      final (vehicleMode, confidence) = await _classifier.predict(features);
      _emit(
        TransportState.vehicleInference(
          VehicleInference(vehicleMode, confidence, 1.0),
        ),
      );
    });
  }

  Future<void> _stopVehicleInference() async {
    await _featureSub?.cancel();
    await _fillSub?.cancel();
    _featureSub = null;
    _fillSub = null;
    _sensorService.stop();
  }

  Future<void> _subscribeActivityStream() async {
    final granted = await _checkAndRequestPermission();
    if (granted) {
      _activitySub = FlutterActivityRecognition.instance.activityStream
          .handleError(_onActivityError)
          .listen(_onActivity);
    }
  }

// TODO remove after testing
  /// Forces the vehicle inference pipeline to start immediately,
  /// bypassing activity recognition. Remove before release.
  Future<void> debugStartVehicleInference() async {
    if (!_running) await start();
    if (!_inVehicle) {
      _inVehicle = true;
      await _startVehicleInference();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _emit(TransportState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<bool> _checkAndRequestPermission() async {
    ActivityPermission permission = await FlutterActivityRecognition.instance
        .checkPermission();
    if (permission == ActivityPermission.PERMANENTLY_DENIED) {
      return false;
    } else if (permission == ActivityPermission.DENIED) {
      permission = await FlutterActivityRecognition.instance
          .requestPermission();
      if (permission != ActivityPermission.GRANTED) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    stop();
    _stateController.close();
    _classifier.dispose();
    _sensorService.dispose();
  }
}
