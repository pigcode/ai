import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  tearDown(() async {
    await fixture.dispose();
  });

  test('two stale writers expose one success and one typed conflict', () async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
    final head = (await fixture.store.loadSession(fileTestSessionId)).head;
    final other = await fixture.open();
    final outcomes = await Future.wait<Object>(<Future<Object>>[
      fixture.store
          .append(fileAppendTransaction(head, variant: 1))
          .then<Object>((receipt) => receipt)
          .catchError((Object error) => error),
      other
          .append(fileAppendTransaction(head, variant: 2))
          .then<Object>((receipt) => receipt)
          .catchError((Object error) => error),
    ]);

    expect(outcomes.whereType<AgentStoreAppendReceipt>(), hasLength(1));
    expect(
      outcomes.whereType<AgentStoreException>().map((error) => error.code),
      <AgentStoreErrorCode>[AgentStoreErrorCode.sequenceConflict],
    );
    final events = await fixture.store.readEvents(fileTestSessionId);
    expect(events.events.map((event) => event.sequence), <int>[1, 2]);
  });

  test('batch write failure publishes no receipt or journal generation',
      () async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    var failed = false;
    final faulty = await fixture.open(
      options: FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        faults: StoreWriterFaults((point, target) {
          if (!failed &&
              point == StoreWriterFaultPoint.afterWrite &&
              target.path.endsWith('.pigj')) {
            failed = true;
            throw StateError('injected short write');
          }
        }),
      ),
    );

    expect(
      () => faulty.append(fileAppendTransaction(before)),
      storeError(AgentStoreErrorCode.ioFailure),
    );
    expect(
      (await fixture.store.loadSession(fileTestSessionId)).head,
      before,
    );
    expect(
      Directory.fromUri(
        fixture.root.uri.resolve('sessions/'),
      )
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('flush failure cannot claim processCrashFlush', () async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    var failed = false;
    final faulty = await fixture.open(
      options: FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        faults: StoreWriterFaults((point, target) {
          if (!failed &&
              point == StoreWriterFaultPoint.beforeFlush &&
              target.path.endsWith('.pigj')) {
            failed = true;
            throw StateError('injected flush failure');
          }
        }),
      ),
    );

    expect(
      () => faulty.append(fileAppendTransaction(before)),
      storeError(AgentStoreErrorCode.ioFailure),
    );
    expect(
      (await fixture.store.loadSession(fileTestSessionId)).head,
      before,
    );
  });

  test('durability requests never silently downgrade', () async {
    fixture = await FileStoreFixture.create();
    final root = await fixture.store.loadRoot();

    expect(
      () => fixture.store.createSession(
        fileCreateTransaction(root.head),
        requestedDurability: AgentStoreDurability.memory,
      ),
      storeError(AgentStoreErrorCode.durabilityUnsupported),
    );
    expect(
      () => fixture.store.createSession(
        fileCreateTransaction(root.head),
        requestedDurability: AgentStoreDurability.buffered,
      ),
      storeError(AgentStoreErrorCode.durabilityUnsupported),
    );
    expect((await fixture.store.loadRoot()).sessionIds, isEmpty);
  });

  test('post-commit create receipt loss retries from durable registry',
      () async {
    fixture = await FileStoreFixture.create();
    var loseReceipt = true;
    final lossy = await fixture.open(
      options: FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        commitFaults: StoreCommitFaults((point) {
          if (loseReceipt && point == StoreCommitPoint.createSession) {
            loseReceipt = false;
            throw StateError('injected receipt loss');
          }
        }),
      ),
    );
    final empty = await lossy.loadRoot();
    final transaction = fileCreateTransaction(empty.head);

    await expectLater(
      () => lossy.createSession(transaction),
      throwsStateError,
    );
    final retry = await lossy.createSession(transaction);

    expect(retry.sessionId, fileTestSessionId);
    expect((await lossy.loadRoot()).sessionIds, <SessionId>{
      fileTestSessionId,
    });
    expect(
      (await lossy.readEvents(fileTestSessionId))
          .events
          .map((event) => event.sequence),
      <int>[1],
    );
  });

  test('missing exact registry artifact fails closed', () async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
    final commandChunks = fixture.root
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.contains('${Platform.pathSeparator}commands'
                  '${Platform.pathSeparator}chunks') &&
              file.path.endsWith('.json'),
        )
        .toList();
    expect(commandChunks, isEmpty);

    final identityChunk =
        fixture.root.listSync(recursive: true).whereType<File>().firstWhere(
              (file) =>
                  file.path.contains('${Platform.pathSeparator}identities'
                      '${Platform.pathSeparator}chunks') &&
                  file.path.endsWith('.json'),
            );
    identityChunk.deleteSync();

    expect(
      () => fixture.store.loadSession(fileTestSessionId),
      storeError(AgentStoreErrorCode.corruption),
    );
  });
}
