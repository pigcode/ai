import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  setUp(() async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    await fixture.store.append(fileAppendTransaction(before));
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('failure before manifest publish leaves previous generation valid',
      () async {
    var inject = false;
    final sessionManifestDirectory =
        StoreLayout.open(fixture.root).manifests(fileTestSessionId).path;
    final faulty = await fixture.open(
      options: FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
        faults: StoreWriterFaults((point, target) {
          if (inject &&
              point == StoreWriterFaultPoint.beforePublish &&
              target.parent.path == sessionManifestDirectory) {
            inject = false;
            throw StateError('injected compaction manifest failure');
          }
        }),
      ),
    );
    final before = (await faulty.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await faulty.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );
    inject = true;

    expect(
      () => faulty.compact(
        fileTestSessionId,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 1,
      ),
      storeError(AgentStoreErrorCode.ioFailure),
    );
    final recovered = await fixture.store.loadSession(fileTestSessionId);
    expect(recovered.head, snapshotReceipt.afterHead);
    expect(recovered.head.historyFloorSequence, 0);
  });

  test('post-commit receipt loss retries the persisted compaction', () async {
    var loseReceipt = true;
    final lossy = await fixture.open(
      options: FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
        commitFaults: StoreCommitFaults((point) {
          if (loseReceipt && point == StoreCommitPoint.compaction) {
            loseReceipt = false;
            throw StateError('injected compaction receipt loss');
          }
        }),
      ),
    );
    final before = (await lossy.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await lossy.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );

    await expectLater(
      () => lossy.compact(
        fileTestSessionId,
        expectedHead: snapshotReceipt.afterHead,
        throughSequence: 1,
      ),
      throwsStateError,
    );
    final retry = await lossy.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );
    expect(retry.afterHead.historyFloorSequence, 1);
  });
}
