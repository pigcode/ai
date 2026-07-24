import '../domain/agent_definition.dart';
import '../domain/agent_run.dart';
import '../domain/agent_session.dart';
import '../domain/approval.dart';
import '../domain/capability_snapshot.dart';
import '../domain/deferred_operation.dart';
import '../domain/run_attempt.dart';
import '../domain/runtime_resource.dart';
import '../domain/work_item.dart';
import '../event/agent_event.dart';
import '../event/agent_event_type.dart';
import '../id/opaque_id.dart';
import '../json/canonical_json.dart';
import '../store/agent_store_snapshot.dart';
import 'replay_violation.dart';

final class AgentReducer {
  const AgentReducer();

  AgentSessionProjection replay(Iterable<AgentEvent> events) {
    AgentSessionProjection? projection;
    for (final event in events) {
      projection =
          projection == null ? _createSession(event) : apply(projection, event);
    }
    if (projection == null) {
      throw const ReplayViolation(
        'empty_replay',
        'A Session replay requires session.created.',
      );
    }
    return projection;
  }

  AgentSessionProjection restoreSnapshot(AgentStoreSnapshot snapshot) {
    if (snapshot.reducerSchemaVersion != 1) {
      throw const ReplayViolation(
        'unsupported_snapshot_reducer',
        'Snapshot reducerSchemaVersion is unsupported.',
      );
    }
    try {
      final projection = AgentSessionProjection.fromJson(
        snapshot.canonicalProjection,
      );
      if (projection.id != snapshot.sessionId ||
          projection.journalSequence != snapshot.sequence) {
        throw const FormatException(
          'Snapshot envelope does not bind its projection.',
        );
      }
      return projection;
    } on FormatException {
      throw const ReplayViolation(
        'invalid_snapshot_projection',
        'Snapshot projection is not a valid reducer state.',
      );
    }
  }

  AgentSessionProjection apply(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    if (event.sessionId != current.id) {
      throw _violation(event, 'session_mismatch', 'SessionId changed.');
    }
    if (event.sequence != current.journalSequence + 1) {
      throw _violation(
        event,
        'event_sequence_violation',
        'Event sequence is not the next Session sequence.',
      );
    }
    if (event.type == AgentEventType.sessionCreated) {
      throw _violation(
        event,
        'duplicate_session_created',
        'session.created may appear only once.',
      );
    }

    final run = event.runId == null ? null : current.runs[event.runId];
    if (event.type.runBusinessEvent && run != null && run.state.isTerminal) {
      throw _violation(
        event,
        'terminal_run_mutation',
        'Run business event followed a terminal event.',
      );
    }

    var next = current;
    if (event.type.family == AgentEventFamily.session) {
      next = _applySession(next, event);
    } else if (event.type.family == AgentEventFamily.run ||
        event.type.family == AgentEventFamily.runTerminal) {
      next = _applyRun(next, event);
    } else if (event.type.family == AgentEventFamily.work) {
      next = _applyWork(next, event);
    } else if (event.type.family == AgentEventFamily.deferred) {
      next = _applyDeferred(next, event);
    } else if (event.type.family == AgentEventFamily.resource) {
      next = _applyResource(next, event);
    } else if (event.type.runBusinessEvent) {
      _requireActiveRun(next, event);
    }
    return next.copyWith(journalSequence: event.sequence);
  }

  AgentSessionProjection _createSession(AgentEvent event) {
    if (event.type != AgentEventType.sessionCreated || event.sequence != 1) {
      throw _violation(
        event,
        'invalid_session_genesis',
        'The first event must be session.created at sequence 1.',
      );
    }
    return AgentSessionProjection(
      id: event.sessionId,
      journalSequence: 1,
      definitionRef: _definitionRef(event),
      capabilitySnapshot: _capabilitySnapshot(event),
      conversationAvailability: ConversationAvailability.available,
      controlAttachment: ControlAttachment.attached,
      runtimeLiveness: RuntimeLiveness.unknown,
      resumeStateAvailability: ResumeStateAvailability.none,
      currentRunId: null,
      runs: const <RunId, AgentRun>{},
      runHistory: const <RunId>[],
      workItems: const <WorkItemId, WorkItem>{},
      approvals: const <ApprovalId, Approval>{},
      deferredOperations: const <DeferredOperationId, DeferredOperation>{},
      resources: const <RuntimeResourceId, RuntimeResource>{},
    );
  }

  AgentSessionProjection _applySession(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    return switch (event.type) {
      AgentEventType.sessionCapabilitiesPinned => current.copyWith(
          capabilitySnapshot: _capabilitySnapshot(event),
        ),
      AgentEventType.sessionAttachmentChanged => current.copyWith(
          controlAttachment: event.payload['attached'] == false
              ? ControlAttachment.detached
              : ControlAttachment.attached,
        ),
      AgentEventType.sessionRuntimeLivenessChanged => current.copyWith(
          runtimeLiveness: switch (event.payload['state']) {
            'alive' => RuntimeLiveness.alive,
            'stopped' => RuntimeLiveness.stopped,
            _ => RuntimeLiveness.unknown,
          },
        ),
      AgentEventType.sessionResumeStateStored => current.copyWith(
          resumeStateAvailability: ResumeStateAvailability.stored,
        ),
      AgentEventType.sessionTombstoned => current.copyWith(
          conversationAvailability: ConversationAvailability.tombstoned,
        ),
      _ => current,
    };
  }

  AgentDefinitionRef? _definitionRef(AgentEvent event) {
    final value = event.payload['definitionRef'];
    return value is String ? AgentDefinitionRef(value) : null;
  }

  CapabilitySnapshot _capabilitySnapshot(AgentEvent event) {
    final value = event.payload['capabilitySnapshot'];
    return value is Map<String, Object?>
        ? CapabilitySnapshot(value)
        : CapabilitySnapshot.empty();
  }

  AgentSessionProjection _applyRun(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    final runId = event.runId!;
    if (event.type == AgentEventType.runCreated) {
      if (current.currentRunId != null) {
        throw _violation(
          event,
          'active_run_exists',
          'A Session already has a nonterminal Run.',
        );
      }
      if (current.runs.containsKey(runId)) {
        throw _violation(event, 'duplicate_run', 'RunId already exists.');
      }
      return current.copyWith(
        currentRunId: runId,
        runs: <RunId, AgentRun>{
          ...current.runs,
          runId: AgentRun(id: runId, state: AgentRunState.pending),
        },
        runHistory: <RunId>[...current.runHistory, runId],
      );
    }

    final run = current.runs[runId];
    if (run == null || current.currentRunId != runId) {
      throw _violation(
        event,
        run?.state.isTerminal == true
            ? 'terminal_run_mutation'
            : 'run_not_active',
        'Run event does not target the active Run.',
      );
    }
    final updated = _transitionRun(run, event);
    return current.copyWith(
      clearCurrentRun: updated.state.isTerminal,
      runs: <RunId, AgentRun>{...current.runs, runId: updated},
    );
  }

  AgentRun _transitionRun(AgentRun run, AgentEvent event) {
    if (event.type == AgentEventType.runInputRecorded) {
      _requireState(run, event, const <AgentRunState>{AgentRunState.pending});
      return run;
    }
    if (event.type == AgentEventType.runAttemptStarted) {
      _requireState(
        run,
        event,
        const <AgentRunState>{
          AgentRunState.pending,
          AgentRunState.resuming,
          AgentRunState.reconciling,
        },
      );
      final attemptId = event.attemptId!;
      if (run.attempts.containsKey(attemptId)) {
        throw _violation(
          event,
          'duplicate_attempt',
          'AttemptId already exists in this Run.',
        );
      }
      final highestEpoch = run.attempts.values.fold<int>(
        0,
        (highest, attempt) =>
            attempt.executionEpoch > highest ? attempt.executionEpoch : highest,
      );
      final suppliedEpoch = event.payload['executionEpoch'];
      final executionEpoch =
          suppliedEpoch is int ? suppliedEpoch : highestEpoch + 1;
      if (executionEpoch <= highestEpoch) {
        throw _violation(
          event,
          'execution_epoch_violation',
          'Attempt executionEpoch must increase.',
        );
      }
      final attempts = <AttemptId, RunAttempt>{...run.attempts};
      final previousId = run.currentAttemptId;
      if (previousId != null) {
        attempts[previousId] =
            attempts[previousId]!.copyWith(state: RunAttemptState.fenced);
      }
      attempts[attemptId] = RunAttempt(
        id: attemptId,
        state: RunAttemptState.started,
        executionEpoch: executionEpoch,
      );
      return run.copyWith(
        attempts: attempts,
        currentAttemptId: attemptId,
      );
    }
    if (event.type.requiresAttemptId &&
        run.currentAttemptId != event.attemptId) {
      throw _violation(
        event,
        'attempt_mismatch',
        'Run event does not match the current attempt.',
      );
    }
    final nextState = switch (event.type) {
      AgentEventType.runStarted => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.pending,
            AgentRunState.suspending,
            AgentRunState.resuming,
            AgentRunState.reconciling,
          },
          AgentRunState.inProgress,
        ),
      AgentEventType.runCancelRequested => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.pending,
            AgentRunState.inProgress,
            AgentRunState.suspending,
            AgentRunState.suspended,
            AgentRunState.resuming,
            AgentRunState.reconciling,
          },
          AgentRunState.cancelling,
        ),
      AgentEventType.runSuspendRequested => _from(
          run,
          event,
          const <AgentRunState>{AgentRunState.inProgress},
          AgentRunState.suspending,
        ),
      AgentEventType.runSuspended => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.suspending,
            AgentRunState.resuming,
          },
          AgentRunState.suspended,
        ),
      AgentEventType.runResumeRequested => _from(
          run,
          event,
          const <AgentRunState>{AgentRunState.suspended},
          AgentRunState.resuming,
        ),
      AgentEventType.runReconciling => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.pending,
            AgentRunState.inProgress,
            AgentRunState.suspending,
            AgentRunState.resuming,
            AgentRunState.cancelling,
          },
          AgentRunState.reconciling,
        ),
      AgentEventType.runCompleted => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.inProgress,
            AgentRunState.suspending,
            AgentRunState.resuming,
            AgentRunState.cancelling,
            AgentRunState.reconciling,
          },
          AgentRunState.completed,
        ),
      AgentEventType.runFailed => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.pending,
            AgentRunState.inProgress,
            AgentRunState.suspending,
            AgentRunState.resuming,
            AgentRunState.cancelling,
            AgentRunState.reconciling,
          },
          AgentRunState.failed,
        ),
      AgentEventType.runCancelled => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.cancelling,
            AgentRunState.reconciling,
          },
          AgentRunState.cancelled,
        ),
      AgentEventType.runInterrupted => _from(
          run,
          event,
          const <AgentRunState>{
            AgentRunState.inProgress,
            AgentRunState.cancelling,
            AgentRunState.reconciling,
          },
          AgentRunState.interrupted,
        ),
      _ => throw _violation(
          event,
          'unsupported_run_event',
          'Event is not a Run state transition.',
        ),
    };
    var attempts = run.attempts;
    final currentAttemptId = run.currentAttemptId;
    if (currentAttemptId != null &&
        (event.type == AgentEventType.runStarted || nextState.isTerminal)) {
      attempts = <AttemptId, RunAttempt>{
        ...attempts,
        currentAttemptId: attempts[currentAttemptId]!.copyWith(
          state: nextState.isTerminal
              ? RunAttemptState.terminal
              : RunAttemptState.active,
        ),
      };
    }
    return run.copyWith(
      state: nextState,
      attempts: attempts,
      terminalEventId: nextState.isTerminal ? event.eventId : null,
    );
  }

  AgentSessionProjection _applyWork(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    _requireActiveRun(current, event);
    final workItemId = event.workItemId!;
    final existing = current.workItems[workItemId];
    if (event.type == AgentEventType.workProposed) {
      if (existing != null) {
        throw _violation(
          event,
          'duplicate_work_item',
          'WorkItemId already exists.',
        );
      }
      final effectControl = switch (event.payload['effectControl']) {
        'interceptable' => EffectControl.interceptable,
        'observedOnly' => EffectControl.observedOnly,
        'unknown' => EffectControl.unknown,
        _ => EffectControl.managed,
      };
      return current.copyWith(
        workItems: <WorkItemId, WorkItem>{
          ...current.workItems,
          workItemId: WorkItem(
            id: workItemId,
            runId: event.runId!,
            state: WorkItemState.proposed,
            effectControl: effectControl,
          ),
        },
      );
    }
    if (existing == null || existing.runId != event.runId) {
      throw _violation(
        event,
        'work_item_not_found',
        'Work event does not target a WorkItem in this Run.',
      );
    }
    if (existing.state.isTerminal) {
      throw _violation(
        event,
        'terminal_work_item_mutation',
        'Work event followed a terminal WorkItem event.',
      );
    }

    var approvals = current.approvals;
    WorkItem updated;
    switch (event.type) {
      case AgentEventType.workPolicyEvaluated:
        _requireWorkState(
          existing,
          event,
          const <WorkItemState>{WorkItemState.proposed},
        );
        updated = existing.copyWith(
          state: event.payload['decision'] == 'deny'
              ? WorkItemState.denied
              : WorkItemState.policyEvaluated,
        );
      case AgentEventType.workApprovalRequested:
        _requireWorkState(
          existing,
          event,
          const <WorkItemState>{WorkItemState.policyEvaluated},
        );
        final approvalId =
            ApprovalId.parse(event.payload['approvalId']! as String);
        if (approvals.containsKey(approvalId)) {
          throw _violation(
            event,
            'duplicate_approval',
            'ApprovalId already exists.',
          );
        }
        updated = existing.copyWith(
          state: WorkItemState.awaitingApproval,
          approvalId: approvalId,
        );
        approvals = <ApprovalId, Approval>{
          ...approvals,
          approvalId: Approval(
            id: approvalId,
            workItemId: workItemId,
            state: ApprovalState.pending,
            bindingDigest: event.payload['bindingDigest'] as String?,
          ),
        };
      case AgentEventType.workApprovalResolved:
        _requireWorkState(
          existing,
          event,
          const <WorkItemState>{WorkItemState.awaitingApproval},
        );
        final approvalId = existing.approvalId!;
        final approval = approvals[approvalId];
        if (approval == null || approval.state != ApprovalState.pending) {
          throw _violation(
            event,
            'approval_not_pending',
            'WorkItem approval is missing or already resolved.',
          );
        }
        final denied = event.payload['decision'] == 'deny';
        updated = existing.copyWith(
          state: denied ? WorkItemState.denied : WorkItemState.approved,
        );
        approvals = <ApprovalId, Approval>{
          ...approvals,
          approvalId: approval.copyWith(
            state: denied ? ApprovalState.denied : ApprovalState.approved,
          ),
        };
      case AgentEventType.workExecutionStarted:
        _requireWorkState(
          existing,
          event,
          const <WorkItemState>{
            WorkItemState.policyEvaluated,
            WorkItemState.approved,
          },
        );
        updated = existing.copyWith(state: WorkItemState.executing);
      case AgentEventType.workCancellationRequested:
        _requireWorkState(
          existing,
          event,
          const <WorkItemState>{WorkItemState.executing},
        );
        updated = existing.copyWith(state: WorkItemState.cancellationRequested);
      case AgentEventType.workSucceeded:
        _requireWorkOutcomeState(existing, event);
        updated = existing.copyWith(state: WorkItemState.succeeded);
      case AgentEventType.workFailed:
        _requireWorkOutcomeState(existing, event);
        updated = existing.copyWith(state: WorkItemState.failed);
      case AgentEventType.workCancelled:
        _requireWorkOutcomeState(existing, event);
        updated = existing.copyWith(state: WorkItemState.cancelled);
      case AgentEventType.workOutcomeUnknown:
        _requireWorkOutcomeState(existing, event);
        updated = existing.copyWith(state: WorkItemState.outcomeUnknown);
      default:
        throw _violation(
          event,
          'unsupported_work_event',
          'Event is not a WorkItem transition.',
        );
    }
    return current.copyWith(
      workItems: <WorkItemId, WorkItem>{
        ...current.workItems,
        workItemId: updated,
      },
      approvals: approvals,
    );
  }

  AgentSessionProjection _applyDeferred(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    _requireActiveRun(current, event);
    final id = DeferredOperationId.parse(
      event.payload['deferredOperationId']! as String,
    );
    final existing = current.deferredOperations[id];
    if (event.type == AgentEventType.deferredCreated) {
      if (existing != null) {
        throw _violation(
          event,
          'duplicate_deferred_operation',
          'DeferredOperationId already exists.',
        );
      }
      return current.copyWith(
        deferredOperations: <DeferredOperationId, DeferredOperation>{
          ...current.deferredOperations,
          id: DeferredOperation(
            id: id,
            originRunId: event.runId!,
            owner: DeferredOperationOwner.run,
            state: DeferredOperationState.pending,
            cancellationPolicy: switch (event.payload['cancellationPolicy']) {
              'transferToSession' =>
                DeferredCancellationPolicy.transferToSession,
              'manual' => DeferredCancellationPolicy.manual,
              _ => DeferredCancellationPolicy.cancelWithOwner,
            },
            deadlineAt: event.payload['deadlineAt'] is String
                ? DateTime.parse(event.payload['deadlineAt']! as String).toUtc()
                : null,
          ),
        },
      );
    }
    if (existing == null || existing.originRunId != event.runId) {
      throw _violation(
        event,
        'deferred_operation_not_found',
        'Deferred event does not target an operation in this Run.',
      );
    }
    if (existing.state.isTerminal) {
      final digest = _eventMutationDigest(event);
      if (existing.terminalDigest == digest) {
        return current;
      }
      throw _violation(
        event,
        'terminal_deferred_operation_mutation',
        'Deferred event followed a terminal operation event.',
      );
    }

    final mutationDigest = _eventMutationDigest(event);
    final updated = switch (event.type) {
      AgentEventType.deferredOwnershipTransferred =>
        _transferDeferred(existing, event),
      AgentEventType.deferredCompleted => existing.copyWith(
          state: DeferredOperationState.completed,
          terminalDigest: mutationDigest,
          terminalResult: event.payload['result'],
        ),
      AgentEventType.deferredFailed => existing.copyWith(
          state: DeferredOperationState.failed,
          terminalDigest: mutationDigest,
          terminalResult: event.payload['result'],
        ),
      AgentEventType.deferredCancelled => existing.copyWith(
          state: DeferredOperationState.cancelled,
          terminalDigest: mutationDigest,
          terminalResult: event.payload['result'],
        ),
      AgentEventType.deferredOutcomeUnknown => existing.copyWith(
          state: DeferredOperationState.outcomeUnknown,
          terminalDigest: mutationDigest,
          terminalResult: event.payload['result'],
        ),
      _ => throw _violation(
          event,
          'unsupported_deferred_event',
          'Event is not a DeferredOperation transition.',
        ),
    };
    return current.copyWith(
      deferredOperations: <DeferredOperationId, DeferredOperation>{
        ...current.deferredOperations,
        id: updated,
      },
    );
  }

  DeferredOperation _transferDeferred(
    DeferredOperation operation,
    AgentEvent event,
  ) {
    final digest = _eventMutationDigest(event);
    if (operation.owner == DeferredOperationOwner.session) {
      if (operation.ownershipTransferDigest == digest) {
        return operation;
      }
      throw _violation(
        event,
        'deferred_owner_mismatch',
        'DeferredOperation was transferred with different content.',
      );
    }
    if (operation.owner != DeferredOperationOwner.run ||
        (event.payload['fromOwner'] != null &&
            event.payload['fromOwner'] != 'run') ||
        (event.payload['owner'] != null &&
            event.payload['owner'] != 'session')) {
      throw _violation(
        event,
        'deferred_owner_mismatch',
        'DeferredOperation ownership transfer must be Run to Session.',
      );
    }
    return operation.copyWith(
      owner: DeferredOperationOwner.session,
      ownershipTransferDigest: digest,
    );
  }

  AgentSessionProjection _applyResource(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    final id = RuntimeResourceId.parse(
      event.payload['runtimeResourceId']! as String,
    );
    final existing = current.resources[id];
    if (event.type == AgentEventType.resourceRegistered && existing != null) {
      throw _violation(
        event,
        'duplicate_resource',
        'RuntimeResourceId already exists.',
      );
    }
    if (event.type != AgentEventType.resourceRegistered && existing == null) {
      throw _violation(
        event,
        'resource_not_found',
        'RuntimeResource does not exist.',
      );
    }
    if (existing != null &&
        (existing.state == RuntimeResourceState.released ||
            existing.state == RuntimeResourceState.outcomeUnknown)) {
      final digest = _eventMutationDigest(event);
      if (existing.terminalDigest == digest) {
        return current;
      }
      throw _violation(
        event,
        'terminal_resource_mutation',
        'Resource event followed a terminal resource event.',
      );
    }

    final RuntimeResource updated;
    if (event.type == AgentEventType.resourceRegistered) {
      final owner = event.payload['owner'] == 'run'
          ? RuntimeResourceOwner.run
          : RuntimeResourceOwner.session;
      final ownerRunValue = event.payload['ownerRunId'];
      final ownerRunId =
          ownerRunValue is String ? RunId.parse(ownerRunValue) : null;
      if (owner == RuntimeResourceOwner.run &&
          (ownerRunId == null ||
              current.currentRunId != ownerRunId ||
              current.runs[ownerRunId]!.state.isTerminal)) {
        throw _violation(
          event,
          'resource_owner_mismatch',
          'Run-owned resource must target the active Run.',
        );
      }
      updated = RuntimeResource(
        id: id,
        state: RuntimeResourceState.registered,
        owner: owner,
        originRunId: ownerRunId,
        ownerRunId: ownerRunId,
      );
    } else if (event.type == AgentEventType.resourceOwnershipTransferred) {
      final digest = _eventMutationDigest(event);
      if (existing!.owner == RuntimeResourceOwner.session) {
        if (existing.ownershipTransferDigest == digest) {
          return current;
        }
        throw _violation(
          event,
          'resource_owner_mismatch',
          'RuntimeResource was transferred with different content.',
        );
      }
      if (existing.owner != RuntimeResourceOwner.run ||
          (event.payload['fromOwner'] != null &&
              event.payload['fromOwner'] != 'run') ||
          (event.payload['owner'] != null &&
              event.payload['owner'] != 'session')) {
        throw _violation(
          event,
          'resource_owner_mismatch',
          'RuntimeResource ownership transfer must be Run to Session.',
        );
      }
      updated = existing.copyWith(
        state: RuntimeResourceState.active,
        owner: RuntimeResourceOwner.session,
        clearOwnerRun: true,
        ownershipTransferDigest: digest,
      );
    } else {
      final state = switch (event.type) {
        AgentEventType.resourceUpdated => RuntimeResourceState.active,
        AgentEventType.resourceReleased => RuntimeResourceState.released,
        AgentEventType.resourceOutcomeUnknown =>
          RuntimeResourceState.outcomeUnknown,
        _ => throw _violation(
            event,
            'unsupported_resource_event',
            'Event is not a resource transition.',
          ),
      };
      updated = existing!.copyWith(
        state: state,
        terminalDigest: state == RuntimeResourceState.released ||
                state == RuntimeResourceState.outcomeUnknown
            ? _eventMutationDigest(event)
            : null,
      );
    }
    return current.copyWith(
      resources: <RuntimeResourceId, RuntimeResource>{
        ...current.resources,
        id: updated,
      },
    );
  }

  String _eventMutationDigest(AgentEvent event) =>
      canonicalJsonSha256(<String, Object?>{
        'type': event.type.wireName,
        'payload': event.payload,
      });

  void _requireActiveRun(
    AgentSessionProjection current,
    AgentEvent event,
  ) {
    if (event.runId == null ||
        current.currentRunId != event.runId ||
        current.runs[event.runId]!.state.isTerminal) {
      throw _violation(
        event,
        'run_not_active',
        'Run business event does not target the active Run.',
      );
    }
  }

  void _requireWorkOutcomeState(WorkItem workItem, AgentEvent event) {
    if ((workItem.effectControl == EffectControl.observedOnly ||
            workItem.effectControl == EffectControl.unknown) &&
        workItem.state == WorkItemState.proposed) {
      return;
    }
    _requireWorkState(
      workItem,
      event,
      const <WorkItemState>{
        WorkItemState.executing,
        WorkItemState.cancellationRequested,
      },
    );
  }

  void _requireWorkState(
    WorkItem workItem,
    AgentEvent event,
    Set<WorkItemState> allowed,
  ) {
    if (!allowed.contains(workItem.state)) {
      throw _violation(
        event,
        'illegal_work_transition',
        'WorkItem state ${workItem.state.name} rejects '
            '${event.type.wireName}.',
      );
    }
  }

  AgentRunState _from(
    AgentRun run,
    AgentEvent event,
    Set<AgentRunState> allowed,
    AgentRunState next,
  ) {
    _requireState(run, event, allowed);
    return next;
  }

  void _requireState(
    AgentRun run,
    AgentEvent event,
    Set<AgentRunState> allowed,
  ) {
    if (!allowed.contains(run.state)) {
      throw _violation(
        event,
        'illegal_run_transition',
        'Run state ${run.state.name} rejects ${event.type.wireName}.',
      );
    }
  }

  ReplayViolation _violation(
    AgentEvent event,
    String code,
    String message,
  ) =>
      ReplayViolation(
        code,
        message,
        sequence: event.sequence,
        eventType: event.type.wireName,
      );
}
