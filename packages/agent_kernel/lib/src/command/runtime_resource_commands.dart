import '../id/opaque_id.dart';
import 'agent_command.dart';
import 'run_commands.dart';

enum RuntimeResourceOutcome {
  released,
  outcomeUnknown,
}

final class RegisterRuntimeResourceCommand extends RunCommand {
  const RegisterRuntimeResourceCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
  });

  @override
  AgentCommandType get type => AgentCommandType.registerRuntimeResource;

  @override
  Map<String, Object?> get canonicalContent => runContent;
}

final class TransferRuntimeResourceCommand extends RunCommand {
  const TransferRuntimeResourceCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.runtimeResourceId,
  });

  final RuntimeResourceId runtimeResourceId;

  @override
  AgentCommandType get type => AgentCommandType.transferRuntimeResource;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'runtimeResourceId': runtimeResourceId.value,
        'fromOwner': 'run',
        'owner': 'session',
      };
}

final class RecordRuntimeResourceOutcomeCommand extends RunCommand {
  const RecordRuntimeResourceOutcomeCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.runtimeResourceId,
    required this.outcome,
  });

  final RuntimeResourceId runtimeResourceId;
  final RuntimeResourceOutcome outcome;

  @override
  AgentCommandType get type => AgentCommandType.recordRuntimeResourceOutcome;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'runtimeResourceId': runtimeResourceId.value,
        'outcome': outcome.name,
      };
}
