import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmd_prototype/feature_extractor.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/models/sensor_reading.dart';
import 'package:tmd_prototype/sensor_buffer.dart';

void fill(SensorBuffer buffer, int startMs, int endMs) {
  for (var ms = startMs; ms < endMs; ms += 20) {
    for (final kind in SensorKind.values) {
      if (kind != SensorKind.accelerometer && ms % 200 != 0) continue;
      buffer.add(kind, SensorReading(Duration(milliseconds: ms), 3, 4, 0));
    }
  }
}

void main() {
  test('exact catalogue, default, source identities and maximum duration', () {
    final models = ClassificationModel.values;
    expect(models.length, 18);
    expect(models.map((m) => m.id).toSet().length, 18);
    expect(ClassificationModel.defaultModel.id, 'sydney-v1-w100-s42');
    expect(ClassificationModel.maximumDuration.inSeconds, 140);
    for (final model in models) {
      expect(
        model.sourceRun,
        model.version == 1 ? 'sydney-20261007' : '20261104T005620Z-3b08cd99',
      );
      expect(model.labels, ['bus', 'car', 'train']);
      expect(model.featureNames.length, 11);
    }
  });

  final cases =
      jsonDecode(File('test/fixtures/features.json').readAsStringSync())
          as List;
  for (final fixture in cases) {
    test('NumPy feature parity: ${fixture['name']}', () {
      final sensors = fixture['sensors'] as Map;
      final input = <SensorKind, List<SensorReading>>{};
      for (final kind in SensorKind.values) {
        input[kind] = [
          for (final row in sensors[kind.name] ?? [])
            SensorReading(
              Duration(milliseconds: (row[0] as num).toInt()),
              (row[1] as num?)?.toDouble() ?? double.nan,
              (row[2] as num?)?.toDouble() ?? double.nan,
              (row[3] as num?)?.toDouble() ?? double.nan,
            ),
        ];
      }
      final actual = FeatureExtractor.extract(input);
      final expected = fixture['features'] as List;
      expect(actual.length, 11);
      for (var i = 0; i < actual.length; i++) {
        if (expected[i] == null) {
          expect(actual[i].isNaN, isTrue);
        } else {
          expect(actual[i], closeTo((expected[i] as num).toDouble(), 1e-6));
        }
      }
    });
  }

  test(
    'early inference has real features without padding and remains cold',
    () {
      final buffer = SensorBuffer();
      fill(buffer, 0, 1000);
      final window = buffer.snapshot(
        ClassificationModel.defaultModel,
        const Duration(seconds: 1),
      );
      expect(window.hasData, isTrue);
      expect(window.features.first, 5);
      expect(window.fill, .01);
      expect(window.isWarm, isFalse);
      expect(() => window.features.add(0), throwsUnsupportedError);
    },
  );

  test(
    'switches slice selected duration and preserve maximum shared window',
    () {
      final buffer = SensorBuffer();
      for (var ms = 0; ms < 200000; ms += 1000) {
        buffer.add(
          SensorKind.accelerometer,
          SensorReading(Duration(milliseconds: ms), ms / 1000, 0, 0),
        );
      }
      final short = ClassificationModel.defaultModel;
      final long = ClassificationModel.values.firstWhere(
        (m) => m.windowSeconds == 140,
      );
      final shortWindow = buffer.snapshot(short, const Duration(seconds: 200));
      final longWindow = buffer.snapshot(long, const Duration(seconds: 200));
      expect(shortWindow.features.first, 149.5); // seconds 100..199
      expect(longWindow.features.first, 129.5); // seconds 60..199
      expect(buffer.length, 140);
      buffer.evict(const Duration(seconds: 341));
      expect(
        buffer.length,
        0,
      ); // expiry also works when sensors stop delivering
    },
  );

  test(
    'warm-up depends on selected duration, sensor rates and boundary gaps',
    () {
      final buffer = SensorBuffer();
      fill(buffer, 0, 100000);
      final short = ClassificationModel.defaultModel;
      final long = ClassificationModel.values.firstWhere(
        (m) => m.windowSeconds == 140,
      );
      expect(
        buffer.snapshot(short, const Duration(seconds: 100)).isWarm,
        isTrue,
      );
      expect(
        buffer.snapshot(long, const Duration(seconds: 100)).isWarm,
        isFalse,
      );
      expect(
        buffer.snapshot(short, const Duration(seconds: 101)).isWarm,
        isFalse,
      );
      fill(buffer, 101000, 202000);
      expect(
        buffer.snapshot(short, const Duration(seconds: 202)).isWarm,
        isTrue,
      );
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.snapshot(short, Duration.zero).hasData, isFalse);
    },
  );

  test(
    'missing and sparse streams never become warm solely through elapsed time',
    () {
      final buffer = SensorBuffer();
      for (var ms = 0; ms < 100000; ms += 1000) {
        buffer.add(
          SensorKind.accelerometer,
          SensorReading(Duration(milliseconds: ms), 1, 0, 0),
        );
      }
      final window = buffer.snapshot(
        ClassificationModel.defaultModel,
        const Duration(seconds: 100),
      );
      expect(window.fill, 1);
      expect(window.isWarm, isFalse);
      expect(window.features.skip(4).every((v) => v.isNaN), isTrue);
      expect(window.coverageIssues, contains('gyroscope: no readings'));
      expect(window.coverageIssues, contains('accelerometer: sparse readings'));
      expect(window.coverageIssues, contains('accelerometer: recording gaps'));
    },
  );

  test('half-open windows exclude future and endpoint readings', () {
    final buffer = SensorBuffer();
    buffer.add(
      SensorKind.accelerometer,
      const SensorReading(Duration.zero, 2, 0, 0),
    );
    buffer.add(
      SensorKind.accelerometer,
      const SensorReading(Duration(seconds: 1), 100, 0, 0),
    );
    expect(
      buffer
          .snapshot(
            ClassificationModel.defaultModel,
            const Duration(seconds: 1),
          )
          .features
          .first,
      2,
    );
  });
}
