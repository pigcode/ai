import 'dart:math';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('terminal race permutations commit at most one terminal', () {
    const reducer = AgentReducer();
    for (var seed = 0; seed < 128; seed++) {
      final random = Random(seed);
      final terminalTypes = <AgentEventType>[
        AgentEventType.runCompleted,
        AgentEventType.runFailed,
        AgentEventType.runInterrupted,
      ]..shuffle(random);
      var projection = reducer.replay(<AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
        _event(2, AgentEventType.runCreated),
        _event(
          3,
          AgentEventType.runAttemptStarted,
          attemptId: _attempt,
        ),
        _event(4, AgentEventType.runStarted, attemptId: _attempt),
      ]);
      var committed = 0;
      var sequence = 5;

      for (final type in terminalTypes) {
        try {
          projection = reducer.apply(
            projection,
            _event(sequence++, type),
          );
          committed += 1;
        } on ReplayViolation {
          sequence -= 1;
        }
      }
      expect(committed, 1, reason: 'seed=$seed');
      expect(projection.runs[_run]!.state.isTerminal, isTrue);
    }
  });
}

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  AttemptId? attemptId,
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toString().padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: _session,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: type == AgentEventType.sessionCreated ? null : _run,
      attemptId: attemptId,
      causationId: _command,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _run = RunId.parse('run_00000000000000000000000000000000');
final _attempt = AttemptId.parse('att_00000000000000000000000000000000');
final _command = CommandId.parse('cmd_00000000000000000000000000000000');
