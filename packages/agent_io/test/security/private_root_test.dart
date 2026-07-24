import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../store/file_store_test_support.dart';

void main() {
  test('P3-TM-INFO-04 production mode requires a provably private root',
      () async {
    final temporary =
        Directory.systemTemp.createTempSync('store-private-security-');
    final root = Directory.fromUri(temporary.uri.resolve('store/'))
      ..createSync();
    final coordinator =
        await FileStoreCoordinator.start(StoreLayout.open(root));
    try {
      if (Platform.isWindows) {
        await expectLater(
          FileAgentStore.open(
            root: root,
            coordinator: coordinator.client,
          ),
          storeError(AgentStoreErrorCode.insecureRoot),
        );
      } else {
        _chmod(root, '755');
        await expectLater(
          FileAgentStore.open(
            root: root,
            coordinator: coordinator.client,
          ),
          storeError(AgentStoreErrorCode.insecureRoot),
        );

        _chmod(root, '700');
        final store = await FileAgentStore.open(
          root: root,
          coordinator: coordinator.client,
        );
        expect((await store.loadRoot()).head, AgentStoreRootHead.empty);
      }
    } finally {
      await coordinator.close();
      temporary.deleteSync(recursive: true);
    }
  });

  test('P3-TM-INFO-05 permission bypass is explicit and test-only', () async {
    final fixture = await FileStoreFixture.create();
    try {
      expect((await fixture.store.loadRoot()).head, AgentStoreRootHead.empty);
      expect(
        fixture.store.options.rootAccessPolicy,
        FileStoreRootAccessPolicy.explicitTestOnly,
      );
    } finally {
      await fixture.dispose();
    }
  });
}

void _chmod(Directory root, String mode) {
  final result = Process.runSync('chmod', <String>[mode, root.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed for the private-root security test.');
  }
}
