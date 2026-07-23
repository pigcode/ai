import 'dart:collection';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';

/// Why one session update was delivered to the client.
enum AcpUpdateProvenance {
  live,
  historicalReplay,
}

/// One ordered, schema-validated `session/update` event.
final class AcpSessionUpdateEvent {
  AcpSessionUpdateEvent({
    required this.sessionId,
    required JsonObject update,
    required this.provenance,
    required this.sequence,
    required this.isLate,
  }) : update = freezeJsonObject(update);

  final String sessionId;
  final JsonObject update;
  final AcpUpdateProvenance provenance;
  final int sequence;
  final bool isLate;

  String get kind => update['sessionUpdate']! as String;
}

/// Bounded in-memory view of session updates observed by one client.
final class AcpSessionHistory {
  AcpSessionHistory({required this.maxEntries}) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
  }

  final int maxEntries;
  final Queue<AcpSessionUpdateEvent> _events = Queue<AcpSessionUpdateEvent>();
  final Set<String> _activeReplays = <String>{};

  List<AcpSessionUpdateEvent> get events =>
      List<AcpSessionUpdateEvent>.unmodifiable(_events);

  List<AcpSessionUpdateEvent> forSession(String sessionId) =>
      List<AcpSessionUpdateEvent>.unmodifiable(
        _events.where((event) => event.sessionId == sessionId),
      );

  bool isReplaying(String sessionId) => _activeReplays.contains(sessionId);

  int beginHistoricalReplay(String sessionId) {
    if (!_activeReplays.add(sessionId)) {
      throw AcpStateException(
        'acp_duplicate_history_replay',
        'A historical replay is already active for session $sessionId.',
      );
    }
    return _events.isEmpty ? 0 : _events.last.sequence + 1;
  }

  List<AcpSessionUpdateEvent> endHistoricalReplay(
    String sessionId,
    int marker,
  ) {
    _activeReplays.remove(sessionId);
    return List<AcpSessionUpdateEvent>.unmodifiable(
      _events.where(
        (event) =>
            event.sequence >= marker &&
            event.sessionId == sessionId &&
            event.provenance == AcpUpdateProvenance.historicalReplay,
      ),
    );
  }

  void record(AcpSessionUpdateEvent event) {
    if (_events.length == maxEntries) {
      _events.removeFirst();
    }
    _events.addLast(event);
  }
}
