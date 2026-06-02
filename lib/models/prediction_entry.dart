import 'package:tmd_prototype/models/transport_state.dart' show TransportState;

class PredictionEntry {
  final TransportState state;
  final DateTime timestamp;
  PredictionEntry(this.state) : timestamp = DateTime.now();
}