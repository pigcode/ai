import 'dart:math';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/run_state_model.dart';

void main() {
  test('random legal Run traces agree with the independent state model', () {
    const model = RunStateModel();
    const reducer = AgentReducer();

    for (var seed = 0; seed < 256; seed++) {
      final random = Random(seed);
      var modelState = ModelRunState.pending;
      var projection = reducer.replay(<AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
        _event(2, AgentEventType.runCreated, runId: _run),
        _event(
          3,
          AgentEventType.runAttemptStarted,
          runId: _run,
          attemptId: _attempt,
        ),
      ]);
      var sequence = 4;

      for (var step = 0; step < 24 && !modelState.isTerminal; step++) {
        final legal = model.legalSignals(modelState);
        final signal = legal[random.nextInt(legal.length)];
        modelState = model.transition(modelState, signal);
        projection = reducer.apply(
          projection,
          _event(
            sequence++,
            _eventType(signal),
            runId: _run,
            attemptId: _requiresAttempt(signal) ? _attempt : null,
          ),
        );

        expect(
          projection.runs[_run]!.state.name,
          modelState.name,
          reason: 'seed=$seed step=$step signal=$signal',
        );
      }
    }
  });
}

AgentEventType _eventType(ModelRunSignal signal) => switch (signal) {
      ModelRunSignal.started => AgentEventType.runStarted,
      ModelRunSignal.startFailed ||
      ModelRunSignal.failed =>
        AgentEventType.runFailed,
      ModelRunSignal.cancelRequested => AgentEventType.runCancelRequested,
      ModelRunSignal.suspendRequested => AgentEventType.runSuspendRequested,
      ModelRunSignal.suspended => AgentEventType.runSuspended,
      ModelRunSignal.resumeRequested => AgentEventType.runResumeRequested,
      ModelRunSignal.reconciling => AgentEventType.runReconciling,
      ModelRunSignal.completed => AgentEventType.runCompleted,
      ModelRunSignal.cancelled => AgentEventType.runCancelled,
      ModelRunSignal.interrupted => AgentEventType.runInterrupted,
    };

bool _requiresAttempt(ModelRunSignal signal) =>
    signal == ModelRunSignal.started || signal == ModelRunSignal.suspended;

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  RunId? runId,
  AttemptId? attemptId,
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toRadixString(32).padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: _session,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: runId,
      attemptId: attemptId,
      causationId: _command,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _run = RunId.parse('run_00000000000000000000000000000000');
final _attempt = AttemptId.parse('att_00000000000000000000000000000000');
final _command = CommandId.parse('cmd_00000000000000000000000000000000');
