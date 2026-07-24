import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class InMemoryAgentStore implements AgentStore {
  InMemoryAgentStore({
    this.loseNextCreateReceipt = false,
    this.failNextAppendBeforeCommit = false,
    bool synchronizeNextCreateLookups = false,
    bool synchronizeNextCommandLookups = false,
  })  : _createLookupBarrier =
            synchronizeNextCreateLookups ? _TwoPartyBarrier() : null,
        _commandLookupBarrier =
            synchronizeNextCommandLookups ? _TwoPartyBarrier() : null;

  bool loseNextCreateReceipt;
  bool failNextAppendBeforeCommit;
  _TwoPartyBarrier? _createLookupBarrier;
  _TwoPartyBarrier? _commandLookupBarrier;

  AgentStoreRootHead _rootHead = AgentStoreRootHead.empty;
  final Set<SessionId> _sessionIds = <SessionId>{};
  final Map<CommandId, AgentStoreAcceptedCommand> _createCommands =
      <CommandId, AgentStoreAcceptedCommand>{};
  final Map<CommandId, AgentStoreCreateSessionReceipt> _createReceipts =
      <CommandId, AgentStoreCreateSessionReceipt>{};
  final Map<SessionId, _MemorySession> _sessions =
      <SessionId, _MemorySession>{};

  @override
  Future<AgentStoreRoot> loadRoot() async => AgentStoreRoot(
        head: _rootHead,
        sessionIds: _sessionIds,
      );

  @override
  Future<AgentStoreAcceptedCommand?> lookupCreateSessionCommand(
    CommandId commandId,
  ) async {
    final result = _createCommands[commandId];
    final barrier = _createLookupBarrier;
    if (barrier != null) {
      await barrier.wait();
      _createLookupBarrier = null;
    }
    return result;
  }

  @override
  Future<AgentStoreCreateSessionReceipt> createSession(
    AgentStoreCreateSessionTransaction transaction, {
    AgentStoreDurability? requestedDurability,
  }) async {
    final requested = requestedDurability ?? AgentStoreDurability.memory;
    _requireMemoryDurability(requested);
    final accepted = transaction.acceptedCommand;
    final previousCommand = _createCommands[accepted.commandId];
    if (previousCommand != null) {
      _requireSameCommand(previousCommand, accepted);
      return _createReceipts[accepted.commandId]!;
    }
    _requireRootHead(transaction.expectedRootHead);
    if (_sessions.containsKey(transaction.sessionId)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.duplicateId,
        'SessionId was already allocated.',
      );
    }
    _validateCreateTransaction(transaction);

    final allocatedIds =
        transaction.newIdAllocations.map((entry) => entry.id.value).toSet();
    final commandRegistry = <CommandId, AgentStoreAcceptedCommand>{};
    final sessionHead = _composeSessionHead(
      events: transaction.events,
      allocatedIds: allocatedIds,
      commands: commandRegistry,
      generation: 1,
      historyFloorSequence: 0,
    );
    final session = _MemorySession(
      head: sessionHead,
      events: transaction.events,
      allocatedIds: allocatedIds,
      commands: commandRegistry,
    );

    final beforeRootHead = _rootHead;
    final nextSessionIds = <SessionId>{..._sessionIds, transaction.sessionId};
    final nextCreateCommands = <CommandId, AgentStoreAcceptedCommand>{
      ..._createCommands,
      accepted.commandId: accepted,
    };
    final afterRootHead = AgentStoreRootHead.compose(
      sequence: beforeRootHead.sequence + 1,
      sessionCatalogRootDigest: _sessionCatalogDigest(nextSessionIds),
      createSessionCommandRegistryRootDigest:
          _commandRegistryDigest(nextCreateCommands),
      generation: beforeRootHead.generation + 1,
    );
    final receipt = AgentStoreCreateSessionReceipt(
      beforeRootHead: beforeRootHead,
      afterRootHead: afterRootHead,
      sessionId: transaction.sessionId,
      sessionHead: sessionHead,
      eventIds: transaction.events.map((event) => event.eventId).toList(),
      requestedDurability: requested,
      achievedDurability: AgentStoreDurability.memory,
    );

    _sessions[transaction.sessionId] = session;
    _sessionIds
      ..clear()
      ..addAll(nextSessionIds);
    _createCommands
      ..clear()
      ..addAll(nextCreateCommands);
    _rootHead = afterRootHead;
    _createReceipts[accepted.commandId] = receipt;
    if (loseNextCreateReceipt) {
      loseNextCreateReceipt = false;
      throw const AgentStoreException(
        AgentStoreErrorCode.resourceLimit,
        'Injected post-commit receipt loss.',
      );
    }
    return receipt;
  }

  @override
  Future<AgentStoreSession> loadSession(SessionId sessionId) async {
    final session = _requireSession(sessionId);
    return AgentStoreSession(
      sessionId: sessionId,
      head: session.head,
      snapshot: session.snapshot,
    );
  }

  @override
  Future<AgentStoreAcceptedCommand?> lookupAcceptedCommand(
    SessionId sessionId,
    CommandId commandId,
  ) async {
    final result = _requireSession(sessionId).commands[commandId];
    final barrier = _commandLookupBarrier;
    if (barrier != null) {
      await barrier.wait();
      _commandLookupBarrier = null;
    }
    return result;
  }

  @override
  Future<AgentStoreEventPage> readEvents(
    SessionId sessionId, {
    AgentStoreCursor after = const AgentStoreCursor(0),
    int limit = 256,
  }) async {
    final session = _requireSession(sessionId);
    if (limit <= 0) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Event page limit must be positive.',
      );
    }
    if (after.sequence < session.head.historyFloorSequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.cursorCompacted,
        'Event cursor is below the retained history floor.',
      );
    }
    final events = session.events
        .where((event) => event.sequence > after.sequence)
        .take(limit)
        .toList();
    final nextSequence = events.isEmpty ? after.sequence : events.last.sequence;
    return AgentStoreEventPage(
      events: events,
      nextCursor: AgentStoreCursor(nextSequence),
      head: session.head,
    );
  }

  @override
  Future<AgentStoreAppendReceipt> append(
    AgentStoreTransaction transaction, {
    AgentStoreDurability? requestedDurability,
  }) async {
    final requested = requestedDurability ?? AgentStoreDurability.memory;
    _requireMemoryDurability(requested);
    final session = _requireSession(transaction.sessionId);
    final accepted = transaction.acceptedCommand;
    if (accepted != null) {
      final previousCommand = session.commands[accepted.commandId];
      if (previousCommand != null) {
        _requireSameCommand(previousCommand, accepted);
        return session.commandReceipts[accepted.commandId]!;
      }
    }
    _requireHead(session.head, transaction.expectedHead);
    _validateAppendTransaction(session, transaction);
    if (failNextAppendBeforeCommit) {
      failNextAppendBeforeCommit = false;
      throw const AgentStoreException(
        AgentStoreErrorCode.resourceLimit,
        'Injected pre-commit append failure.',
      );
    }

    final beforeHead = session.head;
    final nextEvents = <AgentEvent>[...session.events, ...transaction.events];
    final nextAllocatedIds = <String>{
      ...session.allocatedIds,
      ...transaction.newIdAllocations.map((entry) => entry.id.value),
    };
    final nextCommands = <CommandId, AgentStoreAcceptedCommand>{
      ...session.commands,
      if (accepted != null) accepted.commandId: accepted,
    };
    final afterHead = _composeSessionHead(
      events: nextEvents,
      allocatedIds: nextAllocatedIds,
      commands: nextCommands,
      generation: beforeHead.generation + 1,
      historyFloorSequence: beforeHead.historyFloorSequence,
      previousJournalDigest: beforeHead.journalHeadDigest,
      appendedEvents: transaction.events,
    );
    final receipt = AgentStoreAppendReceipt(
      beforeHead: beforeHead,
      afterHead: afterHead,
      eventIds: transaction.events.map((event) => event.eventId).toList(),
      requestedDurability: requested,
      achievedDurability: AgentStoreDurability.memory,
    );

    session
      ..head = afterHead
      ..events = nextEvents
      ..allocatedIds = nextAllocatedIds
      ..commands = nextCommands;
    if (accepted != null) {
      session.commandReceipts[accepted.commandId] = receipt;
    }
    return receipt;
  }

  @override
  Future<AgentStoreAppendReceipt> writeSnapshot(
    AgentStoreSnapshot snapshot, {
    required AgentStoreHead expectedHead,
    AgentStoreDurability? requestedDurability,
  }) async {
    final requested = requestedDurability ?? AgentStoreDurability.memory;
    _requireMemoryDurability(requested);
    final session = _requireSession(snapshot.sessionId);
    _requireHead(session.head, expectedHead);
    if (session.snapshotIds.contains(snapshot.snapshotId)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.duplicateId,
        'SnapshotId was already allocated.',
      );
    }
    if (snapshot.snapshotFormatVersion != 1 ||
        snapshot.reducerSchemaVersion != 1 ||
        snapshot.sequence != session.head.sequence ||
        snapshot.journalHeadDigest != session.head.journalHeadDigest ||
        snapshot.historyFloorSequence != session.head.historyFloorSequence ||
        snapshot.identityRegistryRootDigest !=
            session.head.identityRegistryRootDigest ||
        snapshot.commandRegistryRootDigest !=
            session.head.commandRegistryRootDigest ||
        canonicalJsonSha256(snapshot.canonicalProjection) !=
            snapshot.projectionDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.snapshotConflict,
        'Snapshot does not bind the current Session head.',
      );
    }
    final beforeHead = session.head;
    final afterHead = AgentStoreHead.compose(
      sequence: beforeHead.sequence,
      journalHeadDigest: beforeHead.journalHeadDigest,
      identityRegistryRootDigest: beforeHead.identityRegistryRootDigest,
      commandRegistryRootDigest: beforeHead.commandRegistryRootDigest,
      generation: beforeHead.generation + 1,
      historyFloorSequence: beforeHead.historyFloorSequence,
    );
    final receipt = AgentStoreAppendReceipt(
      beforeHead: beforeHead,
      afterHead: afterHead,
      eventIds: const <EventId>[],
      requestedDurability: requested,
      achievedDurability: AgentStoreDurability.memory,
    );
    session
      ..head = afterHead
      ..snapshot = snapshot
      ..snapshotIds = <SnapshotId>{...session.snapshotIds, snapshot.snapshotId};
    return receipt;
  }

  @override
  Future<AgentStoreAppendReceipt> compact(
    SessionId sessionId, {
    required AgentStoreHead expectedHead,
    required int throughSequence,
    AgentStoreDurability? requestedDurability,
  }) async {
    final requested = requestedDurability ?? AgentStoreDurability.memory;
    _requireMemoryDurability(requested);
    final session = _requireSession(sessionId);
    final previousReceipt = session.compactionReceipts[throughSequence];
    if (previousReceipt != null) {
      return previousReceipt;
    }
    _requireHead(session.head, expectedHead);
    final snapshot = session.snapshot;
    if (throughSequence < session.head.historyFloorSequence ||
        throughSequence > session.head.sequence ||
        snapshot == null ||
        snapshot.sequence < throughSequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Compaction requires a covering snapshot and a valid floor.',
      );
    }
    final beforeHead = session.head;
    final afterHead = AgentStoreHead.compose(
      sequence: beforeHead.sequence,
      journalHeadDigest: beforeHead.journalHeadDigest,
      identityRegistryRootDigest: beforeHead.identityRegistryRootDigest,
      commandRegistryRootDigest: beforeHead.commandRegistryRootDigest,
      generation: beforeHead.generation + 1,
      historyFloorSequence: throughSequence,
    );
    final receipt = AgentStoreAppendReceipt(
      beforeHead: beforeHead,
      afterHead: afterHead,
      eventIds: const <EventId>[],
      requestedDurability: requested,
      achievedDurability: AgentStoreDurability.memory,
    );
    session
      ..head = afterHead
      ..events = session.events
          .where((event) => event.sequence > throughSequence)
          .toList();
    session.compactionReceipts[throughSequence] = receipt;
    return receipt;
  }

  _MemorySession _requireSession(SessionId sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const AgentStoreException(
        AgentStoreErrorCode.sessionNotFound,
        'Session does not exist.',
      );
    }
    return session;
  }

  void _requireMemoryDurability(AgentStoreDurability requested) {
    if (requested != AgentStoreDurability.memory) {
      throw const AgentStoreException(
        AgentStoreErrorCode.durabilityUnsupported,
        'InMemoryAgentStore supports only memory durability.',
      );
    }
  }

  void _requireRootHead(AgentStoreRootHead expected) {
    if (expected.sequence != _rootHead.sequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.rootSequenceConflict,
        'Root sequence does not match.',
      );
    }
    if (expected.stateDigest != _rootHead.stateDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.rootStateDigestConflict,
        'Root state digest does not match.',
      );
    }
  }

  void _requireHead(AgentStoreHead current, AgentStoreHead expected) {
    if (expected.sequence != current.sequence) {
      throw const AgentStoreException(
        AgentStoreErrorCode.sequenceConflict,
        'Session sequence does not match.',
      );
    }
    if (expected.stateDigest != current.stateDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.stateDigestConflict,
        'Session state digest does not match.',
      );
    }
  }

  void _requireSameCommand(
    AgentStoreAcceptedCommand previous,
    AgentStoreAcceptedCommand proposed,
  ) {
    if (previous.contentDigest != proposed.contentDigest) {
      throw const AgentStoreException(
        AgentStoreErrorCode.commandContentMismatch,
        'CommandId was already accepted with different content.',
      );
    }
  }

  void _validateCreateTransaction(
    AgentStoreCreateSessionTransaction transaction,
  ) {
    if (transaction.events.isEmpty ||
        transaction.events.first.type != AgentEventType.sessionCreated ||
        transaction.events.first.sequence != 1 ||
        transaction.events.any(
          (event) => event.sessionId != transaction.sessionId,
        )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Create transaction must contain Session genesis.',
      );
    }
    _validateSequences(transaction.events, 1);
    _validateAllocations(
      transaction.newIdAllocations,
      requiredIds: <OpaqueId>[
        transaction.sessionId,
        transaction.acceptedCommand.commandId,
        ...transaction.events.map((event) => event.eventId),
      ],
      referencedIds: _transactionReferences(
        transaction.events,
        commandId: transaction.acceptedCommand.commandId,
        sessionId: transaction.sessionId,
      ),
    );
  }

  void _validateAppendTransaction(
    _MemorySession session,
    AgentStoreTransaction transaction,
  ) {
    if (transaction.events.isEmpty ||
        transaction.events.any(
          (event) => event.sessionId != transaction.sessionId,
        )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Append transaction requires a non-empty same-Session batch.',
      );
    }
    _validateSequences(transaction.events, session.head.sequence + 1);
    final requiredIds = <OpaqueId>[
      if (transaction.acceptedCommand != null)
        transaction.acceptedCommand!.commandId,
      ...transaction.events.map((event) => event.eventId),
    ];
    _validateAllocations(
      transaction.newIdAllocations,
      requiredIds: requiredIds,
      referencedIds: _transactionReferences(
        transaction.events,
        commandId: transaction.acceptedCommand?.commandId,
      ),
      existingIds: session.allocatedIds,
    );
  }

  void _validateSequences(List<AgentEvent> events, int firstSequence) {
    for (var index = 0; index < events.length; index++) {
      if (events[index].sequence != firstSequence + index) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Event batch sequence is not contiguous.',
        );
      }
    }
  }

  void _validateAllocations(
    List<AgentStoreIdAllocation> allocations, {
    required List<OpaqueId> requiredIds,
    required Set<String> referencedIds,
    Set<String> existingIds = const <String>{},
  }) {
    final values = <String>{};
    for (final allocation in allocations) {
      if (existingIds.contains(allocation.id.value) ||
          !values.add(allocation.id.value)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.duplicateId,
          'Logical ID was already allocated.',
        );
      }
      if (!referencedIds.contains(allocation.id.value)) {
        throw const AgentStoreException(
          AgentStoreErrorCode.invalidTransaction,
          'Transaction allocates an unreferenced logical ID.',
        );
      }
    }
    if (requiredIds.any((id) => !values.contains(id.value))) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Transaction omits a required logical ID allocation.',
      );
    }
    if (referencedIds.any(
      (id) => !existingIds.contains(id) && !values.contains(id),
    )) {
      throw const AgentStoreException(
        AgentStoreErrorCode.invalidTransaction,
        'Transaction omits a newly referenced logical ID allocation.',
      );
    }
  }

  Set<String> _transactionReferences(
    List<AgentEvent> events, {
    CommandId? commandId,
    SessionId? sessionId,
  }) {
    final result = <String>{
      if (commandId != null) commandId.value,
      if (sessionId != null) sessionId.value,
    };
    void collect(Object? value) {
      if (value is String) {
        try {
          result.add(_parseAgentOpaqueId(value).value);
        } on FormatException {
          // Non-ID strings are ordinary domain values.
        }
      } else if (value is List<Object?>) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is Map<String, Object?>) {
        for (final item in value.values) {
          collect(item);
        }
      }
    }

    for (final event in events) {
      result
        ..add(event.eventId.value)
        ..add(event.sessionId.value)
        ..add(event.causationId.value);
      if (event.runId != null) result.add(event.runId!.value);
      if (event.attemptId != null) result.add(event.attemptId!.value);
      if (event.workItemId != null) result.add(event.workItemId!.value);
      collect(event.payload);
    }
    return result;
  }
}

OpaqueId _parseAgentOpaqueId(String value) {
  if (value.startsWith('ses_')) return SessionId.parse(value);
  if (value.startsWith('run_')) return RunId.parse(value);
  if (value.startsWith('evt_')) return EventId.parse(value);
  if (value.startsWith('cmd_')) return CommandId.parse(value);
  if (value.startsWith('wrk_')) return WorkItemId.parse(value);
  if (value.startsWith('att_')) return AttemptId.parse(value);
  if (value.startsWith('apr_')) return ApprovalId.parse(value);
  if (value.startsWith('dop_')) return DeferredOperationId.parse(value);
  if (value.startsWith('res_')) return RuntimeResourceId.parse(value);
  if (value.startsWith('snp_')) return SnapshotId.parse(value);
  throw FormatException('Unknown opaque identifier kind.', value);
}

final class _TwoPartyBarrier {
  final Completer<void> _release = Completer<void>();
  var _arrivals = 0;

  Future<void> wait() async {
    _arrivals += 1;
    if (_arrivals == 2) {
      _release.complete();
    }
    await _release.future;
  }
}

final class _MemorySession {
  _MemorySession({
    required this.head,
    required List<AgentEvent> events,
    required Set<String> allocatedIds,
    required Map<CommandId, AgentStoreAcceptedCommand> commands,
  })  : events = List<AgentEvent>.of(events),
        allocatedIds = Set<String>.of(allocatedIds),
        commands = Map<CommandId, AgentStoreAcceptedCommand>.of(commands);

  AgentStoreHead head;
  List<AgentEvent> events;
  Set<String> allocatedIds;
  Map<CommandId, AgentStoreAcceptedCommand> commands;
  final Map<CommandId, AgentStoreAppendReceipt> commandReceipts =
      <CommandId, AgentStoreAppendReceipt>{};
  AgentStoreSnapshot? snapshot;
  Set<SnapshotId> snapshotIds = <SnapshotId>{};
  final Map<int, AgentStoreAppendReceipt> compactionReceipts =
      <int, AgentStoreAppendReceipt>{};
}

AgentStoreHead _composeSessionHead({
  required List<AgentEvent> events,
  required Set<String> allocatedIds,
  required Map<CommandId, AgentStoreAcceptedCommand> commands,
  required int generation,
  required int historyFloorSequence,
  String? previousJournalDigest,
  List<AgentEvent>? appendedEvents,
}) {
  final journalDigest = canonicalJsonSha256(<String, Object?>{
    'events': (appendedEvents ?? events)
        .map((event) => event.toJson())
        .toList(growable: false),
    'previous': previousJournalDigest ?? agentStoreEmptyDigest,
  });
  return AgentStoreHead.compose(
    sequence: events.isEmpty ? historyFloorSequence : events.last.sequence,
    journalHeadDigest: journalDigest,
    identityRegistryRootDigest: canonicalJsonSha256(
      allocatedIds.toList()..sort(),
    ),
    commandRegistryRootDigest: _commandRegistryDigest(commands),
    generation: generation,
    historyFloorSequence: historyFloorSequence,
  );
}

String _sessionCatalogDigest(Set<SessionId> sessionIds) => canonicalJsonSha256(
      sessionIds.map((id) => id.value).toList()..sort(),
    );

String _commandRegistryDigest(
  Map<CommandId, AgentStoreAcceptedCommand> commands,
) {
  final ids = commands.keys.toList()
    ..sort((left, right) => left.value.compareTo(right.value));
  return canonicalJsonSha256(<Object?>[
    for (final id in ids)
      <String, Object?>{
        'commandId': id.value,
        'contentDigest': commands[id]!.contentDigest,
        'receipt': commands[id]!.receipt,
      },
  ]);
}
