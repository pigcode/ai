import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';

final class DapEventRecord {
  const DapEventRecord({
    required this.seq,
    required this.event,
    required this.body,
  });

  final int seq;
  final String event;
  final JsonObject body;
}

/// Ordered, bounded adapter event queue.
final class DapEventQueue {
  DapEventQueue({this.maxEvents = 1024}) {
    if (maxEvents <= 0) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive.');
    }
  }

  final int maxEvents;
  final List<DapEventRecord> _events = <DapEventRecord>[];
  int _lastSequence = 0;

  List<DapEventRecord> get events => List<DapEventRecord>.unmodifiable(_events);

  DapEventRecord add({
    required int seq,
    required String event,
    required Map<String, Object?> body,
  }) {
    if (seq <= _lastSequence) {
      throw const DapCorrelationException(
        'dap_event_seq_duplicate_or_reordered',
        'DAP event seq must increase monotonically.',
      );
    }
    if (!dapEventsByName.containsKey(event)) {
      throw const DapCorrelationException(
        'dap_event_unknown',
        'DAP event is not in the pinned inventory.',
      );
    }
    if (_events.length >= maxEvents) {
      throw const DapResourceLimitException(
        'dap_event_queue_full',
        'DAP event queue reached its configured limit.',
      );
    }
    final record = DapEventRecord(
      seq: seq,
      event: event,
      body: freezeJsonObject(body),
    );
    _lastSequence = seq;
    _events.add(record);
    return record;
  }
}
