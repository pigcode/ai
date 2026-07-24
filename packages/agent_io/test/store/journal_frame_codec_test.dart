import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'store_test_support.dart';

void main() {
  const codec = JournalFrameCodec();

  test('round-trips a batch-aware sealed segment', () {
    final bytes = testSealedSegment();
    final decoded = codec.decodeSegment(bytes, requireSealed: true);

    expect(decoded.sessionId, testSessionId);
    expect(decoded.startSequence, 1);
    expect(decoded.events.map((event) => event.sequence), <int>[1, 2]);
    expect(decoded.batches, hasLength(1));
    expect(decoded.batches.single.recordDigests, hasLength(2));
    expect(decoded.recordCount, 2);
    expect(decoded.endSequence, 2);
    expect(decoded.sealed, isTrue);
    expect(decoded.validLength, bytes.length);
  });

  test('streaming recovery validates a sealed artifact batch by batch',
      () async {
    final directory = Directory.systemTemp.createTempSync(
      'agent_store_streaming_recovery_',
    );
    try {
      final bytes = testSealedSegment();
      final file = File.fromUri(directory.uri.resolve('segment.bin'));
      await file.writeAsBytes(bytes, flush: true);
      final decoded = await const StoreRecovery().recoverSealedSegmentFile(
        file: file,
        sessionId: testSessionId,
        expectedStartSequence: 1,
        previousFinalRecordDigest: Uint8List(32),
        expectedArtifactDigest: storeHex(storeSha256(bytes)),
      );

      expect(decoded.events.map((event) => event.sequence), <int>[1, 2]);
      expect(decoded.sealed, isTrue);
      expect(decoded.validLength, bytes.length);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('every sealed byte boundary rejects truncation', () {
    final bytes = testSealedSegment();

    for (var length = 0; length < bytes.length; length++) {
      expect(
        () => codec.decodeSegment(
          Uint8List.sublistView(bytes, 0, length),
          requireSealed: true,
        ),
        throwsA(isA<StoreFormatException>()),
        reason: 'prefix length $length must not decode as sealed',
      );
    }
  });

  test('validates previous segment digest before records', () {
    expect(
      () => codec.decodeSegment(
        testSealedSegment(),
        expectedPreviousSegmentFinalDigest: Uint8List.fromList(
          <int>[1, ...List<int>.filled(31, 0)],
        ),
      ),
      throwsStoreCode(StoreFormatErrorCode.digestMismatch),
    );
  });

  test('rejects wrong magic, length, version, and reserved bytes', () {
    final valid = testSealedSegment();
    final footer = valid.length - agentSegmentFooterLength;

    expect(
      () => codec.decodeSegment(_changed(valid, 0, 0)),
      throwsStoreCode(StoreFormatErrorCode.invalidMagic),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, 7, 95)),
      throwsStoreCode(StoreFormatErrorCode.invalidLength),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, 9, 2)),
      throwsStoreCode(StoreFormatErrorCode.unsupportedVersion),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, footer + 9, 2)),
      throwsStoreCode(StoreFormatErrorCode.unsupportedVersion),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, footer + 11, 1)),
      throwsStoreCode(StoreFormatErrorCode.invalidReserved),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, valid.length - 5, 99)),
      throwsStoreCode(StoreFormatErrorCode.invalidLength),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, valid.length - 1, 0)),
      throwsStoreCode(StoreFormatErrorCode.invalidMagic),
    );
  });

  test('rejects count, sequence, and record-chain inconsistencies', () {
    final valid = testSealedSegment();
    final batchHeaderLength = _u32(valid, agentSegmentHeaderLength + 4);
    final frame = agentSegmentHeaderLength + batchHeaderLength;

    expect(
      () => codec.decodeSegment(
        _changed(valid, agentSegmentHeaderLength + 11, 3),
      ),
      throwsStoreCode(StoreFormatErrorCode.batchViolation),
    );
    expect(
      () => codec.decodeSegment(
        _changed(valid, agentSegmentHeaderLength + 19, 2),
      ),
      throwsStoreCode(StoreFormatErrorCode.sequenceViolation),
    );
    expect(
      () => codec.decodeSegment(_changed(valid, frame + 87, 1)),
      throwsStoreCode(StoreFormatErrorCode.digestMismatch),
    );
  });

  test('validates configured body limit before body read or allocation', () {
    const small = JournalFrameCodec(
      limits: StoreLimits(maximumEventBodyBytes: 32),
    );
    expect(
      () => small.encodeSegment(
        sessionId: testSessionId,
        startSequence: 1,
        previousSegmentFinalDigest: Uint8List(32),
        batches: testJournalBatches(),
        seal: true,
      ),
      throwsStoreCode(StoreFormatErrorCode.bodyTooLarge),
    );

    final valid = testSealedSegment();
    final batchHeaderLength = _u32(valid, agentSegmentHeaderLength + 4);
    final frame = agentSegmentHeaderLength + batchHeaderLength;
    final malicious = Uint8List.fromList(valid);
    ByteData.sublistView(malicious).setUint32(
      frame + 88,
      StoreLimits.hardMaximumEventBodyBytes + 1,
      Endian.big,
    );
    expect(
      () => codec.decodeSegment(malicious),
      throwsStoreCode(StoreFormatErrorCode.bodyTooLarge),
    );
  });

  test('open segment is accepted only when sealing is not required', () {
    final bytes = codec.encodeSegment(
      sessionId: testSessionId,
      startSequence: 1,
      previousSegmentFinalDigest: Uint8List(32),
      batches: testJournalBatches(),
      seal: false,
    );

    expect(codec.decodeSegment(bytes).sealed, isFalse);
    expect(
      () => codec.decodeSegment(bytes, requireSealed: true),
      throwsStoreCode(StoreFormatErrorCode.truncated),
    );
  });
}

Matcher throwsStoreCode(StoreFormatErrorCode code) => throwsA(
      isA<StoreFormatException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );

Uint8List _changed(Uint8List source, int offset, int value) {
  final result = Uint8List.fromList(source);
  result[offset] = value;
  return result;
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);
