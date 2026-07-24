import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'store_test_support.dart';

void main() {
  const codec = JournalFrameCodec();
  const recovery = StoreRecovery();

  test('segment gap and overlap are rejected independent of directory order',
      () {
    final first = _segment(
      codec,
      testSessionId,
      sequence: 1,
      previousDigest: Uint8List(32),
    );
    final firstDigest =
        codec.decodeSegment(first, requireSealed: true).finalRecordDigest;
    final gap = _segment(
      codec,
      testSessionId,
      sequence: 3,
      previousDigest: firstDigest,
    );
    final overlap = _segment(
      codec,
      testSessionId,
      sequence: 1,
      previousDigest: firstDigest,
    );

    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[first, gap],
        allowFinalOpenTail: false,
      ),
      throwsCategory(StoreCorruptionCategory.gapOrOverlap),
    );
    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[first, overlap],
        allowFinalOpenTail: false,
      ),
      throwsCategory(StoreCorruptionCategory.gapOrOverlap),
    );
  });

  test('wrong previous digest and wrong Session fail closed', () {
    final first = _segment(
      codec,
      testSessionId,
      sequence: 1,
      previousDigest: Uint8List(32),
    );
    final firstDigest =
        codec.decodeSegment(first, requireSealed: true).finalRecordDigest;
    final wrongPrevious = _segment(
      codec,
      testSessionId,
      sequence: 2,
      previousDigest: Uint8List(32),
    );
    final otherSession =
        SessionId.parse('ses_10000000000000000000000000000000');
    final wrongSession = _segment(
      codec,
      otherSession,
      sequence: 2,
      previousDigest: firstDigest,
    );

    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[first, wrongPrevious],
        allowFinalOpenTail: false,
      ),
      throwsCategory(StoreCorruptionCategory.digestMismatch),
    );
    expect(
      () => recovery.recoverJournalChain(
        sessionId: testSessionId,
        segments: <Uint8List>[first, wrongSession],
        allowFinalOpenTail: false,
      ),
      throwsCategory(StoreCorruptionCategory.sessionMismatch),
    );
  });
}

Uint8List _segment(
  JournalFrameCodec codec,
  SessionId sessionId, {
  required int sequence,
  required Uint8List previousDigest,
}) =>
    codec.encodeSegment(
      sessionId: sessionId,
      startSequence: sequence,
      previousSegmentFinalDigest: previousDigest,
      batches: <JournalBatch>[
        JournalBatch(
          transactionMetadata: const <String, Object?>{
            'schemaVersion': 1,
          },
          events: <AgentEvent>[
            AgentEvent(
              eventId: EventId.parse(
                'evt_${sequence.toString().padLeft(32, '0')}',
              ),
              schemaVersion: 1,
              sessionId: sessionId,
              sequence: sequence,
              recordedAt: DateTime.utc(2026, 7, 24),
              type: sequence == 1
                  ? AgentEventType.sessionCreated
                  : AgentEventType.sessionCapabilitiesPinned,
              causationId: CommandId.parse(
                'cmd_00000000000000000000000000000000',
              ),
              payload: const <String, Object?>{},
              metadata: AgentEventMetadata.empty(),
            ),
          ],
        ),
      ],
      seal: true,
    );

Matcher throwsCategory(StoreCorruptionCategory category) => throwsA(
      isA<StoreCorruptionException>().having(
        (error) => error.category,
        'category',
        category,
      ),
    );
