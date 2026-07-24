import '../id/opaque_id.dart';
import 'agent_store_head.dart';
import 'agent_store_root_head.dart';

enum AgentStoreDurability {
  memory,
  buffered,
  processCrashFlush,
}

final class AgentStoreAppendReceipt {
  AgentStoreAppendReceipt({
    required this.beforeHead,
    required this.afterHead,
    required List<EventId> eventIds,
    required this.requestedDurability,
    required this.achievedDurability,
  }) : eventIds = List<EventId>.unmodifiable(eventIds);

  final AgentStoreHead beforeHead;
  final AgentStoreHead afterHead;
  final List<EventId> eventIds;
  final AgentStoreDurability requestedDurability;
  final AgentStoreDurability achievedDurability;
}

final class AgentStoreCreateSessionReceipt {
  AgentStoreCreateSessionReceipt({
    required this.beforeRootHead,
    required this.afterRootHead,
    required this.sessionId,
    required this.sessionHead,
    required List<EventId> eventIds,
    required this.requestedDurability,
    required this.achievedDurability,
  }) : eventIds = List<EventId>.unmodifiable(eventIds);

  final AgentStoreRootHead beforeRootHead;
  final AgentStoreRootHead afterRootHead;
  final SessionId sessionId;
  final AgentStoreHead sessionHead;
  final List<EventId> eventIds;
  final AgentStoreDurability requestedDurability;
  final AgentStoreDurability achievedDurability;
}
