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
    final head = (await fixture.store.loadSession(fileTestSessionId)).head;
    final snapshotReceipt = await fixture.store.writeSnapshot(
      fileSnapshot(head),
      expectedHead: head,
    );
    await fixture.store.compact(
      fileTestSessionId,
      expectedHead: snapshotReceipt.afterHead,
      throughSequence: 1,
    );
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('ID from physically pruned event remains an exact duplicate', () async {
    final head = (await fixture.store.loadSession(fileTestSessionId)).head;
    final commandId = fileCommandId(3);
    final eventId = fileEventId(2, variant: 3);
    final transaction = AgentStoreTransaction(
      sessionId: fileTestSessionId,
      expectedHead: head,
      acceptedCommand: AgentStoreAcceptedCommand(
        commandId: commandId,
        contentDigest: canonicalJsonSha256('reuse-pruned-id'),
        receipt: const <String, Object?>{'kind': 'reuse'},
      ),
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(commandId),
        AgentStoreIdAllocation(eventId),
        AgentStoreIdAllocation(fileEventId(1)),
      ],
      events: <AgentEvent>[
        fileEvent(
          2,
          commandId: commandId,
          eventId: eventId,
          type: AgentEventType.sessionCapabilitiesPinned,
        ),
      ],
    );

    expect(
      () => fixture.store.append(transaction),
      storeError(AgentStoreErrorCode.duplicateId),
    );
  });

  test('registry limit rejects allocation before journal publication',
      () async {
    final limited = await fixture.open(
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
        limits: StoreLimits(maximumRegistryEntries: 4),
      ),
    );
    final before = (await limited.loadSession(fileTestSessionId)).head;
    final segmentCount = StoreLayout.open(fixture.root)
        .segments(fileTestSessionId)
        .listSync()
        .length;

    expect(
      () => limited.append(fileAppendTransaction(before, variant: 4)),
      storeError(AgentStoreErrorCode.resourceLimit),
    );
    expect(
      StoreLayout.open(fixture.root)
          .segments(fileTestSessionId)
          .listSync()
          .length,
      segmentCount,
    );
  });
}
