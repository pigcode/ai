import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../store/file_store_test_support.dart';

void main() {
  test('P3-TM-ELEV-06 Store operation rejects a symlink in its tree', () async {
    final fixture = await FileStoreFixture.create();
    try {
      final outside = File.fromUri(fixture.temporary.uri.resolve('outside'))
        ..writeAsStringSync('outside');
      Link.fromUri(fixture.root.uri.resolve('linked')).createSync(outside.path);

      await expectLater(
        fixture.store.loadRoot(),
        storeError(AgentStoreErrorCode.corruption),
      );
    } finally {
      await fixture.dispose();
    }
  });

  test('P3-TM-ELEV-07 non-regular expected artifact is rejected', () {
    final temporary =
        Directory.systemTemp.createTempSync('store-entity-security-');
    try {
      final root = Directory.fromUri(temporary.uri.resolve('store/'))
        ..createSync();
      final layout = StoreLayout.open(root);

      expect(
        () => layout.validateExistingArtifact(File(layout.root.path)),
        throwsA(
          isA<StoreLayoutException>().having(
            (error) => error.code,
            'code',
            StoreLayoutErrorCode.unexpectedEntity,
          ),
        ),
      );
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });
}
