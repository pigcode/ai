import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  setUp(() async {
    fixture = await FileStoreFixture.create(
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
      ),
    );
    await fixture.createSession();
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    await fixture.store.append(fileAppendTransaction(before));
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('explicit prune advances floor and binds retained chain', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );
    final compact = await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );

    expect(compact.afterHead.historyFloorSequence, 1);
    expect(
      () => fixture.store.readEvents(fileTestSessionId),
      storeError(AgentStoreErrorCode.cursorCompacted),
    );
    expect(
      (await fixture.store.readEvents(
        fileTestSessionId,
        after: const AgentStoreCursor(1),
      ))
          .events
          .single
          .sequence,
      2,
    );

    final manifest = _latestSessionManifest(fixture);
    final retention = manifest['retention']! as Map<String, Object?>;
    final commitment = retention['prefixCommitment']! as Map<String, Object?>;
    expect(retention['policy'], 'pruneThroughSnapshot');
    expect(commitment['throughSequence'], 1);
    expect(commitment['finalRecordDigest'], isNot(agentStoreEmptyDigest));
    final segments = manifest['segments']! as List<Object?>;
    expect(
      (segments.single! as Map<String, Object?>)['startSequence'],
      2,
    );
  });

  test('prune at head can recover with no retained segment', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );
    await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: before.sequence,
    );

    final loaded = await fixture.store.loadSession(fileTestSessionId);
    expect(loaded.head.sequence, 2);
    expect(loaded.head.historyFloorSequence, 2);
    expect(
      (await fixture.store.readEvents(
        fileTestSessionId,
        after: const AgentStoreCursor(2),
      ))
          .events,
      isEmpty,
    );
    expect(
      _latestSessionManifest(fixture)['segments'],
      isEmpty,
    );
  });

  test('pending or unknown snapshot projection cannot be pruned', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(before, safeToPrune: false),
      expectedHead: before,
    );

    expect(
      () => fixture.store.compact(
        fileTestSessionId,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 1,
      ),
      storeError(AgentStoreErrorCode.invalidTransaction),
    );
    expect(
      (await fixture.store.loadSession(fileTestSessionId))
          .head
          .historyFloorSequence,
      0,
    );
  });

  test('non-reducer snapshot projection cannot be pruned', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final projection = <String, Object?>{
      'approvals': <String, Object?>{},
      'currentRunId': null,
      'deferredOperations': <String, Object?>{},
      'resources': <String, Object?>{},
      'workItems': <String, Object?>{},
    };
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(
        before,
        variant: 10,
        canonicalProjection: projection,
      ),
      expectedHead: before,
    );

    expect(
      () => fixture.store.compact(
        fileTestSessionId,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 1,
      ),
      storeError(AgentStoreErrorCode.invalidTransaction),
    );
    expect(
      (await fixture.store.loadSession(fileTestSessionId))
          .head
          .historyFloorSequence,
      0,
    );
  });

  test('history floor never retreats', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );
    final compact = await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );

    expect(
      () => fixture.store.compact(
        fileTestSessionId,
        expectedHead: compact.afterHead,
        throughSequence: 0,
      ),
      storeError(AgentStoreErrorCode.invalidTransaction),
    );
  });

  test('prune floor cannot split an atomic multi-event batch', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final commandId = fileCommandId(90);
    final firstEventId = fileEventId(3, variant: 90);
    final secondEventId = fileEventId(4, variant: 90);
    await fixture.store.append(
      AgentStoreTransaction(
        sessionId: fileTestSessionId,
        expectedHead: before,
        acceptedCommand: AgentStoreAcceptedCommand(
          commandId: commandId,
          contentDigest: canonicalJsonSha256('multi-event-append'),
          receipt: const <String, Object?>{'kind': 'multi'},
        ),
        newIdAllocations: <AgentStoreIdAllocation>[
          AgentStoreIdAllocation(commandId),
          AgentStoreIdAllocation(firstEventId),
          AgentStoreIdAllocation(secondEventId),
        ],
        events: <AgentEvent>[
          fileEvent(
            3,
            commandId: commandId,
            eventId: firstEventId,
            type: AgentEventType.sessionCapabilitiesPinned,
          ),
          fileEvent(
            4,
            commandId: commandId,
            eventId: secondEventId,
            type: AgentEventType.sessionCapabilitiesPinned,
          ),
        ],
      ),
    );
    final appended = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshot = await fixture.store.writeSnapshot(
      fileSnapshot(appended, variant: 9),
      expectedHead: appended,
    );

    expect(
      () => fixture.store.compact(
        fileTestSessionId,
        expectedHead: snapshot.afterHead,
        throughSequence: 3,
      ),
      storeError(AgentStoreErrorCode.invalidTransaction),
    );
    expect(
      (await fixture.store.loadSession(fileTestSessionId))
          .head
          .historyFloorSequence,
      0,
    );
  });
}

Map<String, Object?> _latestSessionManifest(FileStoreFixture fixture) {
  final directory = StoreLayout.open(fixture.root).manifests(fileTestSessionId);
  final files = directory.listSync().whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  return jsonDecode(files.last.readAsStringSync())! as Map<String, Object?>;
}
