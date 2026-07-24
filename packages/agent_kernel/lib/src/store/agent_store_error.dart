enum AgentStoreErrorCode {
  sessionNotFound,
  rootSequenceConflict,
  rootStateDigestConflict,
  sequenceConflict,
  stateDigestConflict,
  commandContentMismatch,
  duplicateId,
  invalidTransaction,
  cursorCompacted,
  durabilityUnsupported,
  coordinationRequired,
  storeBusy,
  corruption,
  ioFailure,
  snapshotConflict,
  resourceLimit,
  insecureRoot,
}

final class AgentStoreException implements Exception {
  const AgentStoreException(this.code, this.message);

  final AgentStoreErrorCode code;
  final String message;

  @override
  String toString() => 'AgentStoreException(${code.name}): $message';
}
