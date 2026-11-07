import 'dart:async';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/detection_orchestrator.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/models/inference_window.dart';
import 'package:tmd_prototype/models/inference_mode.dart';
import 'package:tmd_prototype/models/sensor_reading.dart';
import 'package:tmd_prototype/models/transport_state.dart';
import 'package:tmd_prototype/sensor_service.dart';
import 'package:tmd_prototype/vehicle_classifier.dart';

class FakeSensors extends SensorService {
  FakeSensors(this.now);
  final Duration Function() now;
  Duration origin = Duration.zero;
  int starts = 0, stops = 0;
  bool active = false;
  Completer<void>? startGate;
  @override
  bool get isRunning => active;
  @override
  Future<void> start() async {
    starts++;
    origin = now();
    buffer.clear();
    active = true;
    await startGate?.future;
  }

  void sample() {
    for (final kind in SensorKind.values) {
      buffer.add(kind, SensorReading(now() - origin, 3, 4, 0));
    }
  }

  @override
  InferenceWindow snapshot(ClassificationModel model) =>
      buffer.snapshot(model, now() - origin);
  @override
  Future<void> stop() async {
    stops++;
    active = false;
    buffer.clear();
  }
}

class FakeClassifier extends VehicleClassifier {
  final loads = <String>[];
  final predictions = <String>[];
  Completer<void>? loadGate;
  Completer<(VehicleMode, double)>? predictionGate;
  bool failLoad = false, failPredict = false;
  bool closed = false, disposed = false;
  int activePredictions = 0, maximumConcurrent = 0;
  @override
  Future<void> load(ClassificationModel model) async {
    loads.add(model.id);
    await loadGate?.future;
    if (failLoad) throw StateError('load failed');
  }

  @override
  Future<(VehicleMode, double)> predict(
    ClassificationModel model,
    List<double> features,
  ) async {
    predictions.add(model.id);
    activePredictions++;
    if (activePredictions > maximumConcurrent) {
      maximumConcurrent = activePredictions;
    }
    try {
      if (failPredict) throw StateError('prediction failed');
      return await (predictionGate?.future ??
          Future.value((VehicleMode.car, .85)));
    } finally {
      activePredictions--;
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class Harness {
  Harness(
    Duration Function() now, {
    Future<bool> Function()? permission,
    InferenceMode inferenceMode = InferenceMode.activityRecognitionFirst,
  }) : sensors = FakeSensors(now) {
    orchestrator = DetectionOrchestrator(
      sensorService: sensors,
      classifier: classifier,
      activities: activities.stream,
      requestPermission: permission ?? () async => true,
    );
    orchestrator.setInferenceMode(inferenceMode);
    orchestrator.stateStream.listen(states.add);
  }
  final activities = StreamController<Activity>.broadcast();
  final FakeSensors sensors;
  final classifier = FakeClassifier();
  late final DetectionOrchestrator orchestrator;
  final states = <TransportState>[];
  void vehicle() => activities.add(
    const Activity(ActivityType.IN_VEHICLE, ActivityConfidence.HIGH),
  );
  void walking() => activities.add(
    const Activity(ActivityType.WALKING, ActivityConfidence.HIGH),
  );
  Future<void> dispose() async {
    await orchestrator.dispose();
    await activities.close();
  }
}
