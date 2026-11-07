enum SensorKind {
  accelerometer(30),
  gyroscope(4),
  magnetometer(2);

  const SensorKind(this.minimumHz);
  final int minimumHz;
}

/// Timestamp is monotonic elapsed collection time.
class SensorReading {
  const SensorReading(this.timestamp, this.x, this.y, this.z);
  final Duration timestamp;
  final double x;
  final double y;
  final double z;
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
}
