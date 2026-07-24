import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'store_digest.dart';
import 'store_format.dart';
import 'store_limits.dart';

final class JournalBatch {
  JournalBatch({
    required Map<String, Object?> transactionMetadata,
    required List<AgentEvent> events,
  })  : transactionMetadata =
            DomainJson.freeze(transactionMetadata)! as Map<String, Object?>,
        events = List<AgentEvent>.unmodifiable(events);

  final Map<String, Object?> transactionMetadata;
  final List<AgentEvent> events;
}

final class DecodedJournalBatch extends JournalBatch {
  DecodedJournalBatch({
    required super.transactionMetadata,
    required super.events,
    required this.batchDigest,
    required List<Uint8List> recordDigests,
    required this.offset,
    required this.length,
  }) : recordDigests = List<Uint8List>.unmodifiable(recordDigests);

  final Uint8List batchDigest;
  final List<Uint8List> recordDigests;
  final int offset;
  final int length;
}

final class DecodedJournalSegment {
  DecodedJournalSegment({
    required this.sessionId,
    required this.startSequence,
    required this.previousSegmentFinalDigest,
    required List<DecodedJournalBatch> batches,
    required this.sealed,
    required this.endSequence,
    required this.recordCount,
    required this.finalRecordDigest,
    required this.segmentDigest,
    required this.validLength,
    required this.discardedTailLength,
  }) : batches = List<DecodedJournalBatch>.unmodifiable(batches);

  final SessionId sessionId;
  final int startSequence;
  final Uint8List previousSegmentFinalDigest;
  final List<DecodedJournalBatch> batches;
  final bool sealed;
  final int? endSequence;
  final int recordCount;
  final Uint8List finalRecordDigest;
  final Uint8List? segmentDigest;
  final int validLength;
  final int discardedTailLength;

  List<AgentEvent> get events => <AgentEvent>[
        for (final batch in batches) ...batch.events,
      ];
}

final class JournalSegmentHeader {
  JournalSegmentHeader({
    required this.sessionId,
    required this.startSequence,
    required List<int> previousSegmentFinalDigest,
  }) : previousSegmentFinalDigest =
            Uint8List.fromList(previousSegmentFinalDigest);

  final SessionId sessionId;
  final int startSequence;
  final Uint8List previousSegmentFinalDigest;
}

final class JournalSegmentFooter {
  JournalSegmentFooter({
    required this.endSequence,
    required this.recordCount,
    required List<int> finalRecordDigest,
    required List<int> segmentDigest,
  })  : finalRecordDigest = Uint8List.fromList(finalRecordDigest),
        segmentDigest = Uint8List.fromList(segmentDigest);

  final int endSequence;
  final int recordCount;
  final Uint8List finalRecordDigest;
  final Uint8List segmentDigest;
}

final class JournalFrameCodec {
  const JournalFrameCodec({
    this.limits = const StoreLimits(),
  });

  final StoreLimits limits;

  JournalSegmentHeader decodeSegmentHeader(Uint8List bytes) {
    if (bytes.length != agentSegmentHeaderLength) {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Segment header must contain exactly 96 bytes.',
      );
    }
    final reader = _Reader(bytes);
    reader.expectMagic(agentSegmentHeaderMagic);
    reader.expectU32(agentSegmentHeaderLength);
    reader.expectU16(agentStoreFormatVersion);
    reader.expectU16(agentJournalFrameVersion);
    final sessionText = reader.readAscii(36);
    late final SessionId sessionId;
    try {
      sessionId = SessionId.parse(sessionText);
    } on FormatException {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidSession,
        'Segment header contains an invalid SessionId.',
      );
    }
    final startSequence = reader.readU64();
    if (startSequence <= 0) {
      throw const StoreFormatException(
        StoreFormatErrorCode.sequenceViolation,
        'Segment start sequence must be positive.',
      );
    }
    final previousSegmentFinalDigest = reader.readBytes(32);
    reader.expectU32(agentSegmentHeaderLength);
    reader.expectMagic(agentSegmentHeaderTrailingMagic);
    return JournalSegmentHeader(
      sessionId: sessionId,
      startSequence: startSequence,
      previousSegmentFinalDigest: previousSegmentFinalDigest,
    );
  }

  JournalSegmentFooter decodeSegmentFooter(Uint8List bytes) {
    if (bytes.length != agentSegmentFooterLength) {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Segment footer must contain exactly 100 bytes.',
      );
    }
    final reader = _Reader(bytes);
    reader.expectMagic(agentSegmentFooterMagic);
    reader.expectU32(agentSegmentFooterLength);
    reader.expectU16(1);
    reader.expectU16(
      0,
      errorCode: StoreFormatErrorCode.invalidReserved,
    );
    final endSequence = reader.readU64();
    final recordCount = reader.readU64();
    final finalRecordDigest = reader.readBytes(32);
    final segmentDigest = reader.readBytes(32);
    reader.expectU32(agentSegmentFooterLength);
    reader.expectMagic(agentSegmentFooterTrailingMagic);
    return JournalSegmentFooter(
      endSequence: endSequence,
      recordCount: recordCount,
      finalRecordDigest: finalRecordDigest,
      segmentDigest: segmentDigest,
    );
  }

  DecodedJournalBatch decodeBatchFrame(
    Uint8List bytes, {
    required SessionId sessionId,
    required int expectedSequence,
    required List<int> previousRecordDigest,
  }) {
    _requireDigest(previousRecordDigest);
    final reader = _Reader(bytes);
    final decoded = _decodeBatch(
      reader,
      sessionId,
      expectedSequence,
      Uint8List.fromList(previousRecordDigest),
    );
    if (!reader.isDone) {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Bytes follow the framed Journal batch.',
        offset: reader.offset,
      );
    }
    return decoded;
  }

  Uint8List encodeSegment({
    required SessionId sessionId,
    required int startSequence,
    required List<int> previousSegmentFinalDigest,
    required List<JournalBatch> batches,
    required bool seal,
  }) {
    _requireDigest(previousSegmentFinalDigest);
    if (startSequence <= 0 || batches.isEmpty) {
      throw const StoreFormatException(
        StoreFormatErrorCode.sequenceViolation,
        'Segment requires a positive start sequence and at least one batch.',
      );
    }
    final output = BytesBuilder(copy: false)
      ..add(_encodeHeader(
        sessionId,
        startSequence,
        previousSegmentFinalDigest,
      ));
    var expectedSequence = startSequence;
    var previousRecordDigest = Uint8List.fromList(previousSegmentFinalDigest);
    var recordCount = 0;
    for (final batch in batches) {
      if (batch.events.isEmpty ||
          batch.events.first.sequence != expectedSequence) {
        throw const StoreFormatException(
          StoreFormatErrorCode.sequenceViolation,
          'Batch does not begin at the expected sequence.',
        );
      }
      final encoded = _encodeBatch(
        sessionId,
        batch,
        previousRecordDigest,
      );
      output.add(encoded.bytes);
      expectedSequence += batch.events.length;
      recordCount += batch.events.length;
      previousRecordDigest = encoded.finalRecordDigest;
    }
    if (seal) {
      final beforeFooter = output.toBytes();
      output
        ..clear()
        ..add(beforeFooter)
        ..add(_encodeFooter(
          beforeFooter,
          endSequence: expectedSequence - 1,
          recordCount: recordCount,
          finalRecordDigest: previousRecordDigest,
        ));
    }
    return output.takeBytes();
  }

  DecodedJournalSegment decodeSegment(
    Uint8List bytes, {
    bool requireSealed = false,
    List<int>? expectedPreviousSegmentFinalDigest,
  }) =>
      _decodeSegment(
        bytes,
        requireSealed: requireSealed,
        expectedPreviousSegmentFinalDigest: expectedPreviousSegmentFinalDigest,
        recoverPartialTail: false,
      );

  DecodedJournalSegment recoverOpenSegment(
    Uint8List bytes, {
    List<int>? expectedPreviousSegmentFinalDigest,
  }) =>
      _decodeSegment(
        bytes,
        requireSealed: false,
        expectedPreviousSegmentFinalDigest: expectedPreviousSegmentFinalDigest,
        recoverPartialTail: true,
      );

  DecodedJournalSegment _decodeSegment(
    Uint8List bytes, {
    required bool requireSealed,
    required List<int>? expectedPreviousSegmentFinalDigest,
    required bool recoverPartialTail,
  }) {
    if (expectedPreviousSegmentFinalDigest != null) {
      _requireDigest(expectedPreviousSegmentFinalDigest);
    }
    final reader = _Reader(bytes);
    final headerStart = reader.offset;
    reader.expectMagic(agentSegmentHeaderMagic);
    reader.expectU32(agentSegmentHeaderLength);
    reader.expectU16(agentStoreFormatVersion);
    reader.expectU16(agentJournalFrameVersion);
    final sessionText = reader.readAscii(36);
    late final SessionId sessionId;
    try {
      sessionId = SessionId.parse(sessionText);
    } on FormatException {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidSession,
        'Segment header contains an invalid SessionId.',
        offset: headerStart + 12,
      );
    }
    final startSequence = reader.readU64();
    if (startSequence <= 0) {
      throw StoreFormatException(
        StoreFormatErrorCode.sequenceViolation,
        'Segment start sequence must be positive.',
        offset: headerStart + 48,
      );
    }
    final previousSegmentFinalDigest = reader.readBytes(32);
    if (expectedPreviousSegmentFinalDigest != null &&
        !storeBytesEqual(
          previousSegmentFinalDigest,
          expectedPreviousSegmentFinalDigest,
        )) {
      throw StoreFormatException(
        StoreFormatErrorCode.digestMismatch,
        'Segment does not continue the expected previous digest.',
        offset: headerStart + 56,
      );
    }
    reader.expectU32(agentSegmentHeaderLength);
    reader.expectMagic(agentSegmentHeaderTrailingMagic);
    if (reader.offset - headerStart != agentSegmentHeaderLength) {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Segment header length is not 96 bytes.',
      );
    }

    final batches = <DecodedJournalBatch>[];
    var expectedSequence = startSequence;
    var previousRecordDigest = previousSegmentFinalDigest;
    var recordCount = 0;
    var sealed = false;
    int? endSequence;
    Uint8List? segmentDigest;
    var discardedTailLength = 0;

    while (!reader.isDone) {
      final itemStart = reader.offset;
      try {
        final magic = reader.peekMagic();
        if (magic == agentSegmentFooterMagic) {
          if (recordCount == 0) {
            throw StoreFormatException(
              StoreFormatErrorCode.batchViolation,
              'Empty segment cannot be sealed.',
              offset: reader.offset,
            );
          }
          final footerOffset = reader.offset;
          reader.expectMagic(agentSegmentFooterMagic);
          reader.expectU32(agentSegmentFooterLength);
          reader.expectU16(1);
          reader.expectU16(
            0,
            errorCode: StoreFormatErrorCode.invalidReserved,
          );
          endSequence = reader.readU64();
          final footerRecordCount = reader.readU64();
          final footerFinalDigest = reader.readBytes(32);
          final footerPrefixEnd = reader.offset;
          segmentDigest = reader.readBytes(32);
          reader.expectU32(agentSegmentFooterLength);
          reader.expectMagic(agentSegmentFooterTrailingMagic);
          if (!reader.isDone) {
            throw StoreFormatException(
              StoreFormatErrorCode.invalidLength,
              'Bytes follow the sealed segment footer.',
              offset: reader.offset,
            );
          }
          if (endSequence != startSequence + recordCount - 1 ||
              footerRecordCount != recordCount) {
            throw StoreFormatException(
              StoreFormatErrorCode.sequenceViolation,
              'Footer range does not match segment records.',
              offset: footerOffset,
            );
          }
          if (!storeBytesEqual(footerFinalDigest, previousRecordDigest)) {
            throw StoreFormatException(
              StoreFormatErrorCode.digestMismatch,
              'Footer final record digest does not match.',
              offset: footerOffset + 28,
            );
          }
          final expectedSegmentDigest = storeDomainDigest(
            'pigcode-agent-segment-v1',
            <List<int>>[
              bytes.sublist(0, footerOffset),
              bytes.sublist(footerOffset, footerPrefixEnd),
            ],
          );
          if (!storeBytesEqual(segmentDigest, expectedSegmentDigest)) {
            throw StoreFormatException(
              StoreFormatErrorCode.digestMismatch,
              'Segment digest does not match.',
              offset: footerPrefixEnd,
            );
          }
          sealed = true;
          break;
        }
        if (magic != agentBatchMagic) {
          throw StoreFormatException(
            StoreFormatErrorCode.invalidMagic,
            'Expected a batch header or segment footer.',
            offset: reader.offset,
          );
        }
        final decoded = _decodeBatch(
          reader,
          sessionId,
          expectedSequence,
          previousRecordDigest,
        );
        batches.add(decoded);
        expectedSequence += decoded.events.length;
        recordCount += decoded.events.length;
        previousRecordDigest = decoded.recordDigests.last;
      } on StoreFormatException catch (error) {
        if (!recoverPartialTail ||
            error.code != StoreFormatErrorCode.truncated) {
          rethrow;
        }
        reader.offset = itemStart;
        discardedTailLength = bytes.length - itemStart;
        break;
      }
    }
    if (requireSealed && !sealed) {
      throw const StoreFormatException(
        StoreFormatErrorCode.truncated,
        'A sealed segment footer is required.',
      );
    }
    return DecodedJournalSegment(
      sessionId: sessionId,
      startSequence: startSequence,
      previousSegmentFinalDigest: previousSegmentFinalDigest,
      batches: batches,
      sealed: sealed,
      endSequence: endSequence,
      recordCount: recordCount,
      finalRecordDigest: Uint8List.fromList(previousRecordDigest),
      segmentDigest: segmentDigest,
      validLength: reader.offset,
      discardedTailLength: discardedTailLength,
    );
  }

  _EncodedBatch _encodeBatch(
    SessionId sessionId,
    JournalBatch batch,
    Uint8List previousRecordDigest,
  ) {
    if (batch.events.length > limits.maximumBatchEventCount) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Batch event count exceeds the configured limit.',
      );
    }
    final metadata = canonicalJsonBytes(batch.transactionMetadata);
    if (metadata.length > limits.maximumBatchMetadataBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Batch metadata exceeds the configured limit.',
      );
    }
    final bodies = <Uint8List>[];
    for (var index = 0; index < batch.events.length; index++) {
      final event = batch.events[index];
      if (event.sequence != batch.events.first.sequence + index ||
          event.sessionId != sessionId) {
        throw const StoreFormatException(
          StoreFormatErrorCode.sequenceViolation,
          'Batch events must be contiguous and belong to the segment Session.',
        );
      }
      final body = canonicalJsonBytes(event.toJson());
      _requireBodySize(body.length);
      bodies.add(body);
    }
    final batchDigest = _batchDigest(
      sessionId,
      batch.events.first.sequence,
      batch.events.length,
      metadata,
      bodies,
    );
    final batchHeaderLength = agentBatchHeaderFixedLength + metadata.length;
    final output = BytesBuilder(copy: false)
      ..add(ascii.encode(agentBatchMagic))
      ..add(storeU32(batchHeaderLength))
      ..add(storeU32(batch.events.length))
      ..add(storeU64(batch.events.first.sequence))
      ..add(storeU32(metadata.length))
      ..add(metadata)
      ..add(batchDigest)
      ..add(storeU32(batchHeaderLength))
      ..add(ascii.encode(agentBatchTrailingMagic));

    var previous = previousRecordDigest;
    final recordDigests = <Uint8List>[];
    for (var index = 0; index < batch.events.length; index++) {
      final event = batch.events[index];
      final body = bodies[index];
      final recordDigest = _recordDigest(
        sessionId,
        event.sequence,
        batch.events.length,
        index,
        batchDigest,
        previous,
        body,
      );
      final frameLength = agentEventFrameFixedLength + body.length;
      output
        ..add(ascii.encode(agentEventFrameMagic))
        ..add(storeU32(frameLength))
        ..add(storeU64(event.sequence))
        ..add(storeU32(batch.events.length))
        ..add(storeU32(index))
        ..add(batchDigest)
        ..add(previous)
        ..add(storeU32(body.length))
        ..add(body)
        ..add(recordDigest)
        ..add(storeU32(frameLength))
        ..add(ascii.encode(agentEventFrameTrailingMagic));
      recordDigests.add(recordDigest);
      previous = recordDigest;
    }
    final bytes = output.takeBytes();
    if (bytes.length > limits.maximumBatchBytes) {
      throw const StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Encoded batch exceeds the configured byte limit.',
      );
    }
    return _EncodedBatch(
      bytes,
      batchDigest,
      recordDigests,
    );
  }

  DecodedJournalBatch _decodeBatch(
    _Reader reader,
    SessionId sessionId,
    int expectedSequence,
    Uint8List previousRecordDigest,
  ) {
    final start = reader.offset;
    reader.expectMagic(agentBatchMagic);
    final headerLength = reader.readU32();
    if (headerLength < agentBatchHeaderFixedLength ||
        headerLength > limits.maximumBatchBytes) {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Batch header length is outside configured bounds.',
        offset: start + 4,
      );
    }
    final eventCount = reader.readU32();
    final firstSequence = reader.readU64();
    final metadataLength = reader.readU32();
    if (eventCount <= 0 || eventCount > limits.maximumBatchEventCount) {
      throw StoreFormatException(
        StoreFormatErrorCode.batchViolation,
        'Batch event count is invalid.',
        offset: start + 8,
      );
    }
    if (firstSequence != expectedSequence) {
      throw StoreFormatException(
        StoreFormatErrorCode.sequenceViolation,
        'Batch first sequence does not match the segment chain.',
        offset: start + 12,
      );
    }
    if (metadataLength > limits.maximumBatchMetadataBytes ||
        headerLength != agentBatchHeaderFixedLength + metadataLength) {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Batch metadata length does not match its header.',
        offset: start + 20,
      );
    }
    final metadataBytes = reader.readBytes(metadataLength);
    final transactionMetadata = _decodeCanonicalObject(
      metadataBytes,
      offset: start + 24,
    );
    final storedBatchDigest = reader.readBytes(32);
    reader.expectU32(headerLength);
    reader.expectMagic(agentBatchTrailingMagic);

    final events = <AgentEvent>[];
    final bodies = <Uint8List>[];
    final recordDigests = <Uint8List>[];
    var previous = previousRecordDigest;
    for (var index = 0; index < eventCount; index++) {
      final frameStart = reader.offset;
      reader.expectMagic(agentEventFrameMagic);
      final frameLength = reader.readU32();
      if (frameLength < agentEventFrameFixedLength ||
          frameLength > limits.maximumBatchBytes) {
        throw StoreFormatException(
          StoreFormatErrorCode.invalidLength,
          'Event frame length is outside configured bounds.',
          offset: frameStart + 4,
        );
      }
      final sequence = reader.readU64();
      final frameEventCount = reader.readU32();
      final batchIndex = reader.readU32();
      final frameBatchDigest = reader.readBytes(32);
      final framePreviousDigest = reader.readBytes(32);
      final bodyLength = reader.readU32();
      _requireBodySize(bodyLength, offset: reader.offset - 4);
      if (frameLength != agentEventFrameFixedLength + bodyLength) {
        throw StoreFormatException(
          StoreFormatErrorCode.invalidLength,
          'Event body length does not match frame length.',
          offset: frameStart + 4,
        );
      }
      final body = reader.readBytes(bodyLength);
      final recordDigest = reader.readBytes(32);
      reader.expectU32(frameLength);
      reader.expectMagic(agentEventFrameTrailingMagic);
      if (reader.offset - frameStart != frameLength) {
        throw StoreFormatException(
          StoreFormatErrorCode.invalidLength,
          'Event frame consumed a different byte length.',
          offset: frameStart,
        );
      }
      if (sequence != firstSequence + index ||
          frameEventCount != eventCount ||
          batchIndex != index ||
          !storeBytesEqual(frameBatchDigest, storedBatchDigest)) {
        throw StoreFormatException(
          StoreFormatErrorCode.batchViolation,
          'Event frame does not match its batch header.',
          offset: frameStart,
          sequence: sequence,
        );
      }
      if (!storeBytesEqual(framePreviousDigest, previous)) {
        throw StoreFormatException(
          StoreFormatErrorCode.digestMismatch,
          'Previous record digest chain does not match.',
          offset: frameStart + 56,
          sequence: sequence,
        );
      }
      final expectedRecordDigest = _recordDigest(
        sessionId,
        sequence,
        eventCount,
        index,
        storedBatchDigest,
        previous,
        body,
      );
      if (!storeBytesEqual(recordDigest, expectedRecordDigest)) {
        throw StoreFormatException(
          StoreFormatErrorCode.digestMismatch,
          'Event record digest does not match.',
          offset: frameStart + frameLength - 40,
          sequence: sequence,
        );
      }
      final event = _decodeCanonicalEvent(body, frameStart);
      if (event.sessionId != sessionId || event.sequence != sequence) {
        throw StoreFormatException(
          StoreFormatErrorCode.sequenceViolation,
          'Canonical event envelope does not match its frame.',
          offset: frameStart,
          sequence: sequence,
        );
      }
      events.add(event);
      bodies.add(body);
      recordDigests.add(recordDigest);
      previous = recordDigest;
    }
    final expectedBatchDigest = _batchDigest(
      sessionId,
      firstSequence,
      eventCount,
      metadataBytes,
      bodies,
    );
    if (!storeBytesEqual(storedBatchDigest, expectedBatchDigest)) {
      throw StoreFormatException(
        StoreFormatErrorCode.digestMismatch,
        'Batch digest does not match metadata and event bodies.',
        offset: start,
      );
    }
    if (reader.offset - start > limits.maximumBatchBytes) {
      throw StoreFormatException(
        StoreFormatErrorCode.resourceLimit,
        'Decoded batch exceeds the configured byte limit.',
        offset: start,
      );
    }
    return DecodedJournalBatch(
      transactionMetadata: transactionMetadata,
      events: events,
      batchDigest: storedBatchDigest,
      recordDigests: recordDigests,
      offset: start,
      length: reader.offset - start,
    );
  }

  Uint8List _encodeHeader(
    SessionId sessionId,
    int startSequence,
    List<int> previousSegmentFinalDigest,
  ) {
    final bytes = BytesBuilder(copy: false)
      ..add(ascii.encode(agentSegmentHeaderMagic))
      ..add(storeU32(agentSegmentHeaderLength))
      ..add(storeU16(agentStoreFormatVersion))
      ..add(storeU16(agentJournalFrameVersion))
      ..add(ascii.encode(sessionId.value))
      ..add(storeU64(startSequence))
      ..add(previousSegmentFinalDigest)
      ..add(storeU32(agentSegmentHeaderLength))
      ..add(ascii.encode(agentSegmentHeaderTrailingMagic));
    return bytes.takeBytes();
  }

  Uint8List _encodeFooter(
    Uint8List bytesBeforeFooter, {
    required int endSequence,
    required int recordCount,
    required Uint8List finalRecordDigest,
  }) {
    final prefix = BytesBuilder(copy: false)
      ..add(ascii.encode(agentSegmentFooterMagic))
      ..add(storeU32(agentSegmentFooterLength))
      ..add(storeU16(1))
      ..add(storeU16(0))
      ..add(storeU64(endSequence))
      ..add(storeU64(recordCount))
      ..add(finalRecordDigest);
    final prefixBytes = prefix.takeBytes();
    final segmentDigest = storeDomainDigest(
      'pigcode-agent-segment-v1',
      <List<int>>[bytesBeforeFooter, prefixBytes],
    );
    return (BytesBuilder(copy: false)
          ..add(prefixBytes)
          ..add(segmentDigest)
          ..add(storeU32(agentSegmentFooterLength))
          ..add(ascii.encode(agentSegmentFooterTrailingMagic)))
        .takeBytes();
  }

  Uint8List _batchDigest(
    SessionId sessionId,
    int firstSequence,
    int eventCount,
    List<int> metadata,
    List<Uint8List> bodies,
  ) =>
      storeDomainDigest(
        'pigcode-agent-batch-v1',
        <List<int>>[
          ascii.encode(sessionId.value),
          storeU64(firstSequence),
          storeU32(eventCount),
          storeU32(metadata.length),
          metadata,
          for (final body in bodies) ...<List<int>>[
            storeU32(body.length),
            body,
          ],
        ],
      );

  Uint8List _recordDigest(
    SessionId sessionId,
    int sequence,
    int eventCount,
    int batchIndex,
    List<int> batchDigest,
    List<int> previousRecordDigest,
    List<int> body,
  ) =>
      storeDomainDigest(
        'pigcode-agent-event-v1',
        <List<int>>[
          ascii.encode(sessionId.value),
          storeU64(sequence),
          storeU32(eventCount),
          storeU32(batchIndex),
          batchDigest,
          previousRecordDigest,
          body,
        ],
      );

  Map<String, Object?> _decodeCanonicalObject(
    Uint8List bytes, {
    required int offset,
  }) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw StoreFormatException(
        StoreFormatErrorCode.nonCanonicalJson,
        'Transaction metadata is not valid UTF-8 JSON.',
        offset: offset,
      );
    }
    if (decoded is! Map<String, Object?> ||
        !storeBytesEqual(canonicalJsonBytes(decoded), bytes)) {
      throw StoreFormatException(
        StoreFormatErrorCode.nonCanonicalJson,
        'Transaction metadata is not canonical JSON.',
        offset: offset,
      );
    }
    return DomainJson.freeze(decoded)! as Map<String, Object?>;
  }

  AgentEvent _decodeCanonicalEvent(Uint8List bytes, int offset) {
    try {
      final encoded = utf8.decode(bytes);
      final event = AgentEventCodec.instance.decode(encoded);
      if (!storeBytesEqual(canonicalJsonBytes(event.toJson()), bytes)) {
        throw const FormatException('Event JSON is not canonical.');
      }
      return event;
    } on Object {
      throw StoreFormatException(
        StoreFormatErrorCode.nonCanonicalJson,
        'Event body is not a canonical AgentEvent.',
        offset: offset,
      );
    }
  }

  void _requireBodySize(int length, {int? offset}) {
    if (length > limits.maximumEventBodyBytes ||
        length > StoreLimits.hardMaximumEventBodyBytes) {
      throw StoreFormatException(
        StoreFormatErrorCode.bodyTooLarge,
        'Event body exceeds the configured limit.',
        offset: offset,
      );
    }
  }

  void _requireDigest(List<int> value) {
    if (value.length != 32) {
      throw const StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Digest must contain exactly 32 bytes.',
      );
    }
  }
}

final class _EncodedBatch {
  const _EncodedBatch(this.bytes, this.batchDigest, this.recordDigests);

  final Uint8List bytes;
  final Uint8List batchDigest;
  final List<Uint8List> recordDigests;

  Uint8List get finalRecordDigest => recordDigests.last;
}

final class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  bool get isDone => offset == bytes.length;

  String peekMagic() {
    _require(4);
    return ascii.decode(bytes.sublist(offset, offset + 4));
  }

  void expectMagic(String expected) {
    final start = offset;
    final actual = readAscii(4);
    if (actual != expected) {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidMagic,
        'Expected $expected magic.',
        offset: start,
      );
    }
  }

  String readAscii(int length) {
    final value = readBytes(length);
    try {
      return ascii.decode(value);
    } on FormatException {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidMagic,
        'Expected canonical ASCII bytes.',
        offset: offset - length,
      );
    }
  }

  int readU16() {
    _require(2);
    final value = ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.big);
    offset += 2;
    return value;
  }

  int readU32() {
    _require(4);
    final value = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);
    offset += 4;
    return value;
  }

  int readU64() {
    _require(8);
    final value = ByteData.sublistView(bytes, offset, offset + 8)
        .getUint64(0, Endian.big);
    offset += 8;
    return value;
  }

  void expectU16(
    int expected, {
    StoreFormatErrorCode errorCode = StoreFormatErrorCode.unsupportedVersion,
  }) {
    final start = offset;
    final actual = readU16();
    if (actual != expected) {
      throw StoreFormatException(
        errorCode,
        'Expected u16 value $expected.',
        offset: start,
      );
    }
  }

  void expectU32(int expected) {
    final start = offset;
    final actual = readU32();
    if (actual != expected) {
      throw StoreFormatException(
        StoreFormatErrorCode.invalidLength,
        'Expected u32 value $expected.',
        offset: start,
      );
    }
  }

  Uint8List readBytes(int length) {
    _require(length);
    final value = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return value;
  }

  void _require(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw StoreFormatException(
        StoreFormatErrorCode.truncated,
        'Journal bytes end inside a framed value.',
        offset: offset,
      );
    }
  }
}
