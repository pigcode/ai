import '../id/opaque_id.dart';
import '../store/agent_store_head.dart';

final class AgentSessionHandle {
  const AgentSessionHandle({
    required this.sessionId,
    required this.projectionGeneration,
    required this.head,
  });

  final SessionId sessionId;
  final int projectionGeneration;
  final AgentStoreHead head;
}
