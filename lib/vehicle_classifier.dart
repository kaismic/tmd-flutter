import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'models/classification_model.dart';
import 'models/transport_state.dart';

/// All native operations share one queue, including close and model changes.
class VehicleClassifier {
  VehicleClassifier({
    Future<OrtSession> Function(ClassificationModel)? sessionFactory,
  }) : _sessionFactory = sessionFactory ?? _createSession;
  final Future<OrtSession> Function(ClassificationModel) _sessionFactory;

  static Future<OrtSession> _createSession(ClassificationModel model) async {
    // Preparation writes this marker only after all source/export parity passes.
    // A partial bundle must fail visibly instead of loading leftover model files.
    final manifest =
        jsonDecode(await rootBundle.loadString('assets/sydney/manifest.json'))
            as Map;
    final models = manifest['models'] as List;
    final expectedIds = ClassificationModel.values.map((m) => m.id).toSet();
    if (models.length != expectedIds.length ||
        !setEquals(models.map((m) => m['id'] as String).toSet(), expectedIds)) {
      throw const FormatException('Incomplete Sydney model bundle');
    }
    final metadata = models.singleWhere((m) => m['id'] == model.id) as Map;
    if (metadata['source_run'] != model.sourceRun ||
        metadata['window_seconds'] != model.windowSeconds ||
        metadata['seed'] != model.seed ||
        'assets/sydney/${metadata['asset']}' != model.asset ||
        !listEquals(metadata['ordered_features'] as List, model.featureNames) ||
        !listEquals(metadata['labels'] as List, model.labels)) {
      throw const FormatException('Sydney model contract mismatch');
    }
    return OnnxRuntime().createSessionFromAsset(
      model.asset,
      options: OrtSessionOptions(
        intraOpNumThreads: 1,
        interOpNumThreads: 1,
        providers: [OrtProvider.CPU],
      ),
    );
  }

  OrtSession? _session;
  String? _loadedId;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load(ClassificationModel model) =>
      _serialize(() => _load(model));

  Future<void> _load(ClassificationModel model) async {
    if (_disposed) throw StateError('Classifier disposed');
    if (_loadedId == model.id && _session != null) return;
    final previous = _session;
    _session = null;
    _loadedId = null;
    await previous?.close();
    _session = await _sessionFactory(model);
    _loadedId = model.id;
  }

  Future<(VehicleMode, double)> predict(
    ClassificationModel model,
    List<double> features,
  ) => _serialize(() async {
    if (features.length != model.featureNames.length) {
      throw ArgumentError('Expected ${model.featureNames.length} features');
    }
    await _load(model);
    OrtValue? input;
    final outputs = <String, OrtValue>{};
    try {
      input = await OrtValue.fromList(Float32List.fromList(features), [
        1,
        features.length,
      ]);
      outputs.addAll(await _session!.run({'features': input}));
      final labels = await outputs['label']!.asList();
      final index = (labels.first as num).toInt();
      final probabilities =
          (await outputs['probabilities']!.asList()).first as List;
      if (index < 0 || index >= model.labels.length) {
        throw StateError('Invalid class index');
      }
      final confidence = (probabilities[index] as num).toDouble();
      if (!confidence.isFinite || confidence < 0 || confidence > 1) {
        throw StateError('Invalid model confidence');
      }
      return (VehicleMode.values.byName(model.labels[index]), confidence);
    } finally {
      // Dispose every allocated tensor even if result decoding fails.
      await Future.wait([
        if (input != null) input.dispose(),
        for (final output in outputs.values) output.dispose(),
      ]);
    }
  });

  Future<void> close() => _serialize(() async {
    final session = _session;
    _session = null;
    _loadedId = null;
    await session?.close();
  });

  Future<void> dispose() async {
    _disposed = true;
    await close();
  }
}
