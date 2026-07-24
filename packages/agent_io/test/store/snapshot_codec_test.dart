import 'dart:convert';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  const codec = StoreSnapshotCodec();
  final head = AgentStoreHead.compose(
    sequence: 7,
    journalHeadDigest: ''.padLeft(64, '1'),
    identityRegistryRootDigest: ''.padLeft(64, '2'),
    commandRegistryRootDigest: ''.padLeft(64, '3'),
    generation: 4,
    historyFloorSequence: 0,
  );
  final snapshot = _snapshot(head);

  test('snapshot envelope round-trips every fixed field canonically', () {
    final bytes = codec.encode(snapshot);
    final decoded = codec.decode(bytes);

    expect(decoded.toJson(), snapshot.toJson());
    expect(bytes, canonicalJsonBytes(snapshot.toJson()));
    codec.validateHeadBinding(decoded, head);
  });

  test('projection digest, version, and typed identity fail closed', () {
    expect(
      () => codec.encode(AgentStoreSnapshot(
        sessionId: snapshot.sessionId,
        snapshotId: snapshot.snapshotId,
        sequence: snapshot.sequence,
        journalHeadDigest: snapshot.journalHeadDigest,
        historyFloorSequence: snapshot.historyFloorSequence,
        identityRegistryRootDigest: snapshot.identityRegistryRootDigest,
        commandRegistryRootDigest: snapshot.commandRegistryRootDigest,
        canonicalProjection: snapshot.canonicalProjection,
        projectionDigest: ''.padLeft(64, '0'),
      )),
      throwsA(isA<StoreFormatException>()),
    );

    final object = jsonDecode(
      utf8.decode(codec.encode(snapshot)),
    )! as Map<String, Object?>;
    object['snapshotFormatVersion'] = 2;
    expect(
      () => codec.decode(canonicalJsonBytes(object)),
      throwsA(
        isA<StoreFormatException>().having(
          (error) => error.code,
          'code',
          StoreFormatErrorCode.unsupportedVersion,
        ),
      ),
    );
    object['snapshotFormatVersion'] = 1;
    object['sessionId'] = 'ses_../../escape';
    expect(
      () => codec.decode(canonicalJsonBytes(object)),
      throwsA(isA<StoreFormatException>()),
    );
  });

  test('snapshot cannot bind a different sequence or journal head', () {
    final other = AgentStoreHead.compose(
      sequence: head.sequence + 1,
      journalHeadDigest: head.journalHeadDigest,
      identityRegistryRootDigest: head.identityRegistryRootDigest,
      commandRegistryRootDigest: head.commandRegistryRootDigest,
      generation: head.generation,
      historyFloorSequence: head.historyFloorSequence,
    );

    expect(
      () => codec.validateHeadBinding(snapshot, other),
      throwsA(isA<StoreFormatException>()),
    );
  });
}

AgentStoreSnapshot _snapshot(AgentStoreHead head) {
  final projection = <String, Object?>{
    'journalSequence': head.sequence,
    'state': 'inProgress',
  };
  return AgentStoreSnapshot(
    sessionId: SessionId.parse('ses_00000000000000000000000000000000'),
    snapshotId: SnapshotId.parse('snp_00000000000000000000000000000000'),
    sequence: head.sequence,
    journalHeadDigest: head.journalHeadDigest,
    historyFloorSequence: head.historyFloorSequence,
    identityRegistryRootDigest: head.identityRegistryRootDigest,
    commandRegistryRootDigest: head.commandRegistryRootDigest,
    canonicalProjection: projection,
    projectionDigest: canonicalJsonSha256(projection),
  );
}
