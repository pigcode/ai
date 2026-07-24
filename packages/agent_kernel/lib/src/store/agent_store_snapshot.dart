import '../id/opaque_id.dart';
import '../event/agent_event_metadata.dart';
import '../json/domain_json.dart';

final class AgentStoreSnapshot {
  AgentStoreSnapshot({
    required this.sessionId,
    required this.snapshotId,
    this.snapshotFormatVersion = 1,
    this.reducerSchemaVersion = 1,
    required this.sequence,
    required this.journalHeadDigest,
    required this.historyFloorSequence,
    required this.identityRegistryRootDigest,
    required this.commandRegistryRootDigest,
    required Map<String, Object?> canonicalProjection,
    required this.projectionDigest,
  }) : canonicalProjection = _freezeSnapshotProjection(canonicalProjection);

  final SessionId sessionId;
  final SnapshotId snapshotId;
  final int snapshotFormatVersion;
  final int reducerSchemaVersion;
  final int sequence;
  final String journalHeadDigest;
  final int historyFloorSequence;
  final String identityRegistryRootDigest;
  final String commandRegistryRootDigest;
  final Map<String, Object?> canonicalProjection;
  final String projectionDigest;

  Map<String, Object?> toJson() => <String, Object?>{
        'sessionId': sessionId.value,
        'snapshotId': snapshotId.value,
        'snapshotFormatVersion': snapshotFormatVersion,
        'reducerSchemaVersion': reducerSchemaVersion,
        'sequence': sequence,
        'journalHeadDigest': journalHeadDigest,
        'historyFloorSequence': historyFloorSequence,
        'identityRegistryRootDigest': identityRegistryRootDigest,
        'commandRegistryRootDigest': commandRegistryRootDigest,
        'canonicalProjection': canonicalProjection,
        'projectionDigest': projectionDigest,
      };
}

Map<String, Object?> _freezeSnapshotProjection(
  Map<String, Object?> value,
) {
  final frozen = DomainJson.freeze(value)! as Map<String, Object?>;
  validateSafePersistedJson(frozen);
  return frozen;
}
