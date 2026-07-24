import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/terminal_test_support.dart';

void main() {
  test('active managed WorkItem blocks terminal', () {
    final work = WorkItem(
      id: terminalWorkId,
      runId: terminalRunId,
      state: WorkItemState.executing,
      effectControl: EffectControl.managed,
    );
    expect(
      _evaluate(
        terminalProjection(
          workItems: <WorkItemId, WorkItem>{terminalWorkId: work},
        ),
      ).blockers,
      contains(TerminalBarrierBlocker.activeManagedWork),
    );
  });

  test('pending Approval blocks terminal', () {
    final work = WorkItem(
      id: terminalWorkId,
      runId: terminalRunId,
      state: WorkItemState.succeeded,
      effectControl: EffectControl.managed,
      approvalId: terminalApprovalId,
    );
    final approval = Approval(
      id: terminalApprovalId,
      workItemId: terminalWorkId,
      state: ApprovalState.pending,
    );
    expect(
      _evaluate(
        terminalProjection(
          workItems: <WorkItemId, WorkItem>{terminalWorkId: work},
          approvals: <ApprovalId, Approval>{
            terminalApprovalId: approval,
          },
        ),
      ).blockers,
      contains(TerminalBarrierBlocker.unresolvedApproval),
    );
  });

  test('Run-owned unsettled DeferredOperation blocks terminal', () {
    final operation = DeferredOperation(
      id: terminalDeferredId,
      originRunId: terminalRunId,
      owner: DeferredOperationOwner.run,
      state: DeferredOperationState.pending,
      cancellationPolicy: DeferredCancellationPolicy.cancelWithOwner,
    );
    expect(
      _evaluate(
        terminalProjection(
          deferredOperations: <DeferredOperationId, DeferredOperation>{
            terminalDeferredId: operation,
          },
        ),
      ).blockers,
      contains(TerminalBarrierBlocker.runOwnedDeferredOperation),
    );
  });

  test('active observed effect blocks terminal', () {
    expect(
      _evaluate(
        terminalProjection(),
        observedEffects: <ObservedEffectBarrier>[
          ObservedEffectBarrier(
            runId: terminalRunId,
            state: ObservedEffectState.active,
          ),
        ],
      ).blockers,
      contains(TerminalBarrierBlocker.unresolvedObservedEffect),
    );
  });

  test('stale attempt, stale epoch, and existing terminal fail closed', () {
    expect(
      _evaluate(
        terminalProjection(),
        proposal: terminalProposal(attemptId: terminalOtherAttemptId),
      ).blockers,
      contains(TerminalBarrierBlocker.staleAttempt),
    );
    expect(
      _evaluate(
        terminalProjection(),
        proposal: terminalProposal(executionEpoch: 4),
      ).blockers,
      contains(TerminalBarrierBlocker.staleExecutionEpoch),
    );
    expect(
      _evaluate(
        terminalProjection(runState: AgentRunState.completed),
      ).blockers,
      contains(TerminalBarrierBlocker.alreadyTerminal),
    );
  });

  test('cancelled requires matching intent or containment proof', () {
    expect(
      _evaluate(
        terminalProjection(runState: AgentRunState.cancelling),
        proposal: terminalProposal(outcome: TerminalOutcome.cancelled),
      ).blockers,
      contains(TerminalBarrierBlocker.cancellationAuthorityMissing),
    );
    expect(
      _evaluate(
        terminalProjection(runState: AgentRunState.cancelling),
        proposal: terminalProposal(
          outcome: TerminalOutcome.cancelled,
          hasMatchingCancellationIntent: true,
        ),
      ).isReady,
      isTrue,
    );
  });

  test('terminal append failure leaves the persisted Run nonterminal',
      () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final started = await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{},
      ),
    );
    final runId = started.runId!;
    final attemptId = AttemptId.parse('att_90000000000000000000000000000000');
    final attemptEventId =
        EventId.parse('evt_80000000000000000000000000000000');
    final startedEventId =
        EventId.parse('evt_81000000000000000000000000000000');
    final driverCommand =
        CommandId.parse('cmd_80000000000000000000000000000000');
    final attemptEvent = _runEvent(
      sequence: 4,
      eventId: attemptEventId,
      type: AgentEventType.runAttemptStarted,
      sessionId: created.sessionId,
      runId: runId,
      attemptId: attemptId,
      causationId: driverCommand,
      payload: const <String, Object?>{'executionEpoch': 1},
    );
    final runStartedEvent = _runEvent(
      sequence: 5,
      eventId: startedEventId,
      type: AgentEventType.runStarted,
      sessionId: created.sessionId,
      runId: runId,
      attemptId: attemptId,
      causationId: driverCommand,
    );
    final prepared = await fixture.store.append(
      AgentStoreTransaction(
        sessionId: created.sessionId,
        expectedHead: started.sessionHandle!.head,
        newIdAllocations: <AgentStoreIdAllocation>[
          AgentStoreIdAllocation(driverCommand),
          AgentStoreIdAllocation(attemptId),
          AgentStoreIdAllocation(attemptEventId),
          AgentStoreIdAllocation(startedEventId),
        ],
        events: <AgentEvent>[attemptEvent, runStartedEvent],
      ),
      requestedDurability: AgentStoreDurability.memory,
    );
    final handle = AgentSessionHandle(
      sessionId: created.sessionId,
      projectionGeneration: prepared.afterHead.generation,
      head: prepared.afterHead,
    );
    fixture.store.failNextAppendBeforeCommit = true;

    await expectLater(
      fixture.kernel.commitTerminal(
        handle: handle,
        proposal: TerminalProposal(
          runId: runId,
          attemptId: attemptId,
          executionEpoch: 1,
          outcome: TerminalOutcome.completed,
          sourceId: 'source:test',
          sourceWatermark: 0,
          causationId: driverCommand,
          payload: const <String, Object?>{},
        ),
        drainedSourceWatermarks: const <String, int>{'source:test': 0},
      ),
      throwsA(
        isA<AgentCommandError>().having(
          (error) => error.code,
          'code',
          AgentErrorCode.unavailable,
        ),
      ),
    );
    final projection = await fixture.kernel.loadProjection(created.sessionId);
    expect(projection.runs[runId]!.state, AgentRunState.inProgress);
    expect(projection.runs[runId]!.terminalEventId, isNull);
  });
}

TerminalBarrierResult _evaluate(
  AgentSessionProjection projection, {
  TerminalProposal? proposal,
  Iterable<ObservedEffectBarrier> observedEffects =
      const <ObservedEffectBarrier>[],
}) =>
    const TerminalBarrier().evaluate(
      projection: projection,
      proposal: proposal ?? terminalProposal(),
      drainedSourceWatermarks: const <String, int>{'source:test': 10},
      observedEffects: observedEffects,
    );

AgentEvent _runEvent({
  required int sequence,
  required EventId eventId,
  required AgentEventType type,
  required SessionId sessionId,
  required RunId runId,
  required AttemptId attemptId,
  required CommandId causationId,
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
      causationId: causationId,
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );
