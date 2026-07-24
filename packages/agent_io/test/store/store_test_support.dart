import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final testSessionId = SessionId.parse('ses_00000000000000000000000000000000');

AgentEvent testStoreEvent(int sequence) => AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toString().padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: testSessionId,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24, 0, 0, sequence),
      type: AgentEventType.sessionCreated,
      causationId: CommandId.parse('cmd_00000000000000000000000000000000'),
      payload: <String, Object?>{
        'definitionRef': 'agent:test',
        'ordinal': sequence,
      },
      metadata: AgentEventMetadata.empty(),
    );

List<JournalBatch> testJournalBatches() => <JournalBatch>[
      JournalBatch(
        transactionMetadata: <String, Object?>{
          'newIdAllocations': <Object?>[
            testStoreEvent(1).eventId.value,
            testStoreEvent(2).eventId.value,
          ],
          'schemaVersion': 1,
        },
        events: <AgentEvent>[testStoreEvent(1), testStoreEvent(2)],
      ),
    ];

Uint8List testSealedSegment() => const JournalFrameCodec().encodeSegment(
      sessionId: testSessionId,
      startSequence: 1,
      previousSegmentFinalDigest: Uint8List(32),
      batches: testJournalBatches(),
      seal: true,
    );
