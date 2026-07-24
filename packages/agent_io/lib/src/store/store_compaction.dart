import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';

final class StorePrefixCommitment {
  const StorePrefixCommitment({
    required this.throughSequence,
    required this.finalRecordDigest,
  });

  static const empty = StorePrefixCommitment(
    throughSequence: 0,
    finalRecordDigest: agentStoreEmptyDigest,
  );

  final int throughSequence;
  final String finalRecordDigest;

  Map<String, Object?> toJson() => <String, Object?>{
        'finalRecordDigest': finalRecordDigest,
        'throughSequence': throughSequence,
      };

  static StorePrefixCommitment fromJson(Map<String, Object?> value) {
    requireExactRegistryKeys(
      value,
      const <String>{'finalRecordDigest', 'throughSequence'},
    );
    final throughSequence = requireRegistryInt(value, 'throughSequence');
    final digest = requireRegistryDigest(value, 'finalRecordDigest');
    if ((throughSequence == 0 && digest != agentStoreEmptyDigest) ||
        (throughSequence > 0 && digest == agentStoreEmptyDigest)) {
      throw const AgentStoreException(
        AgentStoreErrorCode.corruption,
        'Prefix commitment range and digest are inconsistent.',
      );
    }
    return StorePrefixCommitment(
      throughSequence: throughSequence,
      finalRecordDigest: digest,
    );
  }
}

bool snapshotProjectionIsSafeToPrune(
  Map<String, Object?> canonicalProjection,
) {
  final AgentSessionProjection projection;
  try {
    projection = AgentSessionProjection.fromJson(canonicalProjection);
  } on FormatException {
    return false;
  }
  return projection.currentRunId == null &&
      projection.workItems.isEmpty &&
      projection.approvals.isEmpty &&
      projection.deferredOperations.isEmpty &&
      projection.resources.isEmpty;
}
