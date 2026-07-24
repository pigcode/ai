import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'journal_frame_codec.dart';
import 'recovery_report.dart';
import 'store_corruption.dart';
import 'store_digest.dart';
import 'store_format.dart';

final class StoreRecovery {
  const StoreRecovery({
    this.codec = const JournalFrameCodec(),
  });

  final JournalFrameCodec codec;

  Future<DecodedJournalSegment> recoverSealedSegmentFile({
    required File file,
    required SessionId sessionId,
    required int expectedStartSequence,
    required List<int> previousFinalRecordDigest,
    required String expectedArtifactDigest,
  }) async {
    if (expectedStartSequence <= 0 ||
        previousFinalRecordDigest.length != 32 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedArtifactDigest)) {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Streaming recovery inputs are invalid.',
      );
    }
    final handle = await file.open();
    try {
      final fileLength = await handle.length();
      if (fileLength < agentSegmentHeaderLength + agentSegmentFooterLength) {
        throw const StoreFormatException(
          StoreFormatErrorCode.truncated,
          'Sealed segment is shorter than its header and footer.',
        );
      }
      final artifactDigest = StoreDigestAccumulator.sha256();
      final segmentDigest = StoreDigestAccumulator.domain(
        'pigcode-agent-segment-v1',
      );
      var segmentDigestBytesRemaining = fileLength - 40;

      Future<Uint8List> readTracked(int length) async {
        final bytes = await _readExact(handle, length);
        artifactDigest.add(bytes);
        if (segmentDigestBytesRemaining > 0) {
          final included = length < segmentDigestBytesRemaining
              ? length
              : segmentDigestBytesRemaining;
          segmentDigest.add(
            included == bytes.length
                ? bytes
                : Uint8List.sublistView(bytes, 0, included),
          );
          segmentDigestBytesRemaining -= included;
        }
        return bytes;
      }

      final header = codec.decodeSegmentHeader(
        await readTracked(agentSegmentHeaderLength),
      );
      if (header.sessionId != sessionId ||
          header.startSequence != expectedStartSequence ||
          !storeBytesEqual(
            header.previousSegmentFinalDigest,
            previousFinalRecordDigest,
          )) {
        throw const StoreFormatException(
          StoreFormatErrorCode.sequenceViolation,
          'Segment header does not continue the expected Journal chain.',
        );
      }

      final batches = <DecodedJournalBatch>[];
      var expectedSequence = expectedStartSequence;
      var previousDigest = Uint8List.fromList(previousFinalRecordDigest);
      var recordCount = 0;
      while (await handle.position() < fileLength - agentSegmentFooterLength) {
        final prefix = await readTracked(8);
        final magic = String.fromCharCodes(prefix.sublist(0, 4));
        if (magic != agentBatchMagic) {
          throw const StoreFormatException(
            StoreFormatErrorCode.invalidMagic,
            'Expected a framed batch before the sealed footer.',
          );
        }
        final headerLength =
            ByteData.sublistView(prefix, 4, 8).getUint32(0, Endian.big);
        if (headerLength < agentBatchHeaderFixedLength ||
            headerLength > codec.limits.maximumBatchBytes) {
          throw const StoreFormatException(
            StoreFormatErrorCode.invalidLength,
            'Batch header length is outside configured bounds.',
          );
        }
        final headerSuffix = await readTracked(headerLength - 8);
        final eventCount =
            ByteData.sublistView(headerSuffix, 0, 4).getUint32(0, Endian.big);
        if (eventCount <= 0 ||
            eventCount > codec.limits.maximumBatchEventCount) {
          throw const StoreFormatException(
            StoreFormatErrorCode.batchViolation,
            'Batch event count is invalid.',
          );
        }
        final batchBytes = BytesBuilder(copy: false)
          ..add(prefix)
          ..add(headerSuffix);
        var batchLength = headerLength;
        for (var index = 0; index < eventCount; index++) {
          final framePrefix = await readTracked(8);
          final frameMagic = String.fromCharCodes(
            framePrefix.sublist(0, 4),
          );
          if (frameMagic != agentEventFrameMagic) {
            throw const StoreFormatException(
              StoreFormatErrorCode.invalidMagic,
              'Expected an event frame in the Journal batch.',
            );
          }
          final frameLength =
              ByteData.sublistView(framePrefix, 4, 8).getUint32(0, Endian.big);
          if (frameLength < agentEventFrameFixedLength ||
              frameLength > codec.limits.maximumBatchBytes ||
              batchLength + frameLength > codec.limits.maximumBatchBytes) {
            throw const StoreFormatException(
              StoreFormatErrorCode.resourceLimit,
              'Streaming Journal batch exceeds the configured byte limit.',
            );
          }
          batchBytes
            ..add(framePrefix)
            ..add(await readTracked(frameLength - 8));
          batchLength += frameLength;
        }
        final decoded = codec.decodeBatchFrame(
          batchBytes.takeBytes(),
          sessionId: sessionId,
          expectedSequence: expectedSequence,
          previousRecordDigest: previousDigest,
        );
        batches.add(decoded);
        expectedSequence += decoded.events.length;
        recordCount += decoded.events.length;
        previousDigest = decoded.recordDigests.last;
      }
      if (await handle.position() != fileLength - agentSegmentFooterLength) {
        throw const StoreFormatException(
          StoreFormatErrorCode.invalidLength,
          'Segment batches do not end at the sealed footer boundary.',
        );
      }
      final footer = codec.decodeSegmentFooter(
        await readTracked(agentSegmentFooterLength),
      );
      if (await handle.position() != fileLength ||
          batches.isEmpty ||
          footer.endSequence != expectedSequence - 1 ||
          footer.recordCount != recordCount ||
          !storeBytesEqual(footer.finalRecordDigest, previousDigest)) {
        throw const StoreFormatException(
          StoreFormatErrorCode.sequenceViolation,
          'Segment footer does not bind its streamed records.',
        );
      }
      if (segmentDigestBytesRemaining != 0 ||
          !storeBytesEqual(footer.segmentDigest, segmentDigest.close())) {
        throw const StoreFormatException(
          StoreFormatErrorCode.digestMismatch,
          'Streamed segment digest does not match its footer.',
        );
      }
      if (storeHex(artifactDigest.close()) != expectedArtifactDigest) {
        throw const StoreFormatException(
          StoreFormatErrorCode.digestMismatch,
          'Streamed artifact digest does not match its manifest.',
        );
      }
      return DecodedJournalSegment(
        sessionId: sessionId,
        startSequence: expectedStartSequence,
        previousSegmentFinalDigest:
            Uint8List.fromList(previousFinalRecordDigest),
        batches: batches,
        sealed: true,
        endSequence: footer.endSequence,
        recordCount: recordCount,
        finalRecordDigest: footer.finalRecordDigest,
        segmentDigest: footer.segmentDigest,
        validLength: fileLength,
        discardedTailLength: 0,
      );
    } finally {
      await handle.close();
    }
  }

  RecoveryReport recoverJournalChain({
    required SessionId sessionId,
    required List<Uint8List> segments,
    bool allowFinalOpenTail = true,
    int expectedStartSequence = 1,
    Uint8List? previousFinalRecordDigest,
  }) {
    if (segments.isEmpty) {
      throw const StoreCorruptionException(
        category: StoreCorruptionCategory.truncatedHeader,
      );
    }
    final decoded = <DecodedJournalSegment>[];
    final diagnostics = <RecoveryDiagnostic>[];
    if (expectedStartSequence <= 0 ||
        (previousFinalRecordDigest != null &&
            previousFinalRecordDigest.length != 32)) {
      throw const StoreCorruptionException(
        category: StoreCorruptionCategory.invalidFrame,
      );
    }
    var expectedSequence = expectedStartSequence;
    var previousDigest = previousFinalRecordDigest ?? Uint8List(32);
    for (var index = 0; index < segments.length; index++) {
      final isFinal = index == segments.length - 1;
      final allowRecovery = isFinal && allowFinalOpenTail;
      late final DecodedJournalSegment segment;
      try {
        segment = allowRecovery
            ? codec.recoverOpenSegment(
                segments[index],
                expectedPreviousSegmentFinalDigest: previousDigest,
              )
            : codec.decodeSegment(
                segments[index],
                requireSealed: true,
                expectedPreviousSegmentFinalDigest: previousDigest,
              );
      } on StoreFormatException catch (error) {
        throw StoreCorruptionException.fromFormat(
          error,
          sealed: !allowRecovery,
        );
      }
      if (segment.sessionId != sessionId) {
        throw StoreCorruptionException(
          category: StoreCorruptionCategory.sessionMismatch,
          sequence: segment.startSequence,
        );
      }
      if (segment.startSequence != expectedSequence) {
        throw StoreCorruptionException(
          category: StoreCorruptionCategory.gapOrOverlap,
          sequence: segment.startSequence,
        );
      }
      if (!isFinal && !segment.sealed) {
        throw StoreCorruptionException(
          category: StoreCorruptionCategory.sealedSegmentInvalid,
          sequence: segment.startSequence,
        );
      }
      if (segment.discardedTailLength > 0) {
        diagnostics.add(RecoveryDiagnostic(
          category: RecoveryDiagnosticCategory.partialFinalTailDiscarded,
          segmentIndex: index,
          offset: segment.validLength,
          discardedBytes: segment.discardedTailLength,
        ));
      }
      decoded.add(segment);
      expectedSequence = segment.startSequence + segment.recordCount;
      previousDigest = segment.finalRecordDigest;
    }
    return RecoveryReport(
      sessionId: sessionId,
      segments: decoded,
      diagnostics: diagnostics,
    );
  }
}

Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
  final output = Uint8List(length);
  var offset = 0;
  while (offset < length) {
    final count = await file.readInto(output, offset, length);
    if (count == 0) {
      throw StoreFormatException(
        StoreFormatErrorCode.truncated,
        'Journal bytes end inside a streamed frame.',
        offset: await file.position(),
      );
    }
    offset += count;
  }
  return output;
}
