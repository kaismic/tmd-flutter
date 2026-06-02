import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:tmd_prototype/models/prediction_entry.dart';
import 'package:tmd_prototype/vehicle_classifier.dart';
import 'package:tmd_prototype/widgets/current_state_card.dart';
import 'package:tmd_prototype/widgets/history_row.dart';
import 'detection_orchestrator.dart';
import 'models/transport_state.dart';

void main() => runApp(const TransportDetectorApp());

class TransportDetectorApp extends StatelessWidget {
  const TransportDetectorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transport Mode Detector',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const DetectorPage(),
  );
}

class DetectorPage extends StatefulWidget {
  const DetectorPage({super.key});
  @override
  State<DetectorPage> createState() => _DetectorPageState();
}

class _DetectorPageState extends State<DetectorPage> {
  final _orchestrator = DetectionOrchestrator();
  final List<PredictionEntry> _history = [];
  static const int _maxHistory = 10;

  @override
  void initState() {
    super.initState();
    _orchestrator.stateStream.listen((state) {
      if (!state.isRunning ||
            state.activityType == ActivityType.IN_VEHICLE
            && state.vehicleInference!.windowFill < 1.0) {
        return;
      }
      setState(() {
        _history.insert(0, PredictionEntry(state));
        if (_history.length > _maxHistory) _history.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _orchestrator.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_orchestrator.running) {
      await _orchestrator.stop();
    } else {
      await _orchestrator.start();
    }
    setState(() => {});
  }

  Future<void> _showModelPicker() async {
    final selected = await showDialog<ClassificationModel>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Classifier Model'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: ClassificationModel.values.map((cm) {
                final isSelected = cm == _orchestrator.selectedModel;

                return ListTile(
                  title: Text(
                    VehicleClassifier.modelNames[cm] ?? 'Unknown model',
                  ),
                  trailing: isSelected ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(context).pop(cm);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );

    if (selected != null && selected != _orchestrator.selectedModel) {
      setState(() {
        _orchestrator.setSelectedModel(selected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport Detector'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<TransportState>(
              stream: _orchestrator.stateStream,
              initialData: TransportState.idle,
              builder: (context, snapshot) =>
                  CurrentStateCard(snapshot.data ?? TransportState.idle),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Prediction History',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (_history.isNotEmpty)
                  Text(
                    '${_history.length}/$_maxHistory',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Text(
                        _orchestrator.running
                            ? 'Waiting for first prediction…'
                            : 'Press Start to begin',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          HistoryRow(_history[index]),
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showModelPicker,
              label: Text(
                'Selected: ${VehicleClassifier.modelNames[_orchestrator.selectedModel]!}',
              ),
            ),
            // TODO remove after testing
            // const SizedBox(height: 8),
            // OutlinedButton.icon(
            //   onPressed: _orchestrator.running && !_orchestrator.inVehicle
            //       ? () => _orchestrator.debugStartVehicleInference()
            //       : null,
            //   icon: const Icon(Icons.directions_car),
            //   label: const Text('Simulate IN_VEHICLE'),
            // ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_orchestrator.running ? Icons.stop : Icons.play_arrow),
              label: Text(
                _orchestrator.running ? 'Stop Detection' : 'Start Detection',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _orchestrator.running
                    ? theme.colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
