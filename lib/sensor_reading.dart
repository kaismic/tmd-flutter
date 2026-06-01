class SensorReading {
  final DateTime timestamp;
  final List<double> accelerometer;   // [x, y, z]
  final List<double> gyroscope;       // [x, y, z]
  final List<double> linearAccel;     // [x, y, z]
  final List<double> magnetometer;    // [x, y, z]
  final double? speed;                // m/s from GPS

  const SensorReading({
    required this.timestamp,
    required this.accelerometer,
    required this.gyroscope,
    required this.linearAccel,
    required this.magnetometer,
    this.speed,
  });
}
