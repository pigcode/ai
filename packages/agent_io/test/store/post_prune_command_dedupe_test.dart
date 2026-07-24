import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;
  late AgentStoreTransaction accepted;
  late AgentStoreAppendReceipt acceptedReceipt;

  setUp(() async {
    fixture = await FileStoreFixture.create(
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
      ),
    );
    await fixture.createSession();
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    accepted = fileAppendTransaction(before, variant: 5);
    acceptedReceipt = await fixture.store.append(accepted);
    final head = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(head),
      expectedHead: head,
    );
    await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: head.sequence,
    );
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('accepted command remains retryable after its event is pruned',
      () async {
    final retry = await fixture.store.append(accepted);
    expect(retry.afterHead, acceptedReceipt.afterHead);

    final mismatch = AgentStoreTransaction(
      sessionId: accepted.sessionId,
      expectedHead: accepted.expectedHead,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: accepted.acceptedCommand!.commandId,
        contentDigest: canonicalJsonSha256('different'),
        receipt: accepted.acceptedCommand!.receipt,
      ),
      newIdAllocations: accepted.newIdAllocations,
      events: accepted.events,
    );
    expect(
      () => fixture.store.append(mismatch),
      storeError(AgentStoreErrorCode.commandContentMismatch),
    );
  });

  test('root create retry remains bound after Session prune', () async {
    final root = await fixture.store.loadRoot();
    final original = fileCreateTransaction(AgentStoreRootHead.empty);
    final retry = await fixture.store.createSession(original);

    expect(retry.sessionId, fileTestSessionId);
    expect(root.sessionIds, <SessionId>{fileTestSessionId});
  });
}
