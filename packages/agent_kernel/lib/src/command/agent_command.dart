import '../domain/agent_definition.dart';
import '../domain/capability_snapshot.dart';
import '../id/opaque_id.dart';
import '../json/domain_json.dart';
import '../kernel/session_handle.dart';
import '../store/agent_store_root_head.dart';

enum AgentCommandType {
  createSession,
  startRun,
  cancelRun,
  suspendRun,
  resumeRunFromCheckpoint,
  reconcileRun,
  proposeWorkItem,
  resolveApproval,
  startWorkExecution,
  recordWorkItemOutcome,
  createDeferredOperation,
  transferDeferredOperation,
  recordDeferredOperationOutcome,
  registerRuntimeResource,
  transferRuntimeResource,
  recordRuntimeResourceOutcome,
}

abstract interface class AgentCommand {
  CommandId get commandId;

  AgentCommandType get type;

  Map<String, Object?> get canonicalContent;
}

final class CreateSessionCommand implements AgentCommand {
  const CreateSessionCommand({
    required this.commandId,
    required this.expectedRootHead,
    required this.definitionRef,
    required this.capabilitySnapshot,
  });

  @override
  final CommandId commandId;
  final AgentStoreRootHead expectedRootHead;
  final AgentDefinitionRef definitionRef;
  final CapabilitySnapshot capabilitySnapshot;

  @override
  AgentCommandType get type => AgentCommandType.createSession;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        'type': type.name,
        'definitionRef': definitionRef.value,
        'capabilitySnapshot': capabilitySnapshot.toJson(),
      };
}

final class StartRunCommand implements AgentCommand {
  StartRunCommand({
    required this.commandId,
    required this.handle,
    required Map<String, Object?> input,
  }) : input = DomainJson.freeze(input)! as Map<String, Object?>;

  @override
  final CommandId commandId;
  final AgentSessionHandle handle;
  final Map<String, Object?> input;

  @override
  AgentCommandType get type => AgentCommandType.startRun;

  @override
  Map<String, Object?> get canonicalContent => <String, Object?>{
        'type': type.name,
        'sessionId': handle.sessionId.value,
        'input': input,
      };
}
