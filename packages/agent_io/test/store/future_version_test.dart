import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/store_faults.dart';
import 'store_test_support.dart';

void main() {
  const recovery = StoreRecovery();

  test('future Store and frame versions are rejected', () {
    final sealed = testSealedSegment();

    for (final offset in <int>[9, 11]) {
      final future = changedStoreByte(sealed, offset, 2);
      expect(
        () => recovery.recoverJournalChain(
          sessionId: testSessionId,
          segments: <Uint8List>[future],
          allowFinalOpenTail: false,
        ),
        throwsA(
          isA<StoreCorruptionException>().having(
            (error) => error.category,
            'category',
            StoreCorruptionCategory.futureVersion,
          ),
        ),
      );
    }
  });
}
