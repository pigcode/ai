import '../domain/deferred_operation.dart';
import '../id/opaque_id.dart';
import 'agent_command.dart';
import 'run_commands.dart';

enum DeferredOperationOutcome {
  completed,
  failed,
  cancelled,
  outcomeUnknown,
}

final class CreateDeferredOperationCommand extends RunCommand {
  const CreateDeferredOperationCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.deadlineAt,
    required this.cancellationPolicy,
  });

  final DateTime deadlineAt;
  final DeferredCancellationPolicy cancellationPolicy;

  @override
  AgentCommandType get type => AgentCommandType.createDeferredOperation;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'deadlineAt': deadlineAt.toIso8601String(),
        'cancellationPolicy': cancellationPolicy.name,
      };
}

final class TransferDeferredOperationCommand extends RunCommand {
  const TransferDeferredOperationCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.deferredOperationId,
  });

  final DeferredOperationId deferredOperationId;

  @override
  AgentCommandType get type => AgentCommandType.transferDeferredOperation;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'deferredOperationId': deferredOperationId.value,
        'fromOwner': 'run',
        'owner': 'session',
      };
}

final class RecordDeferredOperationOutcomeCommand extends RunCommand {
  const RecordDeferredOperationOutcomeCommand({
    required super.commandId,
    required super.handle,
    required super.runId,
    required this.deferredOperationId,
    required this.outcome,
  });

  final DeferredOperationId deferredOperationId;
  final DeferredOperationOutcome outcome;

  @override
  AgentCommandType get type => AgentCommandType.recordDeferredOperationOutcome;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        ...runContent,
        'deferredOperationId': deferredOperationId.value,
        'outcome': outcome.name,
      };
}
