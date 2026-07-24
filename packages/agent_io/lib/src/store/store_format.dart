const agentStoreFormatVersion = 1;
const agentJournalFrameVersion = 1;
const agentSnapshotFormatVersion = 1;
const agentManifestFormatVersion = 1;

const agentSegmentHeaderLength = 96;
const agentSegmentFooterLength = 100;
const agentBatchHeaderFixedLength = 64;
const agentEventFrameFixedLength = 132;

const agentSegmentHeaderMagic = 'PIGJ';
const agentSegmentHeaderTrailingMagic = 'JGIP';
const agentBatchMagic = 'BAT1';
const agentBatchTrailingMagic = '1TAB';
const agentEventFrameMagic = 'EVT1';
const agentEventFrameTrailingMagic = '1TVE';
const agentSegmentFooterMagic = 'PIGF';
const agentSegmentFooterTrailingMagic = 'FGIP';

enum StoreFormatErrorCode {
  truncated,
  invalidMagic,
  invalidLength,
  unsupportedVersion,
  invalidReserved,
  invalidSession,
  sequenceViolation,
  digestMismatch,
  bodyTooLarge,
  batchViolation,
  registryViolation,
  nonCanonicalJson,
  resourceLimit,
}

final class StoreFormatException implements Exception {
  const StoreFormatException(
    this.code,
    this.message, {
    this.offset,
    this.sequence,
  });

  final StoreFormatErrorCode code;
  final String message;
  final int? offset;
  final int? sequence;

  @override
  String toString() => 'StoreFormatException(${code.name}): $message';
}
