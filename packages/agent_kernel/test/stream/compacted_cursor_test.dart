import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('cursor below compacted history floor returns cursorCompacted',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final beforeSnapshot =
        (await fixture.store.loadSession(running.sessionId)).head;
    final projection =
        (await fixture.kernel.loadProjection(running.sessionId)).toJson();
    final snapshot = AgentStoreSnapshot(
      sessionId: running.sessionId,
      snapshotId: SnapshotId.parse('snp_90000000000000000000000000000000'),
      sequence: beforeSnapshot.sequence,
      journalHeadDigest: beforeSnapshot.journalHeadDigest,
      historyFloorSequence: beforeSnapshot.historyFloorSequence,
      identityRegistryRootDigest: beforeSnapshot.identityRegistryRootDigest,
      commandRegistryRootDigest: beforeSnapshot.commandRegistryRootDigest,
      canonicalProjection: projection,
      projectionDigest: canonicalJsonSha256(projection),
    );
    final snapshotReceipt = await fixture.store.writeSnapshot(
      snapshot,
      expectedHead: beforeSnapshot,
      requestedDurability: AgentStoreDurability.memory,
    );
    await fixture.store.compact(
      running.sessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 3,
      requestedDurability: AgentStoreDurability.memory,
    );
    expect(
      canonicalJsonEncode(
        (await fixture.kernel.loadProjection(running.sessionId)).toJson(),
      ),
      canonicalJsonEncode(projection),
    );

    final subscription = fixture.kernel.subscribeEvents(
      sessionId: running.sessionId,
      cursor: AgentEventCursor(
        sessionId: running.sessionId,
        sequence: 0,
      ),
    );
    final errors = <Object>[];
    final completed = Completer<void>();
    subscription.stream.listen(
      (_) {},
      onError: errors.add,
      onDone: completed.complete,
    );
    await completed.future;

    expect(
      errors.single,
      isA<SubscriptionError>().having(
        (error) => error.code,
        'code',
        SubscriptionErrorCode.cursorCompacted,
      ),
    );
  });
}
