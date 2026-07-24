import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('only one nonterminal Run may exist in a Session', () {
    final events = <AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: _run1),
      _event(3, AgentEventType.runCreated, runId: _run2),
    ];

    expect(
      () => const AgentReducer().replay(events),
      throwsA(_violationCode('active_run_exists')),
    );
  });

  test('sequence gaps, duplicates, and out-of-order events fail closed', () {
    for (final events in <List<AgentEvent>>[
      <AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
        _event(1, AgentEventType.sessionCapabilitiesPinned),
      ],
      <AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
        _event(3, AgentEventType.sessionCapabilitiesPinned),
      ],
      <AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
        _event(2, AgentEventType.sessionCapabilitiesPinned),
        _event(1, AgentEventType.sessionAttachmentChanged),
      ],
    ]) {
      expect(
        () => const AgentReducer().replay(events),
        throwsA(_violationCode('event_sequence_violation')),
      );
    }
  });

  test('terminal blocks business events but permits session/resource/audit',
      () {
    final terminal = const AgentReducer().replay(<AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: _run1),
      _event(
        3,
        AgentEventType.runAttemptStarted,
        runId: _run1,
        attemptId: _attempt,
      ),
      _event(
        4,
        AgentEventType.runStarted,
        runId: _run1,
        attemptId: _attempt,
      ),
      _event(5, AgentEventType.runCompleted, runId: _run1),
    ]);

    expect(
      () => const AgentReducer().apply(
        terminal,
        _event(6, AgentEventType.runFailed, runId: _run1),
      ),
      throwsA(_violationCode('terminal_run_mutation')),
    );

    var projection = const AgentReducer().apply(
      terminal,
      _event(6, AgentEventType.sessionRuntimeLivenessChanged),
    );
    projection = const AgentReducer().apply(
      projection,
      _event(
        7,
        AgentEventType.resourceRegistered,
        payload: <String, Object?>{
          'runtimeResourceId': _resource.value,
        },
      ),
    );
    projection = const AgentReducer().apply(
      projection,
      _event(8, AgentEventType.driverProposalRejected),
    );
    expect(projection.journalSequence, 8);
  });

  test('raw metadata changes do not change domain projection', () {
    final first = const AgentReducer().replay(<AgentEvent>[
      _event(
        1,
        AgentEventType.sessionCreated,
        metadata: AgentEventMetadata.fromJson(
          const <String, Object?>{
            'pigcode.audit': <String, Object?>{'trace': 'first'},
          },
        ),
      ),
    ]);
    final second = const AgentReducer().replay(<AgentEvent>[
      _event(
        1,
        AgentEventType.sessionCreated,
        metadata: AgentEventMetadata.fromJson(
          const <String, Object?>{
            'pigcode.audit': <String, Object?>{'trace': 'second'},
          },
        ),
      ),
    ]);

    expect(first.toJson(), second.toJson());
  });

  test('projects Session, Attempt, Work, Approval, Deferred, and Resource', () {
    final projection = const AgentReducer().replay(<AgentEvent>[
      _event(
        1,
        AgentEventType.sessionCreated,
        payload: <String, Object?>{
          'definitionRef': 'agent:test',
          'capabilitySnapshot': <String, Object?>{'run': true},
        },
      ),
      _event(
        2,
        AgentEventType.sessionCapabilitiesPinned,
        payload: <String, Object?>{
          'capabilitySnapshot': <String, Object?>{'run': true, 'suspend': true},
        },
      ),
      _event(3, AgentEventType.runCreated, runId: _run1),
      _event(
        4,
        AgentEventType.runAttemptStarted,
        runId: _run1,
        attemptId: _attempt,
        payload: const <String, Object?>{'executionEpoch': 7},
      ),
      _event(
        5,
        AgentEventType.runStarted,
        runId: _run1,
        attemptId: _attempt,
      ),
      _event(
        6,
        AgentEventType.workProposed,
        runId: _run1,
        workItemId: _work,
        payload: const <String, Object?>{'effectControl': 'managed'},
      ),
      _event(
        7,
        AgentEventType.workPolicyEvaluated,
        runId: _run1,
        workItemId: _work,
        payload: const <String, Object?>{'decision': 'requireApproval'},
      ),
      _event(
        8,
        AgentEventType.workApprovalRequested,
        runId: _run1,
        workItemId: _work,
        payload: <String, Object?>{'approvalId': _approval.value},
      ),
      _event(
        9,
        AgentEventType.workApprovalResolved,
        runId: _run1,
        workItemId: _work,
        payload: const <String, Object?>{'decision': 'allow'},
      ),
      _event(
        10,
        AgentEventType.workExecutionStarted,
        runId: _run1,
        workItemId: _work,
      ),
      _event(
        11,
        AgentEventType.workSucceeded,
        runId: _run1,
        workItemId: _work,
      ),
      _event(
        12,
        AgentEventType.deferredCreated,
        runId: _run1,
        payload: <String, Object?>{'deferredOperationId': _deferred.value},
      ),
      _event(
        13,
        AgentEventType.deferredOwnershipTransferred,
        runId: _run1,
        payload: <String, Object?>{
          'deferredOperationId': _deferred.value,
          'fromOwner': 'run',
          'owner': 'session',
        },
      ),
      _event(
        14,
        AgentEventType.resourceRegistered,
        payload: <String, Object?>{
          'runtimeResourceId': _resource.value,
          'owner': 'run',
          'ownerRunId': _run1.value,
        },
      ),
      _event(
        15,
        AgentEventType.resourceOwnershipTransferred,
        payload: <String, Object?>{
          'runtimeResourceId': _resource.value,
          'fromOwner': 'run',
          'owner': 'session',
        },
      ),
    ]);

    expect(projection.definitionRef!.value, 'agent:test');
    expect(projection.capabilitySnapshot.value['suspend'], isTrue);
    expect(
      projection.runs[_run1]!.attempts[_attempt]!.executionEpoch,
      7,
    );
    expect(projection.workItems[_work]!.state, WorkItemState.succeeded);
    expect(projection.approvals[_approval]!.state, ApprovalState.approved);
    expect(
      projection.deferredOperations[_deferred]!.owner,
      DeferredOperationOwner.session,
    );
    expect(
      projection.resources[_resource]!.owner,
      RuntimeResourceOwner.session,
    );
  });

  test('attempt and event-type mutations fail closed', () {
    final pending = const AgentReducer().replay(<AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: _run1),
      _event(
        3,
        AgentEventType.runAttemptStarted,
        runId: _run1,
        attemptId: _attempt,
      ),
    ]);

    expect(
      () => const AgentReducer().apply(
        pending,
        _event(
          4,
          AgentEventType.runStarted,
          runId: _run1,
          attemptId: _otherAttempt,
        ),
      ),
      throwsA(_violationCode('attempt_mismatch')),
    );
    expect(
      () => const AgentReducer().apply(
        pending,
        _event(
          4,
          AgentEventType.runSuspended,
          runId: _run1,
          attemptId: _attempt,
        ),
      ),
      throwsA(_violationCode('illegal_run_transition')),
    );
  });

  test('owner and child terminal mutations fail closed', () {
    final projection = const AgentReducer().replay(<AgentEvent>[
      _event(1, AgentEventType.sessionCreated),
      _event(2, AgentEventType.runCreated, runId: _run1),
      _event(
        3,
        AgentEventType.deferredCreated,
        runId: _run1,
        payload: <String, Object?>{'deferredOperationId': _deferred.value},
      ),
      _event(
        4,
        AgentEventType.deferredOwnershipTransferred,
        runId: _run1,
        payload: <String, Object?>{
          'deferredOperationId': _deferred.value,
          'owner': 'session',
        },
      ),
    ]);

    expect(
      () => const AgentReducer().apply(
        projection,
        _event(
          5,
          AgentEventType.deferredOwnershipTransferred,
          runId: _run1,
          payload: <String, Object?>{
            'deferredOperationId': _deferred.value,
            'fromOwner': 'run',
            'owner': 'session',
          },
        ),
      ),
      throwsA(_violationCode('deferred_owner_mismatch')),
    );

    final settled = const AgentReducer().apply(
      projection,
      _event(
        5,
        AgentEventType.deferredCompleted,
        runId: _run1,
        payload: <String, Object?>{'deferredOperationId': _deferred.value},
      ),
    );
    expect(
      () => const AgentReducer().apply(
        settled,
        _event(
          6,
          AgentEventType.deferredFailed,
          runId: _run1,
          payload: <String, Object?>{'deferredOperationId': _deferred.value},
        ),
      ),
      throwsA(_violationCode('terminal_deferred_operation_mutation')),
    );
  });
}

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  RunId? runId,
  AttemptId? attemptId,
  WorkItemId? workItemId,
  Map<String, Object?> payload = const <String, Object?>{},
  AgentEventMetadata? metadata,
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toRadixString(32).padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: _session,
      sequence: sequence <= 0 ? 1 : sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: runId,
      attemptId: attemptId,
      workItemId: workItemId,
      causationId: _command,
      payload: payload,
      metadata: metadata ?? AgentEventMetadata.empty(),
    );

Matcher _violationCode(String code) => isA<ReplayViolation>().having(
      (error) => error.code,
      'code',
      code,
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _run1 = RunId.parse('run_00000000000000000000000000000000');
final _run2 = RunId.parse('run_10000000000000000000000000000000');
final _attempt = AttemptId.parse('att_00000000000000000000000000000000');
final _otherAttempt = AttemptId.parse('att_10000000000000000000000000000000');
final _command = CommandId.parse('cmd_00000000000000000000000000000000');
final _work = WorkItemId.parse('wrk_00000000000000000000000000000000');
final _approval = ApprovalId.parse('apr_00000000000000000000000000000000');
final _deferred =
    DeferredOperationId.parse('dop_00000000000000000000000000000000');
final _resource =
    RuntimeResourceId.parse('res_00000000000000000000000000000000');
