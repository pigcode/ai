import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
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
    final createHead =
        (await fixture.store.loadSession(fileTestSessionId)).head;
    await fixture.store.append(fileAppendTransaction(createHead));
    final appendHead =
        (await fixture.store.loadSession(fileTestSessionId)).head;
    final firstSnapshot = await fixture.store.writeSnapshot(
      fileSnapshot(appendHead, variant: 1),
      expectedHead: appendHead,
    );
    await fixture.store.compact(
      fileTestSessionId,
      expectedHead: firstSnapshot.afterHead,
      throughSequence: appendHead.sequence,
    );
    final compactHead =
        (await fixture.store.loadSession(fileTestSessionId)).head;
    await fixture.store.writeSnapshot(
      fileSnapshot(compactHead, variant: 2),
      expectedHead: compactHead,
    );
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('GC protects latest two generations and is idempotent', () async {
    final first = await fixture.store.garbageCollect(fileTestSessionId);
    expect(first.retiredCount, greaterThan(0));
    expect(first.deletedCount, 0);
    expect(
      StoreLayout.open(fixture.root)
          .retired(fileTestSessionId)
          .listSync()
          .whereType<File>(),
      isNotEmpty,
    );

    final second = await fixture.store.garbageCollect(fileTestSessionId);
    expect(second.deletedCount, first.retiredCount);
    final third = await fixture.store.garbageCollect(fileTestSessionId);
    expect(third.retiredCount, 0);
    expect(third.deletedCount, 0);

    final loaded = await fixture.store.loadSession(fileTestSessionId);
    expect(loaded.head.generation, 5);
    final manifests = StoreLayout.open(fixture.root)
        .manifests(fileTestSessionId)
        .listSync()
        .whereType<File>()
        .toList();
    expect(manifests, hasLength(2));
  });
}
