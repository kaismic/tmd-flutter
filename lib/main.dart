import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'detection_orchestrator.dart';
import 'models/classification_model.dart';
import 'models/prediction_entry.dart';
import 'models/transport_state.dart';
import 'widgets/current_state_card.dart';
import 'widgets/history_row.dart';

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
  const DetectorPage({super.key, this.orchestrator});
  final DetectionOrchestrator? orchestrator;
  @override
  State<DetectorPage> createState() => _DetectorPageState();
}

class _DetectorPageState extends State<DetectorPage> {
  late final _orchestrator = widget.orchestrator ?? DetectionOrchestrator();
  StreamSubscription<TransportState>? _subscription;
  TransportState _state = TransportState.idle;
  final List<PredictionEntry> _history = [];
  static const _maxHistory = 10;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _state = _orchestrator.currentState;
    _subscription = _orchestrator.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _state = state;
        if (state.isRunning &&
            state.message == null &&
            (state.activityType != ActivityType.IN_VEHICLE ||
                state.hasPrediction)) {
          _history.insert(0, PredictionEntry(state));
          if (_history.length > _maxHistory) _history.removeLast();
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_orchestrator.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _toggling = true);
    try {
      if (_orchestrator.running) {
        await _orchestrator.stop();
      } else {
        await _orchestrator.start();
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _showModelPicker() async {
    final selected = await showDialog<ClassificationModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Classifier Model'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final version in [1, 2]) ...[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Sydney V$version',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final model in ClassificationModel.values.where(
                  (m) => m.version == version,
                ))
                  ListTile(
                    key: ValueKey(model.id),
                    title: Text(
                      'XGBoost · ${model.windowSeconds}s · seed ${model.seed}',
                    ),
                    subtitle: Text(model.sourceRun),
                    selected: model.id == _orchestrator.selectedModel.id,
                    trailing: model.id == _orchestrator.selectedModel.id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, model),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _orchestrator.setSelectedModel(selected));
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bound the card on small screens; all status details remain scrollable.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                ),
                child: SingleChildScrollView(child: CurrentStateCard(_state)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Prediction History', style: theme.textTheme.titleSmall),
                  if (_history.isNotEmpty)
                    Text('${_history.length}/$_maxHistory'),
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
                        ),
                      )
                    : ListView.separated(
                        itemCount: _history.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => HistoryRow(_history[i]),
                      ),
              ),
              OutlinedButton.icon(
                onPressed: _showModelPicker,
                icon: const Icon(Icons.tune),
                label: Text(
                  'Selected: ${_orchestrator.selectedModel.name}',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _toggling ? null : _toggle,
                icon: Icon(
                  _orchestrator.running ? Icons.stop : Icons.play_arrow,
                ),
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
      ),
    );
  }
}
