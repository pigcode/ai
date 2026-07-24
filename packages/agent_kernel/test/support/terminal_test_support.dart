import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

AgentSessionProjection terminalProjection({
  AgentRunState runState = AgentRunState.inProgress,
  AttemptId? currentAttemptId,
  int executionEpoch = 3,
  Map<WorkItemId, WorkItem> workItems = const <WorkItemId, WorkItem>{},
  Map<ApprovalId, Approval> approvals = const <ApprovalId, Approval>{},
  Map<DeferredOperationId, DeferredOperation> deferredOperations =
      const <DeferredOperationId, DeferredOperation>{},
}) {
  final attempt = currentAttemptId ?? terminalAttemptId;
  return AgentSessionProjection(
    id: terminalSessionId,
    journalSequence: 5,
    definitionRef: null,
    capabilitySnapshot: CapabilitySnapshot.empty(),
    conversationAvailability: ConversationAvailability.available,
    controlAttachment: ControlAttachment.attached,
    runtimeLiveness: RuntimeLiveness.alive,
    resumeStateAvailability: ResumeStateAvailability.none,
    currentRunId: runState.isTerminal ? null : terminalRunId,
    runs: <RunId, AgentRun>{
      terminalRunId: AgentRun(
        id: terminalRunId,
        state: runState,
        currentAttemptId: attempt,
        attempts: <AttemptId, RunAttempt>{
          attempt: RunAttempt(
            id: attempt,
            state: runState.isTerminal
                ? RunAttemptState.terminal
                : RunAttemptState.active,
            executionEpoch: executionEpoch,
          ),
        },
        terminalEventId: runState.isTerminal ? terminalEventId : null,
      ),
    },
    runHistory: <RunId>[terminalRunId],
    workItems: workItems,
    approvals: approvals,
    deferredOperations: deferredOperations,
    resources: const <RuntimeResourceId, RuntimeResource>{},
  );
}

TerminalProposal terminalProposal({
  AttemptId? attemptId,
  int executionEpoch = 3,
  TerminalOutcome outcome = TerminalOutcome.completed,
  int sourceWatermark = 10,
  bool hasMatchingCancellationIntent = false,
  bool executionContainmentProven = false,
}) =>
    TerminalProposal(
      runId: terminalRunId,
      attemptId: attemptId ?? terminalAttemptId,
      executionEpoch: executionEpoch,
      outcome: outcome,
      sourceId: 'source:test',
      sourceWatermark: sourceWatermark,
      causationId: terminalCausationId,
      payload: const <String, Object?>{},
      hasMatchingCancellationIntent: hasMatchingCancellationIntent,
      executionContainmentProven: executionContainmentProven,
    );

final terminalSessionId =
    SessionId.parse('ses_00000000000000000000000000000000');
final terminalRunId = RunId.parse('run_00000000000000000000000000000000');
final terminalAttemptId =
    AttemptId.parse('att_00000000000000000000000000000000');
final terminalOtherAttemptId =
    AttemptId.parse('att_10000000000000000000000000000000');
final terminalEventId = EventId.parse('evt_90000000000000000000000000000000');
final terminalCausationId =
    CommandId.parse('cmd_90000000000000000000000000000000');
final terminalWorkId = WorkItemId.parse('wrk_00000000000000000000000000000000');
final terminalApprovalId =
    ApprovalId.parse('apr_00000000000000000000000000000000');
final terminalDeferredId =
    DeferredOperationId.parse('dop_00000000000000000000000000000000');
