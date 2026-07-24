enum AgentEventFamily {
  session,
  run,
  runTerminal,
  work,
  deferred,
  resource,
  driverAudit,
}

enum AgentPayloadContextId {
  approvalId,
  deferredOperationId,
  runtimeResourceId,
}

enum AgentEventType {
  sessionCreated(
    'session.created',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  sessionCapabilitiesPinned(
    'session.capabilitiesPinned',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  sessionAttachmentChanged(
    'session.attachmentChanged',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  sessionRuntimeLivenessChanged(
    'session.runtimeLivenessChanged',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  sessionResumeStateStored(
    'session.resumeStateStored',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  sessionTombstoned(
    'session.tombstoned',
    AgentEventFamily.session,
    allowedAfterRunTerminal: true,
  ),
  runCreated(
    'run.created',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runInputRecorded(
    'run.inputRecorded',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runAttemptStarted(
    'run.attemptStarted',
    AgentEventFamily.run,
    requiresRunId: true,
    requiresAttemptId: true,
    runBusinessEvent: true,
  ),
  runStarted(
    'run.started',
    AgentEventFamily.run,
    requiresRunId: true,
    requiresAttemptId: true,
    runBusinessEvent: true,
  ),
  runCancelRequested(
    'run.cancelRequested',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runSuspendRequested(
    'run.suspendRequested',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runSuspended(
    'run.suspended',
    AgentEventFamily.run,
    requiresRunId: true,
    requiresAttemptId: true,
    runBusinessEvent: true,
  ),
  runResumeRequested(
    'run.resumeRequested',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runReconciling(
    'run.reconciling',
    AgentEventFamily.run,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  runCompleted(
    'run.completed',
    AgentEventFamily.runTerminal,
    requiresRunId: true,
    terminal: true,
    runBusinessEvent: true,
  ),
  runFailed(
    'run.failed',
    AgentEventFamily.runTerminal,
    requiresRunId: true,
    terminal: true,
    runBusinessEvent: true,
  ),
  runCancelled(
    'run.cancelled',
    AgentEventFamily.runTerminal,
    requiresRunId: true,
    terminal: true,
    runBusinessEvent: true,
  ),
  runInterrupted(
    'run.interrupted',
    AgentEventFamily.runTerminal,
    requiresRunId: true,
    terminal: true,
    runBusinessEvent: true,
  ),
  workProposed(
    'work.proposed',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workPolicyEvaluated(
    'work.policyEvaluated',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workApprovalRequested(
    'work.approvalRequested',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    requiredPayloadId: AgentPayloadContextId.approvalId,
    runBusinessEvent: true,
  ),
  workApprovalResolved(
    'work.approvalResolved',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workExecutionStarted(
    'work.executionStarted',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workCancellationRequested(
    'work.cancellationRequested',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workSucceeded(
    'work.succeeded',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workFailed(
    'work.failed',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workCancelled(
    'work.cancelled',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  workOutcomeUnknown(
    'work.outcomeUnknown',
    AgentEventFamily.work,
    requiresRunId: true,
    requiresWorkItemId: true,
    runBusinessEvent: true,
  ),
  deferredCreated(
    'deferred.created',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  deferredOwnershipTransferred(
    'deferred.ownershipTransferred',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  deferredCompleted(
    'deferred.completed',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  deferredFailed(
    'deferred.failed',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  deferredCancelled(
    'deferred.cancelled',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  deferredOutcomeUnknown(
    'deferred.outcomeUnknown',
    AgentEventFamily.deferred,
    requiresRunId: true,
    requiredPayloadId: AgentPayloadContextId.deferredOperationId,
    runBusinessEvent: true,
  ),
  resourceRegistered(
    'resource.registered',
    AgentEventFamily.resource,
    requiredPayloadId: AgentPayloadContextId.runtimeResourceId,
    allowedAfterRunTerminal: true,
  ),
  resourceOwnershipTransferred(
    'resource.ownershipTransferred',
    AgentEventFamily.resource,
    requiredPayloadId: AgentPayloadContextId.runtimeResourceId,
    allowedAfterRunTerminal: true,
  ),
  resourceUpdated(
    'resource.updated',
    AgentEventFamily.resource,
    requiredPayloadId: AgentPayloadContextId.runtimeResourceId,
    allowedAfterRunTerminal: true,
  ),
  resourceReleased(
    'resource.released',
    AgentEventFamily.resource,
    requiredPayloadId: AgentPayloadContextId.runtimeResourceId,
    allowedAfterRunTerminal: true,
  ),
  resourceOutcomeUnknown(
    'resource.outcomeUnknown',
    AgentEventFamily.resource,
    requiredPayloadId: AgentPayloadContextId.runtimeResourceId,
    allowedAfterRunTerminal: true,
  ),
  driverProposalRejected(
    'driver.proposalRejected',
    AgentEventFamily.driverAudit,
    allowedAfterRunTerminal: true,
  ),
  driverSourceDrained(
    'driver.sourceDrained',
    AgentEventFamily.driverAudit,
    requiresRunId: true,
    runBusinessEvent: true,
  ),
  effectObserved(
    'effect.observed',
    AgentEventFamily.driverAudit,
    allowedAfterRunTerminal: true,
  ),
  historyImported(
    'history.imported',
    AgentEventFamily.driverAudit,
    allowedAfterRunTerminal: true,
  );

  const AgentEventType(
    this.wireName,
    this.family, {
    this.requiresRunId = false,
    this.requiresAttemptId = false,
    this.requiresWorkItemId = false,
    this.requiredPayloadId,
    this.terminal = false,
    this.runBusinessEvent = false,
    this.allowedAfterRunTerminal = false,
  });

  final String wireName;
  final AgentEventFamily family;
  final bool requiresRunId;
  final bool requiresAttemptId;
  final bool requiresWorkItemId;
  final AgentPayloadContextId? requiredPayloadId;
  final bool terminal;
  final bool runBusinessEvent;
  final bool allowedAfterRunTerminal;

  static AgentEventType parse(String value) {
    for (final type in values) {
      if (type.wireName == value) {
        return type;
      }
    }
    throw FormatException('Unknown AgentEvent type.', value);
  }
}
