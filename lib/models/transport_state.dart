import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';

enum VehicleMode { bus, car, train }

/// Snapshot of the detection pipeline at a point in time.
class TransportState {
  bool isRunning = false;
  ActivityType activityType = ActivityType.UNKNOWN;
  ActivityConfidence? activityConfidence;
  VehicleInference? vehicleInference;

  static final TransportState idle = TransportState._idle();

  TransportState._idle();
  TransportState.activity(this.activityType, this.activityConfidence) : isRunning = true;
  TransportState.vehicleInference(this.vehicleInference) : activityType = ActivityType.IN_VEHICLE, isRunning = true;

  String get label => switch (activityType) {
    ActivityType.STILL => 'Still',
    ActivityType.WALKING => 'Walking',
    ActivityType.RUNNING => 'Running',
    ActivityType.ON_BICYCLE => 'Cycling',
    ActivityType.IN_VEHICLE =>
      vehicleInference!.windowFill < 1.0
      ? 'Warming up...'
      : switch (vehicleInference!.vehicleMode) {
        VehicleMode.bus => 'Bus',
        VehicleMode.car => 'Car',
        VehicleMode.train => 'Train',
    },
    ActivityType.UNKNOWN => 'Unknown',
  };

  String get emoji => switch (activityType) {
    ActivityType.STILL => '🧍',
    ActivityType.WALKING => '🚶',
    ActivityType.RUNNING => '🏃',
    ActivityType.ON_BICYCLE => '🚴',
    ActivityType.IN_VEHICLE =>
      vehicleInference!.windowFill < 1.0
      ? '⌛'
      : switch (vehicleInference!.vehicleMode) {
      VehicleMode.bus => '🚌',
      VehicleMode.car => '🚗',
      VehicleMode.train => '🚆',
    },
    ActivityType.UNKNOWN => '❓',
  };
}

class VehicleInference {
  VehicleMode vehicleMode = VehicleMode.bus;
  double confidence = 0.0;
  double windowFill = 0.0;

  VehicleInference(this.vehicleMode, this.confidence, this.windowFill);
}
