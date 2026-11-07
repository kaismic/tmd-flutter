import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmd_prototype/models/classification_model.dart';
import 'package:tmd_prototype/models/transport_state.dart';
import 'package:tmd_prototype/vehicle_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_onnxruntime');
  final actions = <String>[];
  Completer<void>? gate;
  Completer<void>? entered;
  var failDecode = false;
  late VehicleClassifier classifier;

  setUp(() {
    actions.clear();
    gate = null;
    entered = null;
    failDecode = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'createOrtValue':
              expect(args['sourceType'], 'float32');
              expect(args['shape'], [1, 11]);
              return {
                'valueId': 'input',
                'dataType': 'float32',
                'shape': [1, 11],
              };
            case 'runInference':
              actions.add('run');
              entered?.complete();
              await gate?.future;
              return {
                'label': [
                  'label',
                  'int64',
                  [1],
                ],
                'probabilities': [
                  'probs',
                  'float32',
                  [1, 3],
                ],
              };
            case 'getOrtValueData':
              if (failDecode) throw PlatformException(code: 'decode');
              return {
                'data': args['valueId'] == 'label' ? [1] : [.1, .8, .1],
              };
            case 'releaseOrtValue':
              actions.add('release:${args['valueId']}');
              return null;
            case 'closeSession':
              actions.add('close:${args['sessionId']}');
              return null;
            default:
              throw StateError(call.method);
          }
        });
    classifier = VehicleClassifier(
      sessionFactory: (model) async {
        actions.add('load:${model.id}');
        return OrtSession.fromMap({
          'sessionId': model.id,
          'inputNames': ['features'],
          'outputNames': ['label', 'probabilities'],
        });
      },
    );
  });
  tearDown(() async {
    await classifier.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'native queue waits for prediction and tensor release before changing or closing sessions',
    () async {
      final first = ClassificationModel.values.first,
          last = ClassificationModel.values.last;
      gate = Completer<void>();
      entered = Completer<void>();
      final prediction = classifier.predict(first, List.filled(11, 1));
      await entered!.future;
      final load = classifier.load(last);
      final close = classifier.close();
      expect(actions, ['load:${first.id}', 'run']);
      gate!.complete();
      expect(await prediction, (VehicleMode.car, .8));
      await load;
      await close;
      final releases = actions.where((a) => a.startsWith('release:')).toSet();
      expect(releases, {'release:input', 'release:label', 'release:probs'});
      expect(
        actions.indexOf('load:${last.id}'),
        greaterThan(actions.indexOf('release:probs')),
      );
      expect(
        actions,
        containsAllInOrder([
          'close:${first.id}',
          'load:${last.id}',
          'close:${last.id}',
        ]),
      );
    },
  );

  test(
    'decode failure releases input and every output, and queue recovers',
    () async {
      failDecode = true;
      await expectLater(
        classifier.predict(
          ClassificationModel.defaultModel,
          List.filled(11, 1),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(actions.where((a) => a.startsWith('release:')).length, 3);
      failDecode = false;
      expect(
        await classifier.predict(
          ClassificationModel.defaultModel,
          List.filled(11, 1),
        ),
        (VehicleMode.car, .8),
      );
    },
  );

  test(
    'failed native load can be retried without poisoning the operation queue',
    () async {
      await classifier.dispose();
      var attempts = 0;
      classifier = VehicleClassifier(
        sessionFactory: (model) async {
          if (++attempts == 1) throw StateError('unavailable');
          return OrtSession.fromMap({
            'sessionId': model.id,
            'inputNames': ['features'],
            'outputNames': ['label', 'probabilities'],
          });
        },
      );
      await expectLater(
        classifier.load(ClassificationModel.defaultModel),
        throwsStateError,
      );
      expect(
        await classifier.predict(
          ClassificationModel.defaultModel,
          List.filled(11, 1),
        ),
        (VehicleMode.car, .8),
      );
    },
  );
}
