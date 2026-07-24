import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/store_faults.dart';
import 'store_test_support.dart';

void main() {
  const recovery = StoreRecovery();

  test('sealed record corruption is never treated as a recoverable tail', () {
    final sealed = testSealedSegment();
    final frame = _firstMagic(sealed, agentEventFrameMagic);
    final corrupted = changedStoreByte(
      sealed,
      frame + 100,
      sealed[frame + 100] ^ 1,
    );

    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[corrupted],
      ),
      throwsCategory(StoreCorruptionCategory.digestMismatch),
    );
  });

  test('sealed footer corruption fails closed', () {
    final sealed = testSealedSegment();
    final footer = sealed.length - agentSegmentFooterLength;
    final corrupted = changedStoreByte(
      sealed,
      footer + 65,
      sealed[footer + 65] ^ 1,
    );

    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[corrupted],
      ),
      throwsCategory(StoreCorruptionCategory.digestMismatch),
    );
  });
}

Matcher throwsCategory(StoreCorruptionCategory category) => throwsA(
      isA<StoreCorruptionException>().having(
        (error) => error.category,
        'category',
        category,
      ),
    );

int _firstMagic(Uint8List bytes, String magic) {
  final needle = ascii.encode(magic);
  for (var offset = 0; offset <= bytes.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (bytes[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  throw StateError('Magic not found.');
}
