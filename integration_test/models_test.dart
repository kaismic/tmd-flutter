import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/vehicle_classifier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native ONNX parity for all 18 models, including missing features',
    (tester) async {
      final classifier = VehicleClassifier();
      try {
        for (final model in ClassificationModel.values) {
          final fixture =
              jsonDecode(
                    await rootBundle.loadString(
                      'assets/sydney/fixtures/${model.id}.json',
                    ),
                  )
                  as Map;
          await classifier.load(model);
          for (final row in fixture['rows'] as List) {
            final features = (row['input'] as List)
                .map((v) => (v as num?)?.toDouble() ?? double.nan)
                .toList();
            final (mode, confidence) = await classifier.predict(
              model,
              features,
            );
            expect(
              mode.name,
              model.labels[row['label'] as int],
              reason: model.id,
            );
            final expected = (row['probabilities'][row['label']] as num)
                .toDouble();
            expect(
              confidence,
              closeTo(expected, 1e-6 + 1e-5 * expected.abs()),
              reason: model.id,
            );
          }
        }
      } finally {
        await classifier.dispose();
      }
    },
  );
}
