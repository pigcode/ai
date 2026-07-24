import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  setUp(() async {
    fixture = await FileStoreFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('capability cannot be rebound to another canonical root', () async {
    final otherRoot = Directory.fromUri(
      fixture.temporary.uri.resolve('other-store/'),
    )..createSync();

    expect(
      () => FileAgentStore.open(
        root: otherRoot,
        coordinator: fixture.coordinator.client,
      ),
      storeError(AgentStoreErrorCode.coordinationRequired),
    );
  });

  test('mismatched nonce is rejected by the owner isolate', () async {
    final mismatched = fixture.coordinator.capability.connect(
      expectedNonce: ''.padLeft(64, '0'),
    );

    expect(
      () => FileAgentStore.open(
        root: fixture.root,
        coordinator: mismatched,
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        ),
      ),
      storeError(AgentStoreErrorCode.coordinationRequired),
    );
  });

  test('closed coordinator cannot fall back to a local mutex', () async {
    final client = fixture.coordinator.client;
    await fixture.coordinator.close();

    expect(
      () => FileAgentStore.open(
        root: fixture.root,
        coordinator: client,
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
          coordinatorTimeout: Duration(milliseconds: 25),
        ),
      ),
      storeError(AgentStoreErrorCode.storeBusy),
    );
  });
}
