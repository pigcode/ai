import '../id/opaque_id.dart';
import '../policy/agent_policy.dart';
import '../policy/approval_binding.dart';
import 'agent_command.dart';
import 'run_commands.dart';

enum WorkItemOutcome {
  succeeded,
  failed,
  cancelled,
  outcomeUnknown,
}

final class ProposeWorkItemCommand extends RunCommand {
  const ProposeWorkItemCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.request,
    required this.policyVersion,
  });

  final WorkItemRequest request;
  final String policyVersion;

  @override
  AgentCommandType get type => AgentCommandType.proposeWorkItem;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'request': request.toJson(),
        'policyVersion': policyVersion,
      };
}

final class ResolveApprovalCommand extends RunCommand {
  const ResolveApprovalCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.approvalId,
    required this.binding,
    required this.decision,
    required this.currentPrincipal,
  });

  final ApprovalId approvalId;
  final ApprovalBinding binding;
  final ApprovalDecision decision;
  final String currentPrincipal;

  @override
  AgentCommandType get type => AgentCommandType.resolveApproval;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'approvalId': approvalId.value,
        'binding': binding.toJson(),
        'decision': decision.name,
        'currentPrincipal': currentPrincipal,
      };
}

final class StartWorkExecutionCommand extends RunCommand {
  const StartWorkExecutionCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.workItemId,
  });

  final WorkItemId workItemId;

  @override
  AgentCommandType get type => AgentCommandType.startWorkExecution;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'workItemId': workItemId.value,
      };
}

final class RecordWorkItemOutcomeCommand extends RunCommand {
  const RecordWorkItemOutcomeCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.workItemId,
    required this.outcome,
    this.externalEffectSucceededButResultMissing = false,
  });

  final WorkItemId workItemId;
  final WorkItemOutcome outcome;
  final bool externalEffectSucceededButResultMissing;

  @override
  AgentCommandType get type => AgentCommandType.recordWorkItemOutcome;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'workItemId': workItemId.value,
        'outcome': outcome.name,
        'externalEffectSucceededButResultMissing':
            externalEffectSucceededButResultMissing,
      };
}

WorkItemOutcome recoverWorkItemOutcome({
  required bool externalEffectSucceeded,
  required bool resultPersisted,
  required WorkItemOutcome reportedOutcome,
}) =>
    externalEffectSucceeded && !resultPersisted
        ? WorkItemOutcome.outcomeUnknown
        : reportedOutcome;
