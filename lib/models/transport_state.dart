import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'inference_window.dart';

enum VehicleMode { bus, car, train }

/// Immutable snapshots keep prediction history independent of subsequent switches.
class TransportState {
  const TransportState._({
    this.isRunning = false,
    this.activityType = ActivityType.UNKNOWN,
    this.activityConfidence,
    this.vehicleInference,
    this.message,
  });
  static const idle = TransportState._();
  const TransportState.activity(
    ActivityType type,
    ActivityConfidence? confidence, {
    String? message,
  }) : this._(
         isRunning: true,
         activityType: type,
         activityConfidence: confidence,
         message: message,
       );
  const TransportState.vehicle(VehicleInference inference, {String? message})
    : this._(
        isRunning: true,
        activityType: ActivityType.IN_VEHICLE,
        vehicleInference: inference,
        message: message,
      );
  const TransportState.error(String message) : this._(message: message);

  final bool isRunning;
  final ActivityType activityType;
  final ActivityConfidence? activityConfidence;
  final VehicleInference? vehicleInference;
  final String? message;
  bool get hasPrediction => vehicleInference?.vehicleMode != null;

  String get label => switch (activityType) {
    ActivityType.STILL => 'Still',
    ActivityType.WALKING => 'Walking',
    ActivityType.RUNNING => 'Running',
    ActivityType.ON_BICYCLE => 'Cycling',
    ActivityType.IN_VEHICLE => switch (vehicleInference?.vehicleMode) {
      VehicleMode.bus => 'Bus',
      VehicleMode.car => 'Car',
      VehicleMode.train => 'Train',
      null => 'In vehicle',
    },
    ActivityType.UNKNOWN => isRunning ? 'Unknown' : 'Detection stopped',
  };

  String get emoji => switch (activityType) {
    ActivityType.STILL => '🧍',
    ActivityType.WALKING => '🚶',
    ActivityType.RUNNING => '🏃',
    ActivityType.ON_BICYCLE => '🚴',
    ActivityType.IN_VEHICLE => switch (vehicleInference?.vehicleMode) {
      VehicleMode.bus => '🚌',
      VehicleMode.car => '🚗',
      VehicleMode.train => '🚆',
      null => '⌛',
    },
    ActivityType.UNKNOWN => '❓',
  };
}

class VehicleInference {
  const VehicleInference({
    required this.window,
    required this.collectionId,
    this.vehicleMode,
    this.confidence,
  });
  final InferenceWindow window;
  final int collectionId;
  final VehicleMode? vehicleMode;
  final double? confidence;
}
