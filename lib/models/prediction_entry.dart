import 'package:tmd_prototype/transport_state.dart' show TransportState;

class PredictionEntry {
  final TransportState state;
  final DateTime timestamp;
  PredictionEntry(this.state) : timestamp = DateTime.now();
}