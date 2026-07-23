import 'dart:collection';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'generated/acp_models.g.dart';
import 'history.dart';

/// Terminal result of one prompt turn and its pre-terminal updates.
final class AcpPromptTurnResult {
  AcpPromptTurnResult({
    required this.response,
    required Iterable<AcpSessionUpdateEvent> updates,
    required this.sessionCancelRequested,
  }) : updates = List<AcpSessionUpdateEvent>.unmodifiable(updates);

  final AcpPromptResponse response;
  final List<AcpSessionUpdateEvent> updates;
  final bool sessionCancelRequested;

  String get stopReason =>
      (response.toJson()! as JsonObject)['stopReason']! as String;
}

/// Tracks prompt terminal barriers without equating them to request cancel.
final class AcpPromptLedger {
  AcpPromptLedger({
    required this.history,
    required this.diagnostics,
    required this.maxSessions,
  }) {
    if (maxSessions <= 0) {
      throw ArgumentError.value(
          maxSessions, 'maxSessions', 'Must be positive.');
    }
  }

  final AcpSessionHistory history;
  final ProtocolDiagnosticSink diagnostics;
  final int maxSessions;
  final Map<String, List<AcpSessionUpdateEvent>> _active =
      <String, List<AcpSessionUpdateEvent>>{};
  final LinkedHashSet<String> _terminalSessions = LinkedHashSet<String>();
  final LinkedHashSet<String> _sessionCancelIntents = LinkedHashSet<String>();
  var _nextSequence = 0;

  bool hasActivePrompt(String sessionId) => _active.containsKey(sessionId);

  void beginPrompt(String sessionId) {
    if (_active.containsKey(sessionId)) {
      throw AcpStateException(
        'acp_prompt_already_active',
        'A prompt is already active for session $sessionId.',
      );
    }
    _terminalSessions.remove(sessionId);
    _active[sessionId] = <AcpSessionUpdateEvent>[];
  }

  void noteSessionCancel(String sessionId) {
    if (_active.containsKey(sessionId)) {
      _boundedAdd(_sessionCancelIntents, sessionId);
    }
  }

  void revokeSessionCancel(String sessionId) {
    _sessionCancelIntents.remove(sessionId);
  }

  AcpSessionUpdateEvent recordUpdate(JsonObject notification) {
    final sessionId = notification['sessionId']! as String;
    final update = notification['update']! as JsonObject;
    final provenance = history.isReplaying(sessionId)
        ? AcpUpdateProvenance.historicalReplay
        : AcpUpdateProvenance.live;
    final active = _active[sessionId];
    final event = AcpSessionUpdateEvent(
      sessionId: sessionId,
      update: update,
      provenance: provenance,
      sequence: _nextSequence++,
      isLate: provenance == AcpUpdateProvenance.live &&
          active == null &&
          _terminalSessions.contains(sessionId),
    );
    if (provenance == AcpUpdateProvenance.live) {
      active?.add(event);
    }
    history.record(event);
    return event;
  }

  AcpPromptTurnResult completePrompt(
    String sessionId,
    AcpPromptResponse response,
  ) {
    final updates = _active.remove(sessionId);
    if (updates == null) {
      throw AcpStateException(
        'acp_prompt_not_active',
        'No prompt is active for session $sessionId.',
      );
    }
    _boundedAdd(_terminalSessions, sessionId);
    final hadCancelIntent = _sessionCancelIntents.remove(sessionId);
    final stopReason =
        (response.toJson()! as JsonObject)['stopReason']! as String;
    if (stopReason == 'cancelled' && !hadCancelIntent) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'acp_unmatched_cancelled_prompt',
          message:
              'Peer returned a cancelled prompt without a local session cancel intent.',
          method: 'session/prompt',
          details: <String, Object?>{'sessionId': sessionId},
        ),
      );
    }
    return AcpPromptTurnResult(
      response: response,
      updates: updates,
      sessionCancelRequested: hadCancelIntent,
    );
  }

  void abortPrompt(String sessionId) {
    _active.remove(sessionId);
    _sessionCancelIntents.remove(sessionId);
  }

  void _boundedAdd(LinkedHashSet<String> values, String value) {
    values.remove(value);
    values.add(value);
    while (values.length > maxSessions) {
      values.remove(values.first);
    }
  }

  void _diagnose(ProtocolDiagnostic diagnostic) {
    try {
      diagnostics.add(diagnostic);
    } on Object {
      // Caller diagnostics must not change prompt lifecycle.
    }
  }
}
