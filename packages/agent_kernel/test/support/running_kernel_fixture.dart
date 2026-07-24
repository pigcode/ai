import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'kernel_fixture.dart';

final class RunningKernelState {
  const RunningKernelState({
    required this.sessionId,
    required this.runId,
    required this.attemptId,
    required this.handle,
    required this.driverCommandId,
  });

  final SessionId sessionId;
  final RunId runId;
  final AttemptId attemptId;
  final AgentSessionHandle handle;
  final CommandId driverCommandId;
}

Future<RunningKernelState> prepareRunningRun(
  KernelFixture fixture, {
  bool durableCheckpointResume = false,
}) async {
  final (created, _) = await fixture.createSession(
    capabilities: <String, Object?>{
      'run': true,
      if (durableCheckpointResume) 'durableCheckpointResume': true,
    },
  );
  final started = await fixture.kernel.startRun(
    StartRunCommand(
      commandId: startCommandId,
      handle: created.sessionHandle!,
      input: const <String, Object?>{'prompt': 'test'},
    ),
  );
  final runId = started.runId!;
  final attemptEvent = _event(
    eventId: runningAttemptEventId,
    sequence: 4,
    type: AgentEventType.runAttemptStarted,
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
    payload: const <String, Object?>{'executionEpoch': 1},
  );
  final startedEvent = _event(
    eventId: runningStartedEventId,
    sequence: 5,
    type: AgentEventType.runStarted,
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
  );
  final receipt = await fixture.store.append(
    AgentStoreTransaction(
      sessionId: created.sessionId,
      expectedHead: started.sessionHandle!.head,
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(runningDriverCommandId),
        AgentStoreIdAllocation(runningAttemptId),
        AgentStoreIdAllocation(runningAttemptEventId),
        AgentStoreIdAllocation(runningStartedEventId),
      ],
      events: <AgentEvent>[attemptEvent, startedEvent],
    ),
    requestedDurability: AgentStoreDurability.memory,
  );
  return RunningKernelState(
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
    handle: AgentSessionHandle(
      sessionId: created.sessionId,
      projectionGeneration: receipt.afterHead.generation,
      head: receipt.afterHead,
    ),
    driverCommandId: runningDriverCommandId,
  );
}

AgentEvent _event({
  required EventId eventId,
  required int sequence,
  required AgentEventType type,
  required SessionId sessionId,
  required RunId runId,
  required AttemptId attemptId,
  Map<String, Object?> payload = const <String, Object?>{},
}) =>
    AgentEvent(
      eventId: eventId,
      schemaVersion: 1,
      sessionId: sessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: runId,
      attemptId: attemptId,
      causationId: runningDriverCommandId,
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );

final runningAttemptId =
    AttemptId.parse('att_90000000000000000000000000000000');
final runningAttemptEventId =
    EventId.parse('evt_80000000000000000000000000000000');
final runningStartedEventId =
    EventId.parse('evt_81000000000000000000000000000000');
final runningDriverCommandId =
    CommandId.parse('cmd_80000000000000000000000000000000');
final cancelCommandId = CommandId.parse('cmd_30000000000000000000000000000000');
final suspendCommandId =
    CommandId.parse('cmd_40000000000000000000000000000000');
final resumeCommandId = CommandId.parse('cmd_50000000000000000000000000000000');
final reconcileCommandId =
    CommandId.parse('cmd_60000000000000000000000000000000');
