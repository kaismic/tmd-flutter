import 'dart:async';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'models/classification_model.dart';
import 'models/inference_mode.dart';
import 'models/transport_state.dart';
import 'sensor_service.dart';
import 'vehicle_classifier.dart';

/// Collection is gated by activity recognition or runs continuously in ONNX-only
/// mode. Both modes share the one-second timer and selected trailing window.
class DetectionOrchestrator {
  DetectionOrchestrator({
    SensorService? sensorService,
    VehicleClassifier? classifier,
    this.activities,
    Future<bool> Function()? requestPermission,
  }) : _sensors = sensorService ?? SensorService(),
       _classifier = classifier ?? VehicleClassifier(),
       _permission = requestPermission ?? _checkAndRequestPermission;

  final SensorService _sensors;
  final VehicleClassifier _classifier;
  final Stream<Activity>? activities;
  final Future<bool> Function() _permission;
  final _states = StreamController<TransportState>.broadcast();
  Stream<TransportState> get stateStream => _states.stream;
  TransportState get currentState => _currentState;
  TransportState _currentState = TransportState.idle;
  StreamSubscription<Activity>? _activitySub;
  Timer? _timer;
  Future<void> _lifecycle = Future.value();
  ClassificationModel _selected = ClassificationModel.defaultModel;
  ClassificationModel get selectedModel => _selected;
  InferenceMode _inferenceMode = InferenceMode.activityRecognitionFirst;
  InferenceMode get inferenceMode => _inferenceMode;
  bool running = false;
  bool inVehicle = false;
  bool _ready = false;
  bool _busy = false;
  bool _disposed = false;
  int _collection = 0;
  int _revision = 0;
  int _startAttempt = 0;
  int? _loadingRevision;
  int? _failedRevision;

  /// Select while stopped; the choice takes effect on the next Start.
  void setInferenceMode(InferenceMode mode) {
    if (_disposed) return;
    if (running) {
      throw StateError('Stop detection before changing inference mode.');
    }
    _inferenceMode = mode;
  }

  void setSelectedModel(ClassificationModel model) {
    if (_disposed) return;
    if (_selected.id == model.id && _failedRevision == null) return;
    _selected = model;
    _revision++;
    _failedRevision = null;
    if (running && inVehicle && _ready) unawaited(_loadSelection());
  }

  Future<void> start() async {
    if (running || _disposed) return;
    running = true;
    final attempt = ++_startAttempt;
    _revision++;
    try {
      if (_inferenceMode == InferenceMode.alwaysOnnx) {
        _startVehicleInference();
        await _lifecycle;
        return;
      }
      final granted = await _permission();
      if (!running || _disposed || attempt != _startAttempt) return;
      if (!granted) {
        running = false;
        _emit(
          const TransportState.error(
            'Activity recognition permission is required.',
          ),
        );
        return;
      }
      _emit(
        const TransportState.activity(
          ActivityType.UNKNOWN,
          null,
          message: 'Waiting for activity recognition',
        ),
      );
      _activitySub =
          (activities ?? FlutterActivityRecognition.instance.activityStream)
              .listen(
                _onActivity,
                onError: (Object _) {
                  if (!running || _disposed || attempt != _startAttempt) return;
                  _leaveVehicle();
                  _emit(
                    const TransportState.activity(
                      ActivityType.UNKNOWN,
                      null,
                      message: 'Activity recognition unavailable',
                    ),
                  );
                },
              );
    } catch (_) {
      if (_disposed || attempt != _startAttempt) return;
      running = false;
      _emit(const TransportState.error('Could not start detection.'));
    }
  }

  void _onActivity(Activity activity) {
    if (!running ||
        _disposed ||
        _inferenceMode != InferenceMode.activityRecognitionFirst) {
      return;
    }
    if (activity.type == ActivityType.IN_VEHICLE) {
      _startVehicleInference();
    } else {
      _leaveVehicle();
      _emit(TransportState.activity(activity.type, activity.confidence));
    }
  }

  void _startVehicleInference() {
    if (inVehicle) return;
    inVehicle = true;
    final collection = ++_collection;
    _revision++;
    _lifecycle = _lifecycle.then((_) async {
      if (!_active(collection)) return;
      try {
        await _sensors.start();
        if (!_active(collection)) return;
        _ready = true;
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_tick()),
        );
        unawaited(_loadSelection());
      } catch (_) {
        if (_active(collection)) {
          _emit(
            TransportState.vehicle(
              _waiting(),
              message: 'Sensor collection unavailable',
            ),
          );
        }
      }
    });
  }

  bool _active(int collection) =>
      !_disposed && running && inVehicle && collection == _collection;

  VehicleInference _waiting() => VehicleInference(
    window: _sensors.snapshot(_selected),
    collectionId: _collection,
  );

  Future<void> _loadSelection() async {
    final revision = _revision, collection = _collection;
    final model = _selected;
    _loadingRevision = revision;
    _emit(TransportState.vehicle(_waiting(), message: 'Loading model…'));
    try {
      await _classifier.load(model);
      if (!_active(collection) || revision != _revision) return;
      _failedRevision = null;
      _emit(
        TransportState.vehicle(
          _waiting(),
          message: 'Waiting for next prediction',
        ),
      );
    } catch (_) {
      if (_active(collection) && revision == _revision) {
        _failedRevision = revision;
        _emit(
          TransportState.vehicle(
            _waiting(),
            message: 'Model could not be loaded. Select it again to retry.',
          ),
        );
      }
    } finally {
      if (_loadingRevision == revision) _loadingRevision = null;
    }
  }

  Future<void> _tick() async {
    if (!running ||
        !inVehicle ||
        !_ready ||
        _busy ||
        _loadingRevision == _revision ||
        _failedRevision == _revision) {
      return;
    }
    final collection = _collection, revision = _revision;
    final model = _selected;
    final window = _sensors.snapshot(model);
    if (!window.hasData) {
      _emit(
        TransportState.vehicle(
          VehicleInference(window: window, collectionId: collection),
          message: 'Waiting for usable sensor readings',
        ),
      );
      return;
    }
    _busy = true;
    try {
      final (mode, confidence) = await _classifier.predict(
        model,
        window.features,
      );
      if (!_active(collection) || revision != _revision) return;
      _emit(
        TransportState.vehicle(
          VehicleInference(
            window: window,
            collectionId: collection,
            vehicleMode: mode,
            confidence: confidence,
          ),
        ),
      );
    } catch (_) {
      if (_active(collection) && revision == _revision) {
        _emit(
          TransportState.vehicle(
            VehicleInference(window: window, collectionId: collection),
            message: 'Prediction unavailable; retrying next second',
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  void _leaveVehicle() {
    if (!inVehicle && !_ready) return;
    inVehicle = false;
    _ready = false;
    _collection++;
    _revision++;
    _timer?.cancel();
    _timer = null;
    _lifecycle = _lifecycle.then((_) async {
      await _sensors.stop();
      await _classifier.close();
    });
  }

  Future<void> stop() async {
    running = false;
    _startAttempt++;
    _revision++;
    _leaveVehicle();
    final subscription = _activitySub;
    _activitySub = null;
    _emit(TransportState.idle);
    await subscription?.cancel();
    await _lifecycle;
  }

  void _emit(TransportState state) {
    if (_disposed || _states.isClosed) return;
    _currentState = state;
    _states.add(state);
  }

  static Future<bool> _checkAndRequestPermission() async {
    var permission = await FlutterActivityRecognition.instance
        .checkPermission();
    if (permission == ActivityPermission.DENIED) {
      permission = await FlutterActivityRecognition.instance
          .requestPermission();
    }
    return permission == ActivityPermission.GRANTED;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _sensors.stop();
    await _classifier.dispose();
    await _states.close();
  }
}
