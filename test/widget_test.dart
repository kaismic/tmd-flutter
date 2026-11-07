import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmd_prototype/main.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/models/prediction_entry.dart';
import 'package:tmd_prototype/models/transport_state.dart';
import 'package:tmd_prototype/sensor_buffer.dart';
import 'package:tmd_prototype/widgets/current_state_card.dart';
import 'package:tmd_prototype/widgets/history_row.dart';
import 'fakes.dart';

TransportState prediction({int seconds = 1}) {
  final buffer = SensorBuffer();
  final window = buffer.snapshot(
    ClassificationModel.defaultModel,
    Duration(seconds: seconds),
  );
  return TransportState.vehicle(
    VehicleInference(
      window: window,
      collectionId: 1,
      vehicleMode: VehicleMode.train,
      confidence: .85,
    ),
  );
}

void main() {
  testWidgets(
    'early result shows mode, confidence, identity, progress and coverage',
    (tester) async {
      final state = prediction();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CurrentStateCard(state))),
      );
      expect(find.text('Train'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text(ClassificationModel.defaultModel.name), findsOneWidget);
      expect(find.text('Warm-up incomplete · 1/100s'), findsOneWidget);
      expect(find.textContaining('magnetometer: no readings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history preserves early prediction and model identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HistoryRow(PredictionEntry(prediction()))),
      ),
    );
    expect(find.text('Train'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('Warm-up incomplete · 1/100s'), findsOneWidget);
    expect(find.text(ClassificationModel.defaultModel.name), findsOneWidget);
  });

  testWidgets(
    'picker offers both groups, reaches last model and updates selection',
    (tester) async {
      final h = Harness(() => Duration.zero);
      await tester.pumpWidget(
        MaterialApp(home: DetectorPage(orchestrator: h.orchestrator)),
      );
      await tester.tap(find.textContaining('Selected:'));
      await tester.pumpAndSettle();
      expect(find.text('Sydney V1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sydney V2'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Sydney V2'), findsOneWidget);
      final last = find.byKey(ValueKey(ClassificationModel.values.last.id));
      await tester.scrollUntilVisible(
        last,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
        h.orchestrator.selectedModel.id,
        ClassificationModel.values.last.id,
      );
      expect(
        find.text('Selected: ${ClassificationModel.values.last.name}'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await h.activities.close();
    },
  );

  testWidgets(
    'early predictions enter history and remain limited to ten entries',
    (tester) async {
      var now = Duration.zero;
      final h = Harness(() => now);
      await tester.pumpWidget(
        MaterialApp(home: DetectorPage(orchestrator: h.orchestrator)),
      );
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      h.vehicle();
      await tester.pump();
      h.sensors.sample();
      for (var i = 1; i <= 12; i++) {
        now = Duration(seconds: i);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(find.text('10/10'), findsOneWidget);
      expect(find.textContaining('Warm-up incomplete'), findsWidgets);
      expect(h.classifier.predictions.length, 12);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await h.activities.close();
    },
  );

  testWidgets('narrow screen accommodates status details without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness(() => const Duration(seconds: 100));
    await tester.pumpWidget(
      MaterialApp(home: DetectorPage(orchestrator: h.orchestrator)),
    );
    await tester.tap(find.text('Start Detection'));
    await tester.pump();
    h.vehicle();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await h.activities.close();
  });
}
