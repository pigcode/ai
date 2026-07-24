import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

typedef AgentStoreFactory = Future<AgentStore> Function();

void agentStoreContract(
  AgentStoreFactory createStore, {
  AgentStoreDurability mutationDurability = AgentStoreDurability.memory,
  AgentStoreDurability unsupportedDurability =
      AgentStoreDurability.processCrashFlush,
  bool compactionAdvancesHistoryFloor = true,
}) {
  group('AgentStore contract', () {
    test('empty root and atomic create/load expose bound heads', () async {
      final store = await createStore();
      final empty = await store.loadRoot();
      expect(empty.head, AgentStoreRootHead.empty);
      expect(empty.sessionIds, isEmpty);

      final transaction = _createTransaction(empty.head);
      final receipt = await store.createSession(
        transaction,
        requestedDurability: mutationDurability,
      );
      final root = await store.loadRoot();
      final session = await store.loadSession(_session);

      expect(root.sessionIds, <SessionId>{_session});
      expect(root.head, receipt.afterRootHead);
      expect(session.head, receipt.sessionHead);
      expect(session.head.sequence, 1);
      expect(session.head.stateDigest, isNot(agentStoreEmptyDigest));
      expect(session.head.journalHeadDigest, isNot(agentStoreEmptyDigest));
      expect(
        session.head.identityRegistryRootDigest,
        isNot(agentStoreEmptyDigest),
      );
      expect(root.head.sessionCatalogRootDigest, isNot(agentStoreEmptyDigest));
      expect(
        root.head.createSessionCommandRegistryRootDigest,
        isNot(agentStoreEmptyDigest),
      );
      expect(
        (await store.lookupCreateSessionCommand(_createCommand))!.receipt,
        transaction.acceptedCommand.receipt,
      );
    });

    test('create retry is durable-idempotent and content-bound', () async {
      final store = await createStore();
      final root = await store.loadRoot();
      final transaction = _createTransaction(root.head);
      final first = await store.createSession(
        transaction,
        requestedDurability: mutationDurability,
      );

      final retry = await store.createSession(
        AgentStoreCreateSessionTransaction(
          expectedRootHead: root.head,
          sessionId: _otherSession,
          acceptedCommand: transaction.acceptedCommand,
          newIdAllocations: <AgentStoreIdAllocation>[
            AgentStoreIdAllocation(_otherSession),
            AgentStoreIdAllocation(_createCommand),
            AgentStoreIdAllocation(_eventId(1)),
          ],
          events: <AgentEvent>[_event(1, AgentEventType.sessionCreated)],
        ),
        requestedDurability: mutationDurability,
      );
      expect(retry.sessionId, first.sessionId);
      expect((await store.loadRoot()).sessionIds, <SessionId>{_session});

      expect(
        () => store.createSession(
          AgentStoreCreateSessionTransaction(
            expectedRootHead: root.head,
            sessionId: _otherSession,
            acceptedCommand: AgentStoreAcceptedCommand(
              commandId: _createCommand,
              contentDigest: _digest('different'),
              receipt: const <String, Object?>{'kind': 'createSession'},
            ),
            newIdAllocations: <AgentStoreIdAllocation>[
              AgentStoreIdAllocation(_otherSession),
              AgentStoreIdAllocation(_createCommand),
              AgentStoreIdAllocation(_eventId(1)),
            ],
            events: <AgentEvent>[_event(1, AgentEventType.sessionCreated)],
          ),
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.commandContentMismatch)),
      );
    });

    test('root sequence and digest CAS conflict independently', () async {
      final store = await createStore();
      final root = await store.loadRoot();

      expect(
        () => store.createSession(
          _createTransaction(
            AgentStoreRootHead(
              sequence: root.head.sequence + 1,
              stateDigest: root.head.stateDigest,
              sessionCatalogRootDigest: root.head.sessionCatalogRootDigest,
              createSessionCommandRegistryRootDigest:
                  root.head.createSessionCommandRegistryRootDigest,
              generation: root.head.generation,
            ),
          ),
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.rootSequenceConflict)),
      );
      expect(
        () => store.createSession(
          _createTransaction(
            AgentStoreRootHead(
              sequence: root.head.sequence,
              stateDigest: _digest('wrong-root'),
              sessionCatalogRootDigest: root.head.sessionCatalogRootDigest,
              createSessionCommandRegistryRootDigest:
                  root.head.createSessionCommandRegistryRootDigest,
              generation: root.head.generation,
            ),
          ),
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.rootStateDigestConflict)),
      );
      expect((await store.loadRoot()).sessionIds, isEmpty);
    });

    test('append is atomic, CAS-bound, and command-idempotent', () async {
      final store = await _createdStore(createStore, mutationDurability);
      final initial = await store.loadSession(_session);
      final transaction = _startRunTransaction(initial.head);
      final first = await store.append(
        transaction,
        requestedDurability: mutationDurability,
      );

      expect(first.beforeHead, initial.head);
      expect(first.afterHead.sequence, 3);
      expect(first.eventIds, <EventId>[_eventId(2), _eventId(3)]);
      expect(first.requestedDurability, mutationDurability);
      expect(first.achievedDurability, mutationDurability);
      expect(
        (await store.lookupAcceptedCommand(_session, _startCommand))!.receipt,
        transaction.acceptedCommand!.receipt,
      );

      final retry = await store.append(
        transaction,
        requestedDurability: mutationDurability,
      );
      expect(retry.afterHead, first.afterHead);
      expect((await store.loadSession(_session)).head.sequence, 3);

      final mismatch = AgentStoreTransaction(
        sessionId: _session,
        expectedHead: transaction.expectedHead,
        acceptedCommand: AgentStoreAcceptedCommand(
          commandId: _startCommand,
          contentDigest: _digest('different'),
          receipt: const <String, Object?>{'kind': 'startRun'},
        ),
        newIdAllocations: transaction.newIdAllocations,
        events: transaction.events,
      );
      expect(
        () => store.append(
          mismatch,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.commandContentMismatch)),
      );
    });

    test('session sequence and digest CAS conflict independently', () async {
      final store = await _createdStore(createStore, mutationDurability);
      final current = (await store.loadSession(_session)).head;
      final transaction = _startRunTransaction(current);

      final wrongSequence = _copyTransaction(
        transaction,
        AgentStoreHead(
          sequence: current.sequence + 1,
          stateDigest: current.stateDigest,
          journalHeadDigest: current.journalHeadDigest,
          identityRegistryRootDigest: current.identityRegistryRootDigest,
          commandRegistryRootDigest: current.commandRegistryRootDigest,
          generation: current.generation,
          historyFloorSequence: current.historyFloorSequence,
        ),
      );
      expect(
        () => store.append(
          wrongSequence,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.sequenceConflict)),
      );

      final wrongDigest = _copyTransaction(
        transaction,
        AgentStoreHead(
          sequence: current.sequence,
          stateDigest: _digest('wrong-session'),
          journalHeadDigest: current.journalHeadDigest,
          identityRegistryRootDigest: current.identityRegistryRootDigest,
          commandRegistryRootDigest: current.commandRegistryRootDigest,
          generation: current.generation,
          historyFloorSequence: current.historyFloorSequence,
        ),
      );
      expect(
        () => store.append(
          wrongDigest,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.stateDigestConflict)),
      );
      expect((await store.loadSession(_session)).head, current);
    });

    test('invalid batch and duplicate allocation leave no partial mutation',
        () async {
      final store = await _createdStore(createStore, mutationDurability);
      final before = (await store.loadSession(_session)).head;
      final invalidBatch = AgentStoreTransaction(
        sessionId: _session,
        expectedHead: before,
        newIdAllocations: <AgentStoreIdAllocation>[
          AgentStoreIdAllocation(_eventId(2)),
          AgentStoreIdAllocation(_eventId(3)),
        ],
        events: <AgentEvent>[
          _event(2, AgentEventType.sessionCapabilitiesPinned),
          _event(4, AgentEventType.sessionAttachmentChanged),
        ],
      );
      expect(
        () => store.append(
          invalidBatch,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.invalidTransaction)),
      );
      expect((await store.loadSession(_session)).head, before);

      final duplicate = AgentStoreTransaction(
        sessionId: _session,
        expectedHead: before,
        newIdAllocations: <AgentStoreIdAllocation>[
          AgentStoreIdAllocation(_eventId(2)),
          AgentStoreIdAllocation(_eventId(1)),
        ],
        events: <AgentEvent>[
          _event(2, AgentEventType.sessionCapabilitiesPinned),
        ],
      );
      expect(
        () => store.append(
          duplicate,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.duplicateId)),
      );
      expect((await store.loadSession(_session)).head, before);
    });

    test('newly referenced IDs require exact allocation', () async {
      final store = await _createdStore(createStore, mutationDurability);
      final before = (await store.loadSession(_session)).head;
      final missingRunAllocation = AgentStoreTransaction(
        sessionId: _session,
        expectedHead: before,
        acceptedCommand: AgentStoreAcceptedCommand(
          commandId: _startCommand,
          contentDigest: _digest('missing-run-allocation'),
          receipt: <String, Object?>{
            'kind': 'startRun',
            'runId': _run.value,
          },
        ),
        newIdAllocations: <AgentStoreIdAllocation>[
          AgentStoreIdAllocation(_startCommand),
          AgentStoreIdAllocation(_eventId(2)),
        ],
        events: <AgentEvent>[
          _event(2, AgentEventType.runCreated, runId: _run),
        ],
      );

      expect(
        () => store.append(
          missingRunAllocation,
          requestedDurability: mutationDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.invalidTransaction)),
      );
      expect((await store.loadSession(_session)).head, before);
    });

    test('paged reads, snapshot, cursor floor, and compact retry work',
        () async {
      final store = await _createdStore(createStore, mutationDurability);
      final beforeAppend = (await store.loadSession(_session)).head;
      await store.append(
        _startRunTransaction(beforeAppend),
        requestedDurability: mutationDurability,
      );

      final firstPage = await store.readEvents(_session, limit: 2);
      final secondPage = await store.readEvents(
        _session,
        after: firstPage.nextCursor,
        limit: 2,
      );
      expect(firstPage.events.map((event) => event.sequence), <int>[1, 2]);
      expect(secondPage.events.map((event) => event.sequence), <int>[3]);

      final beforeSnapshot = (await store.loadSession(_session)).head;
      final projection = const <String, Object?>{'state': 'inProgress'};
      final snapshot = AgentStoreSnapshot(
        sessionId: _session,
        snapshotId: _snapshot,
        sequence: beforeSnapshot.sequence,
        journalHeadDigest: beforeSnapshot.journalHeadDigest,
        historyFloorSequence: beforeSnapshot.historyFloorSequence,
        identityRegistryRootDigest: beforeSnapshot.identityRegistryRootDigest,
        commandRegistryRootDigest: beforeSnapshot.commandRegistryRootDigest,
        canonicalProjection: projection,
        projectionDigest: canonicalJsonSha256(projection),
      );
      final snapshotReceipt = await store.writeSnapshot(
        snapshot,
        expectedHead: beforeSnapshot,
        requestedDurability: mutationDurability,
      );
      expect(
        (await store.loadSession(_session)).snapshot!.snapshotId,
        _snapshot,
      );

      final compactReceipt = await store.compact(
        _session,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 2,
        requestedDurability: mutationDurability,
      );
      final retry = await store.compact(
        _session,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 2,
        requestedDurability: mutationDurability,
      );
      expect(retry.afterHead, compactReceipt.afterHead);
      if (compactionAdvancesHistoryFloor) {
        expect(compactReceipt.afterHead.historyFloorSequence, 2);
        expect(
          () => store.readEvents(
            _session,
            after: const AgentStoreCursor(0),
          ),
          throwsA(_storeError(AgentStoreErrorCode.cursorCompacted)),
        );
        expect(
          (await store.readEvents(
            _session,
            after: const AgentStoreCursor(2),
          ))
              .events
              .single
              .sequence,
          3,
        );
      } else {
        expect(compactReceipt.afterHead.historyFloorSequence, 0);
        expect(
          (await store.readEvents(_session))
              .events
              .map((event) => event.sequence),
          <int>[1, 2, 3],
        );
      }
    });

    test('unsupported durability fails without mutation', () async {
      final store = await createStore();
      final root = await store.loadRoot();
      expect(
        () => store.createSession(
          _createTransaction(root.head),
          requestedDurability: unsupportedDurability,
        ),
        throwsA(_storeError(AgentStoreErrorCode.durabilityUnsupported)),
      );
      expect((await store.loadRoot()).sessionIds, isEmpty);
    });
  });
}

Future<AgentStore> _createdStore(
  AgentStoreFactory createStore,
  AgentStoreDurability mutationDurability,
) async {
  final store = await createStore();
  final root = await store.loadRoot();
  await store.createSession(
    _createTransaction(root.head),
    requestedDurability: mutationDurability,
  );
  return store;
}

AgentStoreCreateSessionTransaction _createTransaction(
  AgentStoreRootHead expectedRootHead,
) =>
    AgentStoreCreateSessionTransaction(
      expectedRootHead: expectedRootHead,
      sessionId: _session,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: _createCommand,
        contentDigest: _digest('create'),
        receipt: <String, Object?>{
          'kind': 'createSession',
          'sessionId': _session.value,
        },
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(_session),
        AgentStoreIdAllocation(_createCommand),
        AgentStoreIdAllocation(_eventId(1)),
      ],
      events: <AgentEvent>[
        _event(1, AgentEventType.sessionCreated),
      ],
    );

AgentStoreTransaction _startRunTransaction(AgentStoreHead expectedHead) =>
    AgentStoreTransaction(
      sessionId: _session,
      expectedHead: expectedHead,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: _startCommand,
        contentDigest: _digest('start'),
        receipt: <String, Object?>{
          'kind': 'startRun',
          'runId': _run.value,
          'afterSequence': 3,
        },
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(_startCommand),
        AgentStoreIdAllocation(_run),
        AgentStoreIdAllocation(_eventId(2)),
        AgentStoreIdAllocation(_eventId(3)),
      ],
      events: <AgentEvent>[
        _event(2, AgentEventType.runCreated, runId: _run),
        _event(3, AgentEventType.runInputRecorded, runId: _run),
      ],
    );

AgentStoreTransaction _copyTransaction(
  AgentStoreTransaction transaction,
  AgentStoreHead expectedHead,
) =>
    AgentStoreTransaction(
      sessionId: transaction.sessionId,
      expectedHead: expectedHead,
      newIdAllocations: transaction.newIdAllocations,
      events: transaction.events,
      acceptedCommand: transaction.acceptedCommand,
    );

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  RunId? runId,
}) =>
    AgentEvent(
      eventId: _eventId(sequence),
      schemaVersion: 1,
      sessionId: _session,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      runId: runId,
      causationId: sequence == 1 ? _createCommand : _startCommand,
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

EventId _eventId(int value) => EventId.parse(
      'evt_${value.toString().padLeft(32, '0')}',
    );

String _digest(String value) => canonicalJsonSha256(value);

Matcher _storeError(AgentStoreErrorCode code) =>
    isA<AgentStoreException>().having(
      (error) => error.code,
      'code',
      code,
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _otherSession = SessionId.parse('ses_10000000000000000000000000000000');
final _createCommand = CommandId.parse('cmd_00000000000000000000000000000000');
final _startCommand = CommandId.parse('cmd_10000000000000000000000000000000');
final _run = RunId.parse('run_00000000000000000000000000000000');
final _snapshot = SnapshotId.parse('snp_00000000000000000000000000000000');
