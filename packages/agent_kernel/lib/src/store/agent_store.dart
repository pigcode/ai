import '../event/agent_event.dart';
import '../id/opaque_id.dart';
import 'agent_store_create_session_transaction.dart';
import 'agent_store_head.dart';
import 'agent_store_receipt.dart';
import 'agent_store_root_head.dart';
import 'agent_store_snapshot.dart';
import 'agent_store_transaction.dart';

final class AgentStoreRoot {
  AgentStoreRoot({
    required this.head,
    required Set<SessionId> sessionIds,
  }) : sessionIds = Set<SessionId>.unmodifiable(sessionIds);

  final AgentStoreRootHead head;
  final Set<SessionId> sessionIds;
}

final class AgentStoreSession {
  const AgentStoreSession({
    required this.sessionId,
    required this.head,
    required this.snapshot,
  });

  final SessionId sessionId;
  final AgentStoreHead head;
  final AgentStoreSnapshot? snapshot;
}

final class AgentStoreCursor {
  const AgentStoreCursor(this.sequence);

  final int sequence;
}

final class AgentStoreEventPage {
  AgentStoreEventPage({
    required List<AgentEvent> events,
    required this.nextCursor,
    required this.head,
  }) : events = List<AgentEvent>.unmodifiable(events);

  final List<AgentEvent> events;
  final AgentStoreCursor nextCursor;
  final AgentStoreHead head;
}

abstract interface class AgentStore {
  Future<AgentStoreRoot> loadRoot();

  Future<AgentStoreAcceptedCommand?> lookupCreateSessionCommand(
    CommandId commandId,
  );

  Future<AgentStoreCreateSessionReceipt> createSession(
    AgentStoreCreateSessionTransaction transaction, {
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  });

  Future<AgentStoreSession> loadSession(SessionId sessionId);

  Future<AgentStoreAcceptedCommand?> lookupAcceptedCommand(
    SessionId sessionId,
    CommandId commandId,
  );

  Future<AgentStoreEventPage> readEvents(
    SessionId sessionId, {
    AgentStoreCursor after = const AgentStoreCursor(0),
    int limit = 256,
  });

  Future<AgentStoreAppendReceipt> append(
    AgentStoreTransaction transaction, {
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  });

  Future<AgentStoreAppendReceipt> writeSnapshot(
    AgentStoreSnapshot snapshot, {
    required AgentStoreHead expectedHead,
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  });

  Future<AgentStoreAppendReceipt> compact(
    SessionId sessionId, {
    required AgentStoreHead expectedHead,
    required int throughSequence,
    AgentStoreDurability requestedDurability =
        AgentStoreDurability.processCrashFlush,
  });
}
