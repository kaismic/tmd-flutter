/// Ordered, unscaled float32 input contract shared by both Sydney runs.
const sydneyFeatureNames = [
  'accelerometer#mean',
  'accelerometer#standard_deviation',
  'accelerometer#range',
  'accelerometer#minimum',
  'gyroscope#mean',
  'gyroscope#standard_deviation',
  'gyroscope#range',
  'gyroscope#minimum',
  'magnetometer#standard_deviation',
  'magnetometer#range',
  'magnetometer#minimum',
];

class ClassificationModel {
  const ClassificationModel({
    required this.version,
    required this.sourceRun,
    required this.windowSeconds,
    required this.seed,
  });
  final int version;
  final String sourceRun;
  final int windowSeconds;
  final int seed;
  String get id => 'sydney-v$version-w$windowSeconds-s$seed';
  String get group => 'Sydney V$version';
  String get name => '$group · ${windowSeconds}s · seed $seed';
  String get asset => 'assets/sydney/models/$id.onnx';
  Duration get windowDuration => Duration(seconds: windowSeconds);
  List<String> get featureNames => sydneyFeatureNames;
  List<String> get labels => const ['bus', 'car', 'train'];

  static final values = List<ClassificationModel>.unmodifiable([
    for (final version in [1, 2])
      for (final seconds in [100, 120, 140])
        for (final seed in [42, 43, 44])
          ClassificationModel(
            version: version,
            sourceRun: version == 1
                ? 'sydney-20261007'
                : '20261104T005620Z-3b08cd99',
            windowSeconds: seconds,
            seed: seed,
          ),
  ]);
  static ClassificationModel get defaultModel => values.first;
  static Duration get maximumDuration =>
      values.map((m) => m.windowDuration).reduce((a, b) => a > b ? a : b);
}
