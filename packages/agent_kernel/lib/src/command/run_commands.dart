import '../id/opaque_id.dart';
import '../kernel/session_handle.dart';
import 'agent_command.dart';

abstract base class RunCommand implements AgentCommand {
  const RunCommand({
    required this.commandId,
    required this.handle,
    required this.runId,
  });

  @override
  final CommandId commandId;
  final AgentSessionHandle handle;
  final RunId runId;

  Map<String, Object?> get runContent => <String, Object?>{
        'type': type.name,
        'sessionId': handle.sessionId.value,
        'runId': runId.value,
      };
}

final class CancelRunCommand extends RunCommand {
  const CancelRunCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
  });

  @override
  AgentCommandType get type => AgentCommandType.cancelRun;

  @override
  Map<String, Object?> get canonicalContent => runContent;
}

final class SuspendRunCommand extends RunCommand {
  const SuspendRunCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
  });

  @override
  AgentCommandType get type => AgentCommandType.suspendRun;

  @override
  Map<String, Object?> get canonicalContent => runContent;
}

final class ResumeRunFromCheckpointCommand extends RunCommand {
  const ResumeRunFromCheckpointCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.checkpointReference,
  });

  final String checkpointReference;

  @override
  AgentCommandType get type => AgentCommandType.resumeRunFromCheckpoint;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'checkpointReference': checkpointReference,
      };
}

final class ReconcileRunCommand extends RunCommand {
  const ReconcileRunCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.reason,
  });

  final String reason;

  @override
  AgentCommandType get type => AgentCommandType.reconcileRun;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'reason': reason,
      };
}
