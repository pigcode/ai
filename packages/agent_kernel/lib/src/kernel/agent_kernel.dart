import 'dart:async';

import '../command/agent_command.dart';
import '../command/agent_command_receipt.dart';
import '../command/command_dedupe.dart';
import '../command/deferred_operation_commands.dart';
import '../command/run_commands.dart';
import '../command/runtime_resource_commands.dart';
import '../command/work_item_commands.dart';
import '../domain/agent_run.dart';
import '../domain/agent_session.dart';
import '../domain/approval.dart';
import '../domain/runtime_resource.dart';
import '../domain/work_item.dart';
import '../event/agent_error.dart';
import '../event/agent_event.dart';
import '../event/agent_event_metadata.dart';
import '../event/agent_event_type.dart';
import '../id/opaque_id.dart';
import '../id/opaque_id_generator.dart';
import '../json/canonical_json.dart';
import '../policy/agent_policy.dart';
import '../policy/approval_binding.dart';
import '../policy/policy_decision.dart';
import '../reducer/agent_reducer.dart';
import '../reducer/replay_violation.dart';
import '../store/agent_store.dart';
import '../store/agent_store_create_session_transaction.dart';
import '../store/agent_store_error.dart';
import '../store/agent_store_head.dart';
import '../store/agent_store_receipt.dart';
import '../store/agent_store_transaction.dart';
import '../stream/agent_event_cursor.dart';
import '../stream/agent_event_subscription.dart';
import '../stream/subscription_error.dart';
import '../time/agent_clock.dart';
import 'session_handle.dart';
import 'terminal_barrier.dart';
import 'terminal_proposal.dart';

final class AgentKernel {
  AgentKernel({
    required AgentStore store,
    required OpaqueIdGenerator idGenerator,
    required AgentClock clock,
    AgentStoreDurability durability = AgentStoreDurability.processCrashFlush,
  })  : _store = store,
        _idGenerator = idGenerator,
        _clock = clock,
        _durability = durability;

  final AgentStore _store;
  final OpaqueIdGenerator _idGenerator;
  final AgentClock _clock;
  final AgentStoreDurability _durability;
  final Map<SessionId, Set<AgentEventSubscription>> _subscriptions =
      <SessionId, Set<AgentEventSubscription>>{};
  static const _reducer = AgentReducer();

  Future<AgentCommandReceipt> createSession(
    CreateSessionCommand command,
  ) async {
    final contentDigest = _commandContentDigest(command);
    final existing = await _store.lookupCreateSessionCommand(command.commandId);
    if (existing != null) {
      final restored = restoreCommandReceipt(existing, contentDigest);
      return _withCurrentHandle(restored);
    }

    final sessionId = _idGenerator.generateSessionId();
    final eventId = _idGenerator.generateEventId();
    final event = AgentEvent(
      eventId: eventId,
      schemaVersion: 1,
      sessionId: sessionId,
      sequence: 1,
      recordedAt: _clock.wallTimeUtc,
      type: AgentEventType.sessionCreated,
      causationId: command.commandId,
      payload: <String, Object?>{
        'definitionRef': command.definitionRef.value,
        'capabilitySnapshot': command.capabilitySnapshot.toJson(),
      },
      metadata: AgentEventMetadata.empty(),
    );
    final persistedReceipt = AgentCommandReceipt(
      commandId: command.commandId,
      type: command.type,
      sessionId: sessionId,
      eventIds: <EventId>[eventId],
      acceptedThroughSequence: 1,
    );
    final transaction = AgentStoreCreateSessionTransaction(
      expectedRootHead: command.expectedRootHead,
      sessionId: sessionId,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: command.commandId,
        contentDigest: contentDigest,
        receipt: persistedReceipt.toJson(),
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(sessionId),
        AgentStoreIdAllocation(command.commandId),
        AgentStoreIdAllocation(eventId),
      ],
      events: <AgentEvent>[event],
    );

    try {
      final storeReceipt = await _store.createSession(
        transaction,
        requestedDurability: _durability,
      );
      final acceptedReceipt = await _restoreAcceptedCreateReceipt(
        command.commandId,
        contentDigest,
      );
      await _publishAcceptedCommandEvents(
        acceptedReceipt,
        localEvents: <AgentEvent>[event],
      );
      return _withHandle(acceptedReceipt, storeReceipt.sessionHead);
    } on AgentStoreException catch (error) {
      throw _mapStoreError(error);
    }
  }

  Future<AgentSessionHandle> openSession(SessionId sessionId) async {
    final session = await _store.loadSession(sessionId);
    return AgentSessionHandle(
      sessionId: sessionId,
      projectionGeneration: session.head.generation,
      head: session.head,
    );
  }

  Future<AgentSessionProjection> loadProjection(SessionId sessionId) async {
    final session = await _store.loadSession(sessionId);
    AgentSessionProjection? projection;
    var cursor = const AgentStoreCursor(0);
    final snapshot = session.snapshot;
    if (snapshot != null) {
      projection = _reducer.restoreSnapshot(snapshot);
      cursor = AgentStoreCursor(snapshot.sequence);
    } else if (session.head.historyFloorSequence > 0) {
      throw const ReplayViolation(
        'missing_compaction_snapshot',
        'Compacted Session recovery requires a retained snapshot.',
      );
    }
    while (true) {
      final page = await _store.readEvents(
        sessionId,
        after: cursor,
      );
      for (final event in page.events) {
        projection = projection == null
            ? _reducer.replay(<AgentEvent>[event])
            : _reducer.apply(projection, event);
      }
      if (page.nextCursor.sequence >= page.head.sequence) {
        break;
      }
      if (page.events.isEmpty) {
        throw const ReplayViolation(
          'event_page_did_not_advance',
          'Persisted event page did not advance to the Session head.',
        );
      }
      cursor = page.nextCursor;
    }
    if (projection == null) {
      throw const ReplayViolation(
        'empty_replay',
        'A Session replay requires session.created or a valid snapshot.',
      );
    }
    return projection;
  }

  Future<AgentCommandReceipt> startRun(StartRunCommand command) async {
    final contentDigest = _commandContentDigest(command);
    final existing = await _store.lookupAcceptedCommand(
      command.handle.sessionId,
      command.commandId,
    );
    if (existing != null) {
      final restored = restoreCommandReceipt(existing, contentDigest);
      return _withCurrentHandle(restored);
    }

    final loaded = await _store.loadSession(command.handle.sessionId);
    if (loaded.head != command.handle.head ||
        command.handle.projectionGeneration != loaded.head.generation) {
      throw _staleHandleError();
    }
    final projection = await loadProjection(command.handle.sessionId);
    if (projection.currentRunId != null) {
      throw _preconditionError('Session already has an active Run.');
    }

    final runId = _idGenerator.generateRunId();
    final createdEventId = _idGenerator.generateEventId();
    final inputEventId = _idGenerator.generateEventId();
    final firstSequence = loaded.head.sequence + 1;
    final events = <AgentEvent>[
      AgentEvent(
        eventId: createdEventId,
        schemaVersion: 1,
        sessionId: command.handle.sessionId,
        sequence: firstSequence,
        recordedAt: _clock.wallTimeUtc,
        type: AgentEventType.runCreated,
        runId: runId,
        causationId: command.commandId,
        payload: const <String, Object?>{},
        metadata: AgentEventMetadata.empty(),
      ),
      AgentEvent(
        eventId: inputEventId,
        schemaVersion: 1,
        sessionId: command.handle.sessionId,
        sequence: firstSequence + 1,
        recordedAt: _clock.wallTimeUtc,
        type: AgentEventType.runInputRecorded,
        runId: runId,
        causationId: command.commandId,
        payload: command.input,
        metadata: AgentEventMetadata.empty(),
      ),
    ];
    final persistedReceipt = AgentCommandReceipt(
      commandId: command.commandId,
      type: command.type,
      sessionId: command.handle.sessionId,
      runId: runId,
      eventIds: <EventId>[createdEventId, inputEventId],
      acceptedThroughSequence: firstSequence + 1,
    );
    final transaction = AgentStoreTransaction(
      sessionId: command.handle.sessionId,
      expectedHead: command.handle.head,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: command.commandId,
        contentDigest: contentDigest,
        receipt: persistedReceipt.toJson(),
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(command.commandId),
        AgentStoreIdAllocation(runId),
        AgentStoreIdAllocation(createdEventId),
        AgentStoreIdAllocation(inputEventId),
      ],
      events: events,
    );

    try {
      final storeReceipt = await _store.append(
        transaction,
        requestedDurability: _durability,
      );
      final acceptedReceipt = await _restoreAcceptedSessionReceipt(
        command.handle.sessionId,
        command.commandId,
        contentDigest,
      );
      await _publishAcceptedCommandEvents(
        acceptedReceipt,
        localEvents: events,
      );
      return _withHandle(acceptedReceipt, storeReceipt.afterHead);
    } on AgentStoreException catch (error) {
      throw _mapStoreError(error);
    }
  }

  Future<AgentCommandReceipt> cancelRun(CancelRunCommand command) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final loaded = prepared.loaded!;
    final projection = prepared.projection!;
    final firstSequence = loaded.head.sequence + 1;
    final events = <AgentEvent>[];
    var sequence = firstSequence;
    events.add(
      _runEvent(
        eventId: _idGenerator.generateEventId(),
        sessionId: command.handle.sessionId,
        sequence: sequence++,
        type: AgentEventType.runCancelRequested,
        runId: command.runId,
        causationId: command.commandId,
      ),
    );
    for (final approval in projection.approvals.values) {
      final work = projection.workItems[approval.workItemId];
      if (approval.state == ApprovalState.pending &&
          work?.runId == command.runId) {
        events.add(
          _runEvent(
            eventId: _idGenerator.generateEventId(),
            sessionId: command.handle.sessionId,
            sequence: sequence++,
            type: AgentEventType.workApprovalResolved,
            runId: command.runId,
            workItemId: work!.id,
            causationId: command.commandId,
            payload: const <String, Object?>{'decision': 'deny'},
          ),
        );
      }
    }
    return _appendRunCommand(command, prepared.contentDigest, events);
  }

  Future<AgentCommandReceipt> suspendRun(SuspendRunCommand command) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final loaded = prepared.loaded!;
    final projection = prepared.projection!;
    if (projection.capabilitySnapshot.value['durableCheckpointResume'] !=
        true) {
      throw _unsupportedError(
        'Session does not have durableCheckpointResume capability.',
      );
    }
    if (projection.runs[command.runId]!.state != AgentRunState.inProgress) {
      throw _preconditionError('Only an in-progress Run can suspend.');
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: loaded.head.sequence + 1,
          type: AgentEventType.runSuspendRequested,
          runId: command.runId,
          causationId: command.commandId,
        ),
      ],
    );
  }

  Future<AgentSessionHandle> recordSuspendedCheckpoint({
    required AgentSessionHandle handle,
    required RunId runId,
    required AttemptId attemptId,
    required OpaqueId causationId,
    required String checkpointReference,
  }) async {
    final loaded = await _store.loadSession(handle.sessionId);
    if (loaded.head != handle.head ||
        handle.projectionGeneration != loaded.head.generation) {
      throw _staleHandleError();
    }
    final projection = await loadProjection(handle.sessionId);
    final run = projection.runs[runId];
    if (projection.capabilitySnapshot.value['durableCheckpointResume'] !=
            true ||
        run == null ||
        run.state != AgentRunState.suspending ||
        run.currentAttemptId != attemptId) {
      throw _preconditionError(
        'Checkpoint does not match a suspending authoritative attempt.',
      );
    }
    final event = _runEvent(
      eventId: _idGenerator.generateEventId(),
      sessionId: handle.sessionId,
      sequence: loaded.head.sequence + 1,
      type: AgentEventType.runSuspended,
      runId: runId,
      attemptId: attemptId,
      causationId: causationId,
      payload: <String, Object?>{
        'checkpointReference': checkpointReference,
      },
    );
    try {
      final receipt = await _store.append(
        AgentStoreTransaction(
          sessionId: handle.sessionId,
          expectedHead: handle.head,
          newIdAllocations: <AgentStoreIdAllocation>[
            AgentStoreIdAllocation(event.eventId),
          ],
          events: <AgentEvent>[event],
        ),
        requestedDurability: _durability,
      );
      _publish(<AgentEvent>[event]);
      return AgentSessionHandle(
        sessionId: handle.sessionId,
        projectionGeneration: receipt.afterHead.generation,
        head: receipt.afterHead,
      );
    } on AgentStoreException catch (error) {
      throw _mapStoreError(error);
    }
  }

  Future<AgentCommandReceipt> resumeRunFromCheckpoint(
    ResumeRunFromCheckpointCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final loaded = prepared.loaded!;
    final projection = prepared.projection!;
    if (projection.capabilitySnapshot.value['durableCheckpointResume'] !=
        true) {
      throw _unsupportedError(
        'Session does not have durableCheckpointResume capability.',
      );
    }
    final run = projection.runs[command.runId]!;
    if (run.state != AgentRunState.suspended) {
      throw _preconditionError('Only a suspended Run can resume.');
    }
    final executionEpoch = run.attempts.values.fold<int>(
          0,
          (highest, attempt) => attempt.executionEpoch > highest
              ? attempt.executionEpoch
              : highest,
        ) +
        1;
    final attemptId = _idGenerator.generateAttemptId();
    final firstSequence = loaded.head.sequence + 1;
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: firstSequence,
          type: AgentEventType.runResumeRequested,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'checkpointReference': command.checkpointReference,
          },
        ),
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: firstSequence + 1,
          type: AgentEventType.runAttemptStarted,
          runId: command.runId,
          attemptId: attemptId,
          causationId: command.commandId,
          payload: <String, Object?>{'executionEpoch': executionEpoch},
        ),
      ],
      additionalAllocations: <OpaqueId>[attemptId],
    );
  }

  Future<AgentCommandReceipt> reconcileRun(
    ReconcileRunCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final loaded = prepared.loaded!;
    final projection = prepared.projection!;
    final state = projection.runs[command.runId]!.state;
    if (!const <AgentRunState>{
      AgentRunState.pending,
      AgentRunState.inProgress,
      AgentRunState.suspending,
      AgentRunState.resuming,
      AgentRunState.cancelling,
    }.contains(state)) {
      throw _preconditionError('Run cannot enter reconciliation from $state.');
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: loaded.head.sequence + 1,
          type: AgentEventType.runReconciling,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{'reason': command.reason},
        ),
      ],
    );
  }

  Future<AgentCommandReceipt> proposeWorkItem(
    ProposeWorkItemCommand command, {
    required AgentPolicy policy,
  }) async {
    if (command.request.runId != command.runId ||
        command.policyVersion != policy.version) {
      throw _preconditionError(
        'WorkItem request and policy version must match the command.',
      );
    }
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final workItemId = _idGenerator.generateWorkItemId();
    final firstSequence = prepared.loaded!.head.sequence + 1;
    final events = <AgentEvent>[
      _runEvent(
        eventId: _idGenerator.generateEventId(),
        sessionId: command.handle.sessionId,
        sequence: firstSequence,
        type: AgentEventType.workProposed,
        runId: command.runId,
        workItemId: workItemId,
        causationId: command.commandId,
        payload: <String, Object?>{
          'effectControl': command.request.effectControl.name,
          'toolIdentity': command.request.toolIdentity,
          'arguments': command.request.arguments,
        },
      ),
    ];
    ApprovalId? approvalId;
    if (command.request.effectControl == EffectControl.managed ||
        command.request.effectControl == EffectControl.interceptable) {
      final decision = policy.evaluate(command.request, _clock.wallTimeUtc);
      events.add(
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: firstSequence + 1,
          type: AgentEventType.workPolicyEvaluated,
          runId: command.runId,
          workItemId: workItemId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'decision': switch (decision.kind) {
              PolicyDecisionKind.allow => 'allow',
              PolicyDecisionKind.deny => 'deny',
              PolicyDecisionKind.requireApproval => 'requireApproval',
            },
            'policyVersion': decision.policyVersion,
          },
        ),
      );
      if (decision.kind == PolicyDecisionKind.requireApproval) {
        approvalId = _idGenerator.generateApprovalId();
        final binding = _approvalBinding(
          command.request,
          workItemId,
          policy.version,
        );
        events.add(
          _runEvent(
            eventId: _idGenerator.generateEventId(),
            sessionId: command.handle.sessionId,
            sequence: firstSequence + 2,
            type: AgentEventType.workApprovalRequested,
            runId: command.runId,
            workItemId: workItemId,
            causationId: command.commandId,
            payload: <String, Object?>{
              'approvalId': approvalId.value,
              'bindingDigest': binding.digest,
            },
          ),
        );
      }
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      events,
      additionalAllocations: <OpaqueId>[
        workItemId,
        if (approvalId != null) approvalId,
      ],
      receiptWorkItemId: workItemId,
      receiptApprovalId: approvalId,
    );
  }

  Future<AgentCommandReceipt> resolveApproval(
    ResolveApprovalCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final projection = prepared.projection!;
    final approval = projection.approvals[command.approvalId];
    final work =
        approval == null ? null : projection.workItems[approval.workItemId];
    if (approval == null ||
        approval.state != ApprovalState.pending ||
        work == null ||
        work.runId != command.runId ||
        approval.bindingDigest != command.binding.digest ||
        !command.binding.isValid(
          nowUtc: _clock.wallTimeUtc,
          currentPrincipal: command.currentPrincipal,
          runCancelled:
              projection.runs[command.runId]!.state == AgentRunState.cancelling,
        )) {
      throw _preconditionError('Approval binding is stale or invalid.');
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.workApprovalResolved,
          runId: command.runId,
          workItemId: work.id,
          causationId: command.commandId,
          payload: <String, Object?>{
            'decision':
                command.decision == ApprovalDecision.approve ? 'allow' : 'deny',
            'bindingDigest': command.binding.digest,
          },
        ),
      ],
      receiptWorkItemId: work.id,
      receiptApprovalId: approval.id,
    );
  }

  Future<AgentCommandReceipt> startWorkExecution(
    StartWorkExecutionCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final work = prepared.projection!.workItems[command.workItemId];
    if (work == null ||
        work.runId != command.runId ||
        (work.effectControl != EffectControl.managed &&
            work.effectControl != EffectControl.interceptable) ||
        (work.state != WorkItemState.policyEvaluated &&
            work.state != WorkItemState.approved)) {
      throw _preconditionError(
        'Only policy-authorized managed/interceptable WorkItems execute.',
      );
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.workExecutionStarted,
          runId: command.runId,
          workItemId: command.workItemId,
          causationId: command.commandId,
        ),
      ],
      receiptWorkItemId: command.workItemId,
    );
  }

  Future<AgentCommandReceipt> recordWorkItemOutcome(
    RecordWorkItemOutcomeCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final work = prepared.projection!.workItems[command.workItemId];
    if (work == null || work.runId != command.runId) {
      throw _preconditionError('WorkItem does not belong to the active Run.');
    }
    final outcome = recoverWorkItemOutcome(
      externalEffectSucceeded: command.externalEffectSucceededButResultMissing,
      resultPersisted: !command.externalEffectSucceededButResultMissing,
      reportedOutcome: command.outcome,
    );
    final eventType = switch (outcome) {
      WorkItemOutcome.succeeded => AgentEventType.workSucceeded,
      WorkItemOutcome.failed => AgentEventType.workFailed,
      WorkItemOutcome.cancelled => AgentEventType.workCancelled,
      WorkItemOutcome.outcomeUnknown => AgentEventType.workOutcomeUnknown,
    };
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: eventType,
          runId: command.runId,
          workItemId: command.workItemId,
          causationId: command.commandId,
        ),
      ],
      receiptWorkItemId: command.workItemId,
    );
  }

  Future<AgentCommandReceipt> createDeferredOperation(
    CreateDeferredOperationCommand command,
  ) async {
    if (!command.deadlineAt.isUtc) {
      throw _preconditionError('DeferredOperation deadline must be UTC.');
    }
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final id = _idGenerator.generateDeferredOperationId();
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.deferredCreated,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'deferredOperationId': id.value,
            'deadlineAt': command.deadlineAt.toIso8601String(),
            'cancellationPolicy': command.cancellationPolicy.name,
          },
        ),
      ],
      additionalAllocations: <OpaqueId>[id],
      receiptDeferredOperationId: id,
    );
  }

  Future<AgentCommandReceipt> transferDeferredOperation(
    TransferDeferredOperationCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final operation =
        prepared.projection!.deferredOperations[command.deferredOperationId];
    if (operation == null ||
        operation.originRunId != command.runId ||
        operation.state.isTerminal) {
      throw _preconditionError(
        'DeferredOperation is not transferable from this Run.',
      );
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.deferredOwnershipTransferred,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'deferredOperationId': command.deferredOperationId.value,
            'fromOwner': 'run',
            'owner': 'session',
          },
        ),
      ],
      receiptDeferredOperationId: command.deferredOperationId,
    );
  }

  Future<AgentCommandReceipt> recordDeferredOperationOutcome(
    RecordDeferredOperationOutcomeCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final operation =
        prepared.projection!.deferredOperations[command.deferredOperationId];
    if (operation == null || operation.originRunId != command.runId) {
      throw _preconditionError(
        'DeferredOperation does not belong to this Run.',
      );
    }
    final type = switch (command.outcome) {
      DeferredOperationOutcome.completed => AgentEventType.deferredCompleted,
      DeferredOperationOutcome.failed => AgentEventType.deferredFailed,
      DeferredOperationOutcome.cancelled => AgentEventType.deferredCancelled,
      DeferredOperationOutcome.outcomeUnknown =>
        AgentEventType.deferredOutcomeUnknown,
    };
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: type,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'deferredOperationId': command.deferredOperationId.value,
            'result': command.outcome.name,
          },
        ),
      ],
      receiptDeferredOperationId: command.deferredOperationId,
    );
  }

  Future<AgentCommandReceipt> registerRuntimeResource(
    RegisterRuntimeResourceCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final id = _idGenerator.generateRuntimeResourceId();
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.resourceRegistered,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'runtimeResourceId': id.value,
            'owner': 'run',
            'ownerRunId': command.runId.value,
          },
        ),
      ],
      additionalAllocations: <OpaqueId>[id],
      receiptRuntimeResourceId: id,
    );
  }

  Future<AgentCommandReceipt> transferRuntimeResource(
    TransferRuntimeResourceCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final resource = prepared.projection!.resources[command.runtimeResourceId];
    if (resource == null ||
        resource.owner != RuntimeResourceOwner.run ||
        resource.ownerRunId != command.runId) {
      throw _preconditionError(
        'RuntimeResource is not owned by this Run.',
      );
    }
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: AgentEventType.resourceOwnershipTransferred,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'runtimeResourceId': command.runtimeResourceId.value,
            'fromOwner': 'run',
            'owner': 'session',
          },
        ),
      ],
      receiptRuntimeResourceId: command.runtimeResourceId,
    );
  }

  Future<AgentCommandReceipt> recordRuntimeResourceOutcome(
    RecordRuntimeResourceOutcomeCommand command,
  ) async {
    final prepared = await _prepareRunCommand(command);
    if (prepared.restored != null) {
      return prepared.restored!;
    }
    final resource = prepared.projection!.resources[command.runtimeResourceId];
    if (resource == null || resource.originRunId != command.runId) {
      throw _preconditionError(
        'RuntimeResource does not belong to this Run.',
      );
    }
    final type = switch (command.outcome) {
      RuntimeResourceOutcome.released => AgentEventType.resourceReleased,
      RuntimeResourceOutcome.outcomeUnknown =>
        AgentEventType.resourceOutcomeUnknown,
    };
    return _appendRunCommand(
      command,
      prepared.contentDigest,
      <AgentEvent>[
        _runEvent(
          eventId: _idGenerator.generateEventId(),
          sessionId: command.handle.sessionId,
          sequence: prepared.loaded!.head.sequence + 1,
          type: type,
          runId: command.runId,
          causationId: command.commandId,
          payload: <String, Object?>{
            'runtimeResourceId': command.runtimeResourceId.value,
          },
        ),
      ],
      receiptRuntimeResourceId: command.runtimeResourceId,
    );
  }

  Future<AgentSessionHandle> commitTerminal({
    required AgentSessionHandle handle,
    required TerminalProposal proposal,
    required Map<String, int> drainedSourceWatermarks,
    Iterable<ObservedEffectBarrier> observedEffects =
        const <ObservedEffectBarrier>[],
    List<AgentEvent> leadingEvents = const <AgentEvent>[],
  }) async {
    final loaded = await _store.loadSession(handle.sessionId);
    if (loaded.head != handle.head ||
        handle.projectionGeneration != loaded.head.generation) {
      throw _staleHandleError();
    }
    var projection = await loadProjection(handle.sessionId);
    var nextSequence = loaded.head.sequence + 1;
    for (final event in leadingEvents) {
      if (event.sessionId != handle.sessionId ||
          event.sequence != nextSequence) {
        throw _preconditionError(
          'Terminal leading events must be a contiguous Session batch.',
        );
      }
      projection = _reducer.apply(projection, event);
      nextSequence += 1;
    }
    final barrier = const TerminalBarrier().evaluate(
      projection: projection,
      proposal: proposal,
      drainedSourceWatermarks: drainedSourceWatermarks,
      observedEffects: observedEffects,
    );
    if (!barrier.isReady) {
      throw _preconditionError(
        'Terminal barrier is blocked: '
        '${barrier.blockers.map((blocker) => blocker.name).join(',')}.',
      );
    }

    final terminalEventId = _idGenerator.generateEventId();
    final terminalEvent = AgentEvent(
      eventId: terminalEventId,
      schemaVersion: 1,
      sessionId: handle.sessionId,
      sequence: nextSequence,
      recordedAt: _clock.wallTimeUtc,
      type: switch (proposal.outcome) {
        TerminalOutcome.completed => AgentEventType.runCompleted,
        TerminalOutcome.failed => AgentEventType.runFailed,
        TerminalOutcome.cancelled => AgentEventType.runCancelled,
        TerminalOutcome.interrupted => AgentEventType.runInterrupted,
      },
      runId: proposal.runId,
      causationId: proposal.causationId,
      payload: proposal.payload,
      metadata: AgentEventMetadata.empty(),
    );
    _reducer.apply(projection, terminalEvent);
    final batch = <AgentEvent>[...leadingEvents, terminalEvent];

    try {
      final receipt = await _store.append(
        AgentStoreTransaction(
          sessionId: handle.sessionId,
          expectedHead: handle.head,
          newIdAllocations: <AgentStoreIdAllocation>[
            for (final event in batch) AgentStoreIdAllocation(event.eventId),
          ],
          events: batch,
        ),
        requestedDurability: _durability,
      );
      _publish(batch);
      return AgentSessionHandle(
        sessionId: handle.sessionId,
        projectionGeneration: receipt.afterHead.generation,
        head: receipt.afterHead,
      );
    } on AgentStoreException catch (error) {
      throw _mapStoreError(error);
    }
  }

  Future<AgentCommandReceipt> _withCurrentHandle(
    AgentCommandReceipt receipt,
  ) async {
    final session = await _store.loadSession(receipt.sessionId);
    return _withHandle(receipt, session.head);
  }

  AgentEventSubscription subscribeEvents({
    required SessionId sessionId,
    AgentEventCursor? cursor,
    RunId? runId,
    int queueLimit = 256,
  }) {
    late final AgentEventSubscription subscription;
    subscription = AgentEventSubscription(
      cursor: cursor ??
          AgentEventCursor(
            sessionId: sessionId,
            sequence: 0,
          ),
      runId: runId,
      queueLimit: queueLimit,
      onDetach: () {
        final subscriptions = _subscriptions[sessionId];
        subscriptions?.remove(subscription);
        if (subscriptions?.isEmpty ?? false) {
          _subscriptions.remove(sessionId);
        }
      },
    );
    (_subscriptions[sessionId] ??= <AgentEventSubscription>{})
        .add(subscription);
    unawaited(_replaySubscription(sessionId, subscription));
    return subscription;
  }

  Future<void> _replaySubscription(
    SessionId sessionId,
    AgentEventSubscription subscription,
  ) async {
    try {
      if (subscription.cursor.sessionId != sessionId) {
        subscription.fail(
          const SubscriptionError(
            SubscriptionErrorCode.sessionMismatch,
            'Cursor belongs to a different Session.',
          ),
        );
        return;
      }
      final session = await _store.loadSession(sessionId);
      if (subscription.cursor.sequence < session.head.historyFloorSequence) {
        subscription.fail(
          const SubscriptionError(
            SubscriptionErrorCode.cursorCompacted,
            'Cursor is below the retained history floor.',
          ),
        );
        return;
      }
      if (subscription.cursor.sequence > session.head.sequence) {
        subscription.fail(
          const SubscriptionError(
            SubscriptionErrorCode.sequenceConflict,
            'Cursor is ahead of the persisted Session head.',
          ),
        );
        return;
      }
      var afterSequence = subscription.cursor.sequence;
      if (afterSequence > session.head.historyFloorSequence &&
          subscription.cursor.eventId != null &&
          subscription.cursor.eventDigest != null) {
        afterSequence -= 1;
      }
      while (!subscription.isClosed) {
        final page = await _store.readEvents(
          sessionId,
          after: AgentStoreCursor(afterSequence),
        );
        for (final event in page.events) {
          subscription.acceptReplay(event);
          afterSequence = event.sequence;
        }
        if (afterSequence >= page.head.sequence) {
          break;
        }
        if (page.events.isEmpty) {
          subscription.fail(
            const SubscriptionError(
              SubscriptionErrorCode.sequenceConflict,
              'Persisted event page did not advance to the Session head.',
            ),
          );
          return;
        }
      }
      subscription.completeReplay();
    } on AgentStoreException catch (error) {
      subscription.fail(
        SubscriptionError(
          error.code == AgentStoreErrorCode.cursorCompacted
              ? SubscriptionErrorCode.cursorCompacted
              : SubscriptionErrorCode.closed,
          'Store could not establish the persisted event replay.',
        ),
      );
    }
  }

  void _publish(List<AgentEvent> events) {
    for (final event in events) {
      final subscriptions = List<AgentEventSubscription>.of(
        _subscriptions[event.sessionId] ?? const <AgentEventSubscription>{},
      );
      for (final subscription in subscriptions) {
        subscription.acceptLive(event);
      }
    }
  }

  AgentCommandReceipt _withHandle(
    AgentCommandReceipt receipt,
    AgentStoreHead head,
  ) =>
      AgentCommandReceipt(
        commandId: receipt.commandId,
        type: receipt.type,
        sessionId: receipt.sessionId,
        runId: receipt.runId,
        workItemId: receipt.workItemId,
        approvalId: receipt.approvalId,
        deferredOperationId: receipt.deferredOperationId,
        runtimeResourceId: receipt.runtimeResourceId,
        eventIds: receipt.eventIds,
        acceptedThroughSequence: receipt.acceptedThroughSequence,
        sessionHandle: AgentSessionHandle(
          sessionId: receipt.sessionId,
          projectionGeneration: head.generation,
          head: head,
        ),
      );

  Future<AgentCommandReceipt> _restoreAcceptedCreateReceipt(
    CommandId commandId,
    String contentDigest,
  ) async {
    final accepted = await _store.lookupCreateSessionCommand(commandId);
    if (accepted == null) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Committed create command is missing from the root registry.',
      );
    }
    return restoreCommandReceipt(accepted, contentDigest);
  }

  Future<AgentCommandReceipt> _restoreAcceptedSessionReceipt(
    SessionId sessionId,
    CommandId commandId,
    String contentDigest,
  ) async {
    final accepted = await _store.lookupAcceptedCommand(sessionId, commandId);
    if (accepted == null) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Committed command is missing from the Session registry.',
      );
    }
    return restoreCommandReceipt(accepted, contentDigest);
  }

  Future<void> _publishAcceptedCommandEvents(
    AgentCommandReceipt receipt, {
    required List<AgentEvent> localEvents,
  }) async {
    if (_sameEventIds(
      receipt.eventIds,
      localEvents.map((event) => event.eventId).toList(growable: false),
    )) {
      _publish(localEvents);
      return;
    }
    final firstSequence =
        receipt.acceptedThroughSequence - receipt.eventIds.length + 1;
    if (firstSequence <= 0) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Accepted command receipt has an invalid event range.',
      );
    }
    final persistedEvents = <AgentEvent>[];
    var cursor = AgentStoreCursor(firstSequence - 1);
    try {
      while (persistedEvents.length < receipt.eventIds.length) {
        final page = await _store.readEvents(
          receipt.sessionId,
          after: cursor,
          limit: receipt.eventIds.length - persistedEvents.length,
        );
        if (page.events.isEmpty) {
          throw const AgentStoreException(
            AgentStoreErrorCode.corruption,
            'Accepted command events are missing from the journal.',
          );
        }
        persistedEvents.addAll(page.events);
        cursor = page.nextCursor;
      }
    } on AgentStoreException catch (error) {
      if (error.code == AgentStoreErrorCode.cursorCompacted) return;
      rethrow;
    }
    if (!_sameEventIds(
      receipt.eventIds,
      persistedEvents.map((event) => event.eventId).toList(growable: false),
    )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Accepted command receipt does not match the journal.',
      );
    }
    _publish(persistedEvents);
  }

  bool _sameEventIds(List<EventId> left, List<EventId> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<_PreparedRunCommand> _prepareRunCommand(
    RunCommand command,
  ) async {
    final contentDigest = _commandContentDigest(command);
    final existing = await _store.lookupAcceptedCommand(
      command.handle.sessionId,
      command.commandId,
    );
    if (existing != null) {
      return _PreparedRunCommand(
        contentDigest: contentDigest,
        restored: await _withCurrentHandle(
          restoreCommandReceipt(existing, contentDigest),
        ),
      );
    }
    final loaded = await _store.loadSession(command.handle.sessionId);
    if (loaded.head != command.handle.head ||
        command.handle.projectionGeneration != loaded.head.generation) {
      throw _staleHandleError();
    }
    final projection = await loadProjection(command.handle.sessionId);
    if (projection.currentRunId != command.runId ||
        projection.runs[command.runId]?.state.isTerminal != false) {
      throw _preconditionError('Command does not target the active Run.');
    }
    return _PreparedRunCommand(
      contentDigest: contentDigest,
      loaded: loaded,
      projection: projection,
    );
  }

  Future<AgentCommandReceipt> _appendRunCommand(
    RunCommand command,
    String contentDigest,
    List<AgentEvent> events, {
    List<OpaqueId> additionalAllocations = const <OpaqueId>[],
    WorkItemId? receiptWorkItemId,
    ApprovalId? receiptApprovalId,
    DeferredOperationId? receiptDeferredOperationId,
    RuntimeResourceId? receiptRuntimeResourceId,
  }) async {
    var projection = await loadProjection(command.handle.sessionId);
    try {
      for (final event in events) {
        projection = _reducer.apply(projection, event);
      }
    } on ReplayViolation catch (error) {
      throw _preconditionError(error.message);
    }
    final persistedReceipt = AgentCommandReceipt(
      commandId: command.commandId,
      type: command.type,
      sessionId: command.handle.sessionId,
      runId: command.runId,
      workItemId: receiptWorkItemId,
      approvalId: receiptApprovalId,
      deferredOperationId: receiptDeferredOperationId,
      runtimeResourceId: receiptRuntimeResourceId,
      eventIds: events.map((event) => event.eventId).toList(),
      acceptedThroughSequence: events.last.sequence,
    );
    try {
      final receipt = await _store.append(
        AgentStoreTransaction(
          sessionId: command.handle.sessionId,
          expectedHead: command.handle.head,
          acceptedCommand: AgentStoreAcceptedCommand(
            commandId: command.commandId,
            contentDigest: contentDigest,
            receipt: persistedReceipt.toJson(),
          ),
          newIdAllocations: <AgentStoreIdAllocation>[
            AgentStoreIdAllocation(command.commandId),
            for (final id in additionalAllocations) AgentStoreIdAllocation(id),
            for (final event in events) AgentStoreIdAllocation(event.eventId),
          ],
          events: events,
        ),
        requestedDurability: _durability,
      );
      final acceptedReceipt = await _restoreAcceptedSessionReceipt(
        command.handle.sessionId,
        command.commandId,
        contentDigest,
      );
      await _publishAcceptedCommandEvents(
        acceptedReceipt,
        localEvents: events,
      );
      return _withHandle(acceptedReceipt, receipt.afterHead);
    } on AgentStoreException catch (error) {
      throw _mapStoreError(error);
    }
  }

  ApprovalBinding _approvalBinding(
    WorkItemRequest request,
    WorkItemId workItemId,
    String policyVersion,
  ) =>
      ApprovalBinding(
        principal: request.principal,
        workItemId: workItemId,
        toolIdentity: request.toolIdentity,
        arguments: request.arguments,
        workspaceScopeReference: request.workspaceScopeReference,
        environmentAllowlistDigest: request.environmentAllowlistDigest,
        capabilityGrantVersion: request.capabilityGrantVersion,
        policyVersion: policyVersion,
        expiresAt: request.approvalExpiresAt,
      );

  AgentEvent _runEvent({
    required EventId eventId,
    required SessionId sessionId,
    required int sequence,
    required AgentEventType type,
    required RunId runId,
    required OpaqueId causationId,
    AttemptId? attemptId,
    WorkItemId? workItemId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) =>
      AgentEvent(
        eventId: eventId,
        schemaVersion: 1,
        sessionId: sessionId,
        sequence: sequence,
        recordedAt: _clock.wallTimeUtc,
        type: type,
        runId: runId,
        attemptId: attemptId,
        workItemId: workItemId,
        causationId: causationId,
        payload: payload,
        metadata: AgentEventMetadata.empty(),
      );

  String _commandContentDigest(AgentCommand command) {
    validateSafePersistedJson(command.canonicalContent);
    return canonicalJsonSha256(command.canonicalContent);
  }

  AgentCommandError _mapStoreError(AgentStoreException error) {
    final stale = switch (error.code) {
      AgentStoreErrorCode.rootSequenceConflict ||
      AgentStoreErrorCode.rootStateDigestConflict ||
      AgentStoreErrorCode.sequenceConflict ||
      AgentStoreErrorCode.stateDigestConflict =>
        true,
      _ => false,
    };
    return AgentCommandError(
      code: stale ? AgentErrorCode.staleHandle : AgentErrorCode.unavailable,
      scope: AgentErrorScope.store,
      phase: AgentErrorPhase.acceptance,
      source: AgentErrorSource.store,
      retryDisposition: stale
          ? AgentRetryDisposition.afterRefresh
          : AgentRetryDisposition.reconcile,
      effect: stale ? AgentEffect.none : AgentEffect.unknown,
      safeMessage: stale
          ? 'Store head changed; refresh the handle before retrying.'
          : 'Store mutation did not return a durable receipt.',
      namespacedDetails: AgentEventMetadata.empty(),
    );
  }

  AgentCommandError _staleHandleError() => AgentCommandError(
        code: AgentErrorCode.staleHandle,
        scope: AgentErrorScope.session,
        phase: AgentErrorPhase.validation,
        source: AgentErrorSource.kernel,
        retryDisposition: AgentRetryDisposition.afterRefresh,
        effect: AgentEffect.none,
        safeMessage: 'Session handle is stale.',
        namespacedDetails: AgentEventMetadata.empty(),
      );

  AgentCommandError _preconditionError(String message) => AgentCommandError(
        code: AgentErrorCode.preconditionFailed,
        scope: AgentErrorScope.session,
        phase: AgentErrorPhase.validation,
        source: AgentErrorSource.kernel,
        retryDisposition: AgentRetryDisposition.afterRefresh,
        effect: AgentEffect.none,
        safeMessage: message,
        namespacedDetails: AgentEventMetadata.empty(),
      );

  AgentCommandError _unsupportedError(String message) => AgentCommandError(
        code: AgentErrorCode.unsupported,
        scope: AgentErrorScope.run,
        phase: AgentErrorPhase.validation,
        source: AgentErrorSource.kernel,
        retryDisposition: AgentRetryDisposition.never,
        effect: AgentEffect.none,
        safeMessage: message,
        namespacedDetails: AgentEventMetadata.empty(),
      );
}

final class _PreparedRunCommand {
  const _PreparedRunCommand({
    required this.contentDigest,
    this.loaded,
    this.projection,
    this.restored,
  });

  final String contentDigest;
  final AgentStoreSession? loaded;
  final AgentSessionProjection? projection;
  final AgentCommandReceipt? restored;
}
