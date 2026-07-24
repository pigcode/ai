import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  setUp(() async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('selected valid generation with missing snapshot fails closed',
      () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshot = _snapshot(before);
    await fixture.store.writeSnapshot(snapshot, expectedHead: before);
    final snapshotFile = fixture.root
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.pigs'));
    snapshotFile.deleteSync();

    expect(
      () => fixture.store.loadSession(fileTestSessionId),
      storeError(AgentStoreErrorCode.corruption),
    );
  });

  test('invalid generation above a valid snapshot falls back safely', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshot = _snapshot(before);
    await fixture.store.writeSnapshot(snapshot, expectedHead: before);
    final directory =
        StoreLayout.open(fixture.root).manifests(fileTestSessionId);
    File.fromUri(directory.uri.resolve(
      '00000000000000000003-${''.padLeft(64, '0')}.json',
    )).writeAsStringSync('partial');

    final loaded = await fixture.store.loadSession(fileTestSessionId);
    expect(loaded.snapshot!.snapshotId, snapshot.snapshotId);
    expect(loaded.head.generation, 2);
  });
}

AgentStoreSnapshot _snapshot(AgentStoreHead head) {
  final projection = <String, Object?>{
    'journalSequence': head.sequence,
  };
  return AgentStoreSnapshot(
    sessionId: fileTestSessionId,
    snapshotId: SnapshotId.parse('snp_00000000000000000000000000000000'),
    sequence: head.sequence,
    journalHeadDigest: head.journalHeadDigest,
    historyFloorSequence: head.historyFloorSequence,
    identityRegistryRootDigest: head.identityRegistryRootDigest,
    commandRegistryRootDigest: head.commandRegistryRootDigest,
    canonicalProjection: projection,
    projectionDigest: canonicalJsonSha256(projection),
  );
}
