import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';
import 'store_format.dart';

final class StoreSnapshotCodec {
  const StoreSnapshotCodec();

  Uint8List encode(AgentStoreSnapshot snapshot) {
    validate(snapshot);
    return canonicalJsonBytes(snapshot.toJson());
  }

  AgentStoreSnapshot decode(Uint8List bytes) {
    final value = decodeCanonicalRegistryObject(bytes);
    requireExactRegistryKeys(value, const <String>{
      'canonicalProjection',
      'commandRegistryRootDigest',
      'historyFloorSequence',
      'identityRegistryRootDigest',
      'journalHeadDigest',
      'projectionDigest',
      'reducerSchemaVersion',
      'sequence',
      'sessionId',
      'snapshotFormatVersion',
      'snapshotId',
    });
    if (requireRegistryInt(value, 'snapshotFormatVersion') !=
        agentSnapshotFormatVersion) {
      throw const StoreFormatException(
        StoreFormatErrorCode.unsupportedVersion,
        'Unsupported snapshot format version.',
      );
    }
    final projection = value['canonicalProjection'];
    if (projection is! Map<String, Object?>) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Snapshot projection must be an object.',
      );
    }
    late final AgentStoreSnapshot snapshot;
    try {
      snapshot = AgentStoreSnapshot(
        sessionId: SessionId.parse(requireRegistryString(value, 'sessionId')),
        snapshotId:
            SnapshotId.parse(requireRegistryString(value, 'snapshotId')),
        snapshotFormatVersion:
            requireRegistryInt(value, 'snapshotFormatVersion'),
        reducerSchemaVersion: requireRegistryInt(value, 'reducerSchemaVersion'),
        sequence: requireRegistryInt(value, 'sequence'),
        journalHeadDigest: requireRegistryDigest(value, 'journalHeadDigest'),
        historyFloorSequence: requireRegistryInt(value, 'historyFloorSequence'),
        identityRegistryRootDigest:
            requireRegistryDigest(value, 'identityRegistryRootDigest'),
        commandRegistryRootDigest:
            requireRegistryDigest(value, 'commandRegistryRootDigest'),
        canonicalProjection: projection,
        projectionDigest: requireRegistryDigest(value, 'projectionDigest'),
      );
    } on FormatException {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Snapshot contains an invalid typed identifier.',
      );
    }
    validate(snapshot);
    return snapshot;
  }

  void validate(AgentStoreSnapshot snapshot) {
    if (snapshot.snapshotFormatVersion != agentSnapshotFormatVersion ||
        snapshot.reducerSchemaVersion != 1 ||
        snapshot.sequence <= 0 ||
        snapshot.historyFloorSequence < 0 ||
        snapshot.historyFloorSequence > snapshot.sequence ||
        canonicalJsonSha256(snapshot.canonicalProjection) !=
            snapshot.projectionDigest) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Snapshot envelope or projection digest is invalid.',
      );
    }
    for (final digest in <String>[
      snapshot.journalHeadDigest,
      snapshot.identityRegistryRootDigest,
      snapshot.commandRegistryRootDigest,
      snapshot.projectionDigest,
    ]) {
      if (!isStoreDigest(digest)) {
        throw const StoreFormatException(
          StoreFormatErrorCode.registryViolation,
          'Snapshot contains an invalid digest.',
        );
      }
    }
  }

  void validateHeadBinding(
    AgentStoreSnapshot snapshot,
    AgentStoreHead head,
  ) {
    validate(snapshot);
    if (snapshot.sequence != head.sequence ||
        snapshot.journalHeadDigest != head.journalHeadDigest ||
        snapshot.historyFloorSequence != head.historyFloorSequence ||
        snapshot.identityRegistryRootDigest !=
            head.identityRegistryRootDigest ||
        snapshot.commandRegistryRootDigest != head.commandRegistryRootDigest) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Snapshot does not bind the expected Session head.',
      );
    }
  }
}
