import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/terminal_test_support.dart';

void main() {
  test('Run-owned resource blocks terminal until settle or transfer', () {
    final resource = RuntimeResource(
      id: _resource,
      state: RuntimeResourceState.active,
      owner: RuntimeResourceOwner.run,
      originRunId: terminalRunId,
      ownerRunId: terminalRunId,
    );
    final projection = _withResources(
      terminalProjection(),
      <RuntimeResourceId, RuntimeResource>{_resource: resource},
    );

    expect(
      _barrier(projection).blockers,
      contains(TerminalBarrierBlocker.runOwnedRuntimeResource),
    );
    expect(
      _barrier(
        _withResources(
          projection,
          <RuntimeResourceId, RuntimeResource>{
            _resource: resource.copyWith(
              owner: RuntimeResourceOwner.session,
              clearOwnerRun: true,
            ),
          },
        ),
      ).isReady,
      isTrue,
    );
  });

  test('duplicate transfer/terminal content is idempotent; mutation conflicts',
      () {
    const reducer = AgentReducer();
    var projection = reducer.replay(<AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: terminalRunId),
      _event(
        3,
        AgentEventType.deferredCreated,
        runId: terminalRunId,
        payload: <String, Object?>{
          'deferredOperationId': terminalDeferredId.value,
        },
      ),
      _event(
        4,
        AgentEventType.deferredOwnershipTransferred,
        runId: terminalRunId,
        payload: <String, Object?>{
          'deferredOperationId': terminalDeferredId.value,
          'fromOwner': 'run',
          'owner': 'session',
        },
      ),
    ]);
    projection = reducer.apply(
      projection,
      _event(
        5,
        AgentEventType.deferredOwnershipTransferred,
        runId: terminalRunId,
        payload: <String, Object?>{
          'deferredOperationId': terminalDeferredId.value,
          'fromOwner': 'run',
          'owner': 'session',
        },
      ),
    );
    expect(
      projection.deferredOperations[terminalDeferredId]!.owner,
      DeferredOperationOwner.session,
    );
    expect(
      () => reducer.apply(
        projection,
        _event(
          6,
          AgentEventType.deferredOwnershipTransferred,
          runId: terminalRunId,
          payload: <String, Object?>{
            'deferredOperationId': terminalDeferredId.value,
            'fromOwner': 'session',
            'owner': 'run',
          },
        ),
      ),
      throwsA(_replayCode('deferred_owner_mismatch')),
    );
  });

  test('after Run terminal only Session/resource/audit events can continue',
      () {
    const reducer = AgentReducer();
    var projection = reducer.replay(<AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: terminalRunId),
      _event(
        3,
        AgentEventType.runAttemptStarted,
        runId: terminalRunId,
        attemptId: terminalAttemptId,
      ),
      _event(
        4,
        AgentEventType.runStarted,
        runId: terminalRunId,
        attemptId: terminalAttemptId,
      ),
      _event(
        5,
        AgentEventType.resourceRegistered,
        payload: <String, Object?>{
          'runtimeResourceId': _resource.value,
          'owner': 'run',
          'ownerRunId': terminalRunId.value,
        },
      ),
      _event(
        6,
        AgentEventType.resourceOwnershipTransferred,
        payload: <String, Object?>{
          'runtimeResourceId': _resource.value,
          'fromOwner': 'run',
          'owner': 'session',
        },
      ),
      _event(
        7,
        AgentEventType.deferredCreated,
        runId: terminalRunId,
        payload: <String, Object?>{
          'deferredOperationId': terminalDeferredId.value,
        },
      ),
      _event(
        8,
        AgentEventType.deferredOwnershipTransferred,
        runId: terminalRunId,
        payload: <String, Object?>{
          'deferredOperationId': terminalDeferredId.value,
          'owner': 'session',
        },
      ),
      _event(9, AgentEventType.runCompleted, runId: terminalRunId),
    ]);
    projection = reducer.apply(
      projection,
      _event(
        10,
        AgentEventType.resourceUpdated,
        payload: <String, Object?>{'runtimeResourceId': _resource.value},
      ),
    );
    expect(projection.journalSequence, 10);
    expect(
      () => reducer.apply(
        projection,
        _event(
          11,
          AgentEventType.deferredCompleted,
          runId: terminalRunId,
          payload: <String, Object?>{
            'deferredOperationId': terminalDeferredId.value,
          },
        ),
      ),
      throwsA(_replayCode('terminal_run_mutation')),
    );
  });
}

TerminalBarrierResult _barrier(AgentSessionProjection projection) =>
    const TerminalBarrier().evaluate(
      projection: projection,
      proposal: terminalProposal(),
      drainedSourceWatermarks: <String, int>{'source:test': 10},
    );

AgentSessionProjection _withResources(
  AgentSessionProjection projection,
  Map<RuntimeResourceId, RuntimeResource> resources,
) =>
    projection.copyWith(resources: resources);

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  RunId? runId,
  AttemptId? attemptId,
  Map<String, Object?> payload = const <String, Object?>{},
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toString().padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: terminalSessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: runId,
      attemptId: attemptId,
      causationId: terminalCausationId,
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );

Matcher _replayCode(String code) => isA<ReplayViolation>().having(
      (error) => error.code,
      'code',
      code,
    );

final _resource =
    RuntimeResourceId.parse('res_00000000000000000000000000000000');
