import 'dart:math';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('every snapshot cut plus suffix equals full legal replay', () {
    const reducer = AgentReducer();

    for (var seed = 0; seed < 128; seed++) {
      final random = Random(seed);
      final events = <AgentEvent>[
        _event(
          1,
          AgentEventType.sessionCreated,
          payload: const <String, Object?>{
            'definitionRef': 'agent:test',
          },
        ),
      ];
      for (var sequence = 2; sequence <= 24; sequence++) {
        final type = _sessionTypes[random.nextInt(_sessionTypes.length)];
        events.add(_event(
          sequence,
          type,
          payload: _payload(type, random),
        ));
      }
      final full = reducer.replay(events);
      final fullBytes = canonicalJsonEncode(full.toJson());
      final restored = reducer.restoreSnapshot(
        AgentStoreSnapshot(
          sessionId: full.id,
          snapshotId: SnapshotId.parse(
            'snp_${seed.toString().padLeft(32, '0')}',
          ),
          sequence: full.journalSequence,
          journalHeadDigest: ''.padLeft(64, '1'),
          historyFloorSequence: 0,
          identityRegistryRootDigest: ''.padLeft(64, '2'),
          commandRegistryRootDigest: ''.padLeft(64, '3'),
          canonicalProjection: full.toJson(),
          projectionDigest: canonicalJsonSha256(full.toJson()),
        ),
      );
      expect(canonicalJsonEncode(restored.toJson()), fullBytes);

      for (var cut = 1; cut <= events.length; cut++) {
        var resumed = reducer.replay(events.take(cut));
        for (final event in events.skip(cut)) {
          resumed = reducer.apply(resumed, event);
        }
        expect(
          canonicalJsonEncode(resumed.toJson()),
          fullBytes,
          reason: 'seed=$seed cut=$cut',
        );
      }
    }
  });

  test('snapshot projection rejects unknown fields and dangling references',
      () {
    const reducer = AgentReducer();
    final projection = reducer.replay(<AgentEvent>[
      _event(
        1,
        AgentEventType.sessionCreated,
        payload: const <String, Object?>{
          'definitionRef': 'agent:test',
        },
      ),
    ]).toJson();
    projection['unknown'] = true;
    final snapshot = AgentStoreSnapshot(
      sessionId: SessionId.parse(
        'ses_00000000000000000000000000000000',
      ),
      snapshotId: SnapshotId.parse(
        'snp_00000000000000000000000000000000',
      ),
      sequence: 1,
      journalHeadDigest: ''.padLeft(64, '1'),
      historyFloorSequence: 0,
      identityRegistryRootDigest: ''.padLeft(64, '2'),
      commandRegistryRootDigest: ''.padLeft(64, '3'),
      canonicalProjection: projection,
      projectionDigest: canonicalJsonSha256(projection),
    );

    expect(
      () => reducer.restoreSnapshot(snapshot),
      throwsA(
        isA<ReplayViolation>().having(
          (error) => error.code,
          'code',
          'invalid_snapshot_projection',
        ),
      ),
    );
  });
}

const _sessionTypes = <AgentEventType>[
  AgentEventType.sessionCapabilitiesPinned,
  AgentEventType.sessionAttachmentChanged,
  AgentEventType.sessionRuntimeLivenessChanged,
  AgentEventType.sessionResumeStateStored,
];

Map<String, Object?> _payload(AgentEventType type, Random random) =>
    switch (type) {
      AgentEventType.sessionCapabilitiesPinned => <String, Object?>{
          'capabilitySnapshot': <String, Object?>{
            'run': random.nextBool(),
          },
        },
      AgentEventType.sessionAttachmentChanged => <String, Object?>{
          'attached': random.nextBool(),
        },
      AgentEventType.sessionRuntimeLivenessChanged => <String, Object?>{
          'state': <String>['alive', 'stopped', 'unknown'][random.nextInt(3)],
        },
      AgentEventType.sessionResumeStateStored => const <String, Object?>{
          'stored': true,
        },
      _ => const <String, Object?>{},
    };

AgentEvent _event(
  int sequence,
  AgentEventType type, {
  required Map<String, Object?> payload,
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toString().padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: type,
      causationId: CommandId.parse('cmd_00000000000000000000000000000000'),
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );
