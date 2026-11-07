import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/models/transport_state.dart';
import 'fakes.dart';

void main() {
  void scenario(void Function(FakeAsync, Harness) body) {
    fakeAsync((clock) {
      final h = Harness(() => clock.elapsed);
      unawaited(h.orchestrator.start());
      clock.flushMicrotasks();
      h.vehicle();
      clock.flushMicrotasks();
      h.sensors.sample();
      body(clock, h);
      unawaited(h.dispose());
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  }

  test(
    'one-second predictions start early, with no fabricated warm-up labels',
    () {
      scenario((clock, h) {
        expect(h.states.where((s) => s.hasPrediction), isEmpty);
        clock.elapse(const Duration(milliseconds: 999));
        expect(h.classifier.predictions, isEmpty);
        clock.elapse(const Duration(milliseconds: 1));
        expect(h.classifier.predictions.length, 1);
        expect(h.states.last.label, 'Car');
        expect(h.states.last.vehicleInference!.window.fill, .01);
        clock.elapse(const Duration(seconds: 2));
        expect(h.classifier.predictions.length, 3);
      });
    },
  );

  test(
    'empty sensors show waiting and never run an all-imputed prediction',
    () {
      scenario((clock, h) {
        h.sensors.buffer.clear();
        clock.elapse(const Duration(seconds: 3));
        expect(h.classifier.predictions, isEmpty);
        expect(h.states.last.message, contains('usable sensor'));
        expect(h.states.last.hasPrediction, isFalse);
      });
    },
  );

  test(
    'rapid model changes retain collection and suppress obsolete predictions',
    () {
      scenario((clock, h) {
        final prediction = Completer<(VehicleMode, double)>();
        h.classifier.predictionGate = prediction;
        clock.elapse(const Duration(seconds: 1));
        final model = ClassificationModel.values.last;
        h.orchestrator.setSelectedModel(ClassificationModel.values[3]);
        h.orchestrator.setSelectedModel(model);
        clock.flushMicrotasks();
        prediction.complete((VehicleMode.bus, .9));
        clock.flushMicrotasks();
        expect(h.states.where((s) => s.hasPrediction), isEmpty);
        h.classifier.predictionGate = null;
        clock.elapse(const Duration(seconds: 1));
        expect(h.states.last.vehicleInference!.window.model.id, model.id);
        expect(
          h.states.last.vehicleInference!.window.recordedDuration.inSeconds,
          2,
        );
        expect(h.sensors.starts, 1);
        expect(h.classifier.maximumConcurrent, 1);
      });
    },
  );

  test('load failure is visible and selecting the same model retries', () {
    scenario((clock, h) {
      h.classifier.failLoad = true;
      h.orchestrator.setSelectedModel(ClassificationModel.values.last);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      expect(h.states.last.message, contains('could not be loaded'));
      expect(h.classifier.predictions, isEmpty);
      h.classifier.failLoad = false;
      h.orchestrator.setSelectedModel(ClassificationModel.values.last);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(h.states.last.hasPrediction, isTrue);
    });
  });

  test('slow loading and inference never overlap timer predictions', () {
    scenario((clock, h) {
      final loading = Completer<void>();
      h.classifier.loadGate = loading;
      h.orchestrator.setSelectedModel(ClassificationModel.values.last);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      expect(h.classifier.predictions, isEmpty);
      loading.complete();
      clock.flushMicrotasks();
      final prediction = Completer<(VehicleMode, double)>();
      h.classifier.predictionGate = prediction;
      clock.elapse(const Duration(seconds: 3));
      expect(h.classifier.predictions.length, 1);
      prediction.complete((VehicleMode.car, .8));
      clock.flushMicrotasks();
    });
  });

  test(
    'vehicle exit clears collection and suppresses in-flight completion',
    () {
      scenario((clock, h) {
        final prediction = Completer<(VehicleMode, double)>();
        h.classifier.predictionGate = prediction;
        clock.elapse(const Duration(seconds: 1));
        h.walking();
        clock.flushMicrotasks();
        prediction.complete((VehicleMode.train, .9));
        clock.flushMicrotasks();
        expect(h.states.last.activityType, ActivityType.WALKING);
        expect(h.sensors.buffer.length, 0);
        expect(h.classifier.closed, isTrue);
        clock.elapse(const Duration(seconds: 2));
        expect(h.classifier.predictions.length, 1);
        h.classifier.predictionGate = null;
        h.vehicle();
        clock.flushMicrotasks();
        h.sensors.sample();
        clock.elapse(const Duration(seconds: 1));
        expect(h.sensors.starts, 2);
        expect(
          h.states.last.vehicleInference!.window.recordedDuration.inSeconds,
          1,
        );
      });
    },
  );

  test('stop and restart invalidate old predictions and timers', () {
    scenario((clock, h) {
      final prediction = Completer<(VehicleMode, double)>();
      h.classifier.predictionGate = prediction;
      clock.elapse(const Duration(seconds: 1));
      unawaited(h.orchestrator.stop());
      clock.flushMicrotasks();
      prediction.complete((VehicleMode.train, .9));
      clock.flushMicrotasks();
      expect(h.states.last.isRunning, isFalse);
      unawaited(h.orchestrator.start());
      clock.flushMicrotasks();
      h.classifier.predictionGate = null;
      h.vehicle();
      clock.flushMicrotasks();
      h.sensors.sample();
      clock.elapse(const Duration(seconds: 1));
      expect(h.states.last.label, 'Car');
      expect(clock.periodicTimerCount, 1);
    });
  });

  test('prediction errors replace the old result and recover next tick', () {
    scenario((clock, h) {
      clock.elapse(const Duration(seconds: 1));
      h.classifier.failPredict = true;
      clock.elapse(const Duration(seconds: 1));
      expect(h.states.last.hasPrediction, isFalse);
      expect(h.states.last.message, contains('retrying'));
      h.classifier.failPredict = false;
      clock.elapse(const Duration(seconds: 1));
      expect(h.states.last.hasPrediction, isTrue);
    });
  });

  test(
    'model changes while permission is pending do not prevent subscription',
    () {
      fakeAsync((clock) {
        final permission = Completer<bool>();
        final h = Harness(
          () => clock.elapsed,
          permission: () => permission.future,
        );
        unawaited(h.orchestrator.start());
        h.orchestrator.setSelectedModel(ClassificationModel.values.last);
        permission.complete(true);
        clock.flushMicrotasks();
        h.vehicle();
        clock.flushMicrotasks();
        expect(h.sensors.starts, 1);
        unawaited(h.dispose());
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'permission denial leaves detection stopped with an explanation',
    () async {
      final h = Harness(() => Duration.zero, permission: () async => false);
      await h.orchestrator.start();
      expect(h.orchestrator.running, isFalse);
      expect(h.orchestrator.currentState.message, contains('permission'));
      await h.dispose();
    },
  );
}
