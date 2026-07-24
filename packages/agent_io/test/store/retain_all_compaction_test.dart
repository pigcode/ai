import 'dart:io';

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

  test('retainAll is default and preserves history and cursor zero', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshot = fileSnapshot(before);
    final snapshotReceipt = await fixture.store.writeSnapshot(
      snapshot,
      expectedHead: before,
    );
    final segmentCountBefore = _segmentFiles(fixture).length;
    final compact = await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );

    expect(compact.afterHead.historyFloorSequence, 0);
    expect(_segmentFiles(fixture), hasLength(segmentCountBefore));
    expect(
      (await fixture.store.readEvents(fileTestSessionId))
          .events
          .map((event) => event.sequence),
      <int>[1, 2],
    );
  });

  test('retainAll compaction retry is idempotent', () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(before),
      expectedHead: before,
    );
    final first = await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );
    final retry = await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );

    expect(retry.afterHead, first.afterHead);
  });
}

List<File> _segmentFiles(FileStoreFixture fixture) => fixture.root
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.pigj'))
    .toList();
