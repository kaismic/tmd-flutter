import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'transport_state.dart';

enum ClassificationModel { dt, knn, nn, rf, svm }

class VehicleClassifier {
  OrtSession? _session;
  bool loading = false;
  bool _isLoaded = false;
  ClassificationModel selected = ClassificationModel.dt;

  static const Map<ClassificationModel, String> _modelFilenames = {
    ClassificationModel.dt: 'decision_tree',
    ClassificationModel.knn: 'knn',
    ClassificationModel.nn: 'neural_network',
    ClassificationModel.rf: 'random_forest',
    ClassificationModel.svm: 'svm',
  };

  static const Map<ClassificationModel, String> modelNames = {
    ClassificationModel.dt: 'Decision Tree',
    ClassificationModel.knn: 'K-NN',
    ClassificationModel.nn: 'Neural Network',
    ClassificationModel.rf: 'Random Forest',
    ClassificationModel.svm: 'SVM',
  };

  /// Maps the integer class index output by the model back to a [VehicleMode].
  /// Order must match TRANSPORT_MODES in constants.py:
  ///   bus=0, car=1, train=2
  static const List<VehicleMode> _vehicleIndex = [
    VehicleMode.bus,
    VehicleMode.car,
    VehicleMode.train,
  ];

  Future<void> load() async {
    if (loading) return;
    loading = true;
    _session?.close();
    final ort = OnnxRuntime();
    _session = await ort.createSessionFromAsset(
      'assets/7264c172/${_modelFilenames[selected]}.onnx',
    );
    _isLoaded = true;
    loading = false;
  }

  /// Run inference on [features] (output of FeatureExtractor.extract).
  /// Expects exactly 16 features as a flat list.
  /// Returns (predicted mode, confidence 0.0 - 1.0).
  Future<(VehicleMode, double)> predict(List<double> features) async {
    if (!_isLoaded) await load();
    assert(_session != null);

    final inputTensor = await OrtValue.fromList(features, [1, 16]);
    final inputs = {_session!.inputNames[0]: inputTensor};
    final outputs = await _session!.run(inputs);

    // Model output names
    // label: int64[1]
    // probabilities: float32[1,3]
    // class_labels: int64[3]

    final labelData = await outputs['label']!.asList();
    int index = labelData.first as int;

    final probDataOuter = await outputs['probabilities']!.asList();
    final probData = probDataOuter.first as List;
    double confidence = probData[index] as double;

    await inputTensor.dispose();
    for (final tensor in outputs.values) {
      await tensor.dispose();
    }

    return (_vehicleIndex[index], confidence);
  }

  void dispose() {
    _session?.close();
    _isLoaded = false;
  }
}
