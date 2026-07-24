import '../event/agent_event.dart';
import '../id/opaque_id.dart';
import '../json/domain_json.dart';
import 'agent_store_head.dart';

final class AgentStoreIdAllocation {
  const AgentStoreIdAllocation(this.id);

  final OpaqueId id;
}

final class AgentStoreAcceptedCommand {
  AgentStoreAcceptedCommand({
    required this.commandId,
    required this.contentDigest,
    required Map<String, Object?> receipt,
  }) : receipt = DomainJson.freeze(receipt)! as Map<String, Object?>;

  final CommandId commandId;
  final String contentDigest;
  final Map<String, Object?> receipt;
}

final class AgentStoreTransaction {
  AgentStoreTransaction({
    required this.sessionId,
    required this.expectedHead,
    required List<AgentStoreIdAllocation> newIdAllocations,
    required List<AgentEvent> events,
    this.acceptedCommand,
  })  : newIdAllocations =
            List<AgentStoreIdAllocation>.unmodifiable(newIdAllocations),
        events = List<AgentEvent>.unmodifiable(events);

  final SessionId sessionId;
  final AgentStoreHead expectedHead;
  final List<AgentStoreIdAllocation> newIdAllocations;
  final List<AgentEvent> events;
  final AgentStoreAcceptedCommand? acceptedCommand;
}
