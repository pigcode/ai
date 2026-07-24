import 'store_format.dart';

enum StoreCorruptionCategory {
  truncatedHeader,
  sealedSegmentInvalid,
  digestMismatch,
  gapOrOverlap,
  sessionMismatch,
  futureVersion,
  invalidFrame,
  resourceLimit,
}

final class StoreCorruptionException implements Exception {
  const StoreCorruptionException({
    required this.category,
    this.sequence,
    this.offset,
    this.digest,
  });

  final StoreCorruptionCategory category;
  final int? sequence;
  final int? offset;
  final String? digest;

  factory StoreCorruptionException.fromFormat(
    StoreFormatException error, {
    required bool sealed,
  }) =>
      StoreCorruptionException(
        category: switch (error.code) {
          StoreFormatErrorCode.truncated => sealed
              ? StoreCorruptionCategory.sealedSegmentInvalid
              : StoreCorruptionCategory.truncatedHeader,
          StoreFormatErrorCode.digestMismatch =>
            StoreCorruptionCategory.digestMismatch,
          StoreFormatErrorCode.sequenceViolation ||
          StoreFormatErrorCode.batchViolation =>
            StoreCorruptionCategory.gapOrOverlap,
          StoreFormatErrorCode.invalidSession =>
            StoreCorruptionCategory.sessionMismatch,
          StoreFormatErrorCode.unsupportedVersion =>
            StoreCorruptionCategory.futureVersion,
          StoreFormatErrorCode.bodyTooLarge ||
          StoreFormatErrorCode.resourceLimit =>
            StoreCorruptionCategory.resourceLimit,
          StoreFormatErrorCode.invalidMagic ||
          StoreFormatErrorCode.invalidLength ||
          StoreFormatErrorCode.invalidReserved ||
          StoreFormatErrorCode.registryViolation ||
          StoreFormatErrorCode.nonCanonicalJson =>
            StoreCorruptionCategory.invalidFrame,
        },
        sequence: error.sequence,
        offset: error.offset,
      );

  @override
  String toString() {
    final fields = <String>[
      'category=${category.name}',
      if (sequence != null) 'sequence=$sequence',
      if (offset != null) 'offset=$offset',
      if (digest != null) 'digest=$digest',
    ];
    return 'StoreCorruptionException(${fields.join(', ')})';
  }
}
