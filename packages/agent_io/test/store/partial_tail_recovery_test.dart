import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/store_faults.dart';
import 'store_test_support.dart';

void main() {
  const recovery = StoreRecovery();

  test('only a complete header is the minimum recoverable open prefix', () {
    final open = _twoBatchOpenSegment();
    for (var length = 0; length < agentSegmentHeaderLength; length++) {
      expect(
        () => recovery.recoverJournalChain(
          sessionId: testSessionId,
          segments: <Uint8List>[
            Uint8List.sublistView(open, 0, length),
          ],
        ),
        throwsA(
          isA<StoreCorruptionException>().having(
            (error) => error.category,
            'category',
            StoreCorruptionCategory.truncatedHeader,
          ),
        ),
      );
    }
  });

  test('partial second batch truncates from BAT1 and preserves first batch',
      () {
    final open = _twoBatchOpenSegment();
    final decoded = const JournalFrameCodec().decodeSegment(open);
    final secondBatchOffset = decoded.batches[1].offset;

    for (var length = secondBatchOffset + 1; length < open.length; length++) {
      final report = recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[
          Uint8List.sublistView(open, 0, length),
        ],
      );
      expect(
        report.events.map((event) => event.sequence),
        <int>[1],
        reason: 'prefix $length must discard all of batch two',
      );
      expect(report.segments.single.validLength, secondBatchOffset);
      expect(report.discardedPartialTail, isTrue);
      expect(report.diagnostics.single.offset, secondBatchOffset);
    }
  });

  test('multi-event batch does not commit a complete frame prefix', () {
    final open = const JournalFrameCodec().encodeSegment(
      sessionId: testSessionId,
      startSequence: 1,
      previousSegmentFinalDigest: Uint8List(32),
      batches: testJournalBatches(),
      seal: false,
    );
    final frameOffsets = _magicOffsets(open, agentEventFrameMagic);
    expect(frameOffsets, hasLength(2));
    final truncateInsideSecondFrame = frameOffsets[1] + 40;
    final report = recovery.recoverJournalChain(
      sessionId: testSessionId,
      segments: <Uint8List>[
        Uint8List.sublistView(open, 0, truncateInsideSecondFrame),
      ],
    );

    expect(report.events, isEmpty);
    expect(report.segments.single.validLength, agentSegmentHeaderLength);
  });

  test('sealed prefixes and complete digest mismatches fail closed', () {
    final sealed = testSealedSegment();
    for (final prefix in everyTruncatedPrefix(sealed)) {
      expect(
        () => recovery.recoverJournalChain(
          sessionId: testSessionId,
          segments: <Uint8List>[prefix],
          allowFinalOpenTail: false,
        ),
        throwsA(isA<StoreCorruptionException>()),
      );
    }

    final frame = _magicOffsets(sealed, agentEventFrameMagic).first;
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
      throwsA(
        isA<StoreCorruptionException>().having(
          (error) => error.category,
          'category',
          StoreCorruptionCategory.digestMismatch,
        ),
      ),
    );
  });

  test('safe diagnostic contains no event payload', () {
    const diagnostic = StoreCorruptionException(
      category: StoreCorruptionCategory.digestMismatch,
      sequence: 7,
      offset: 99,
      digest: 'abc',
    );

    expect(diagnostic.toString(), contains('sequence=7'));
    expect(diagnostic.toString(), isNot(contains('definitionRef')));
  });
}

Uint8List _twoBatchOpenSegment() => const JournalFrameCodec().encodeSegment(
      sessionId: testSessionId,
      startSequence: 1,
      previousSegmentFinalDigest: Uint8List(32),
      batches: <JournalBatch>[
        JournalBatch(
          transactionMetadata: const <String, Object?>{
            'schemaVersion': 1,
          },
          events: <AgentEvent>[testStoreEvent(1)],
        ),
        JournalBatch(
          transactionMetadata: const <String, Object?>{
            'schemaVersion': 1,
          },
          events: <AgentEvent>[testStoreEvent(2)],
        ),
      ],
      seal: false,
    );

List<int> _magicOffsets(Uint8List bytes, String magic) {
  final needle = ascii.encode(magic);
  final offsets = <int>[];
  for (var offset = 0; offset <= bytes.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (bytes[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) offsets.add(offset);
  }
  return offsets;
}
