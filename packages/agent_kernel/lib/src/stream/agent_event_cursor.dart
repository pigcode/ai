import '../id/opaque_id.dart';

final class AgentEventCursor {
  const AgentEventCursor({
    required this.sessionId,
    required this.sequence,
    this.eventId,
    this.eventDigest,
  });

  final SessionId sessionId;
  final int sequence;
  final EventId? eventId;
  final String? eventDigest;
}
