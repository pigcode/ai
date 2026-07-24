import '../event/agent_event.dart';
import '../id/opaque_id.dart';
import 'agent_store_root_head.dart';
import 'agent_store_transaction.dart';

final class AgentStoreCreateSessionTransaction {
  AgentStoreCreateSessionTransaction({
    required this.expectedRootHead,
    required this.sessionId,
    required this.acceptedCommand,
    required List<AgentStoreIdAllocation> newIdAllocations,
    required List<AgentEvent> events,
  })  : newIdAllocations =
            List<AgentStoreIdAllocation>.unmodifiable(newIdAllocations),
        events = List<AgentEvent>.unmodifiable(events);

  final AgentStoreRootHead expectedRootHead;
  final SessionId sessionId;
  final AgentStoreAcceptedCommand acceptedCommand;
  final List<AgentStoreIdAllocation> newIdAllocations;
  final List<AgentEvent> events;
}
