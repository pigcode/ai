import 'dart:math';

import 'opaque_id.dart';

const _opaqueIdByteLength = 20;
const _crockfordAlphabet = '0123456789abcdefghjkmnpqrstvwxyz';

typedef OpaqueIdByteSource = List<int> Function(int length);

enum OpaqueIdGenerationFailure {
  sourceUnavailable,
  invalidSourceBytes,
  collisionLimitExceeded,
}

final class OpaqueIdGenerationException implements Exception {
  const OpaqueIdGenerationException({
    required this.kind,
    required this.attempts,
    required this.message,
    this.cause,
  });

  final OpaqueIdGenerationFailure kind;
  final int attempts;
  final String message;
  final Object? cause;

  @override
  String toString() => 'OpaqueIdGenerationException($kind): $message';
}

/// Generates opaque IDs from a CSPRNG or an explicitly injected test source.
final class OpaqueIdGenerator {
  OpaqueIdGenerator({
    OpaqueIdByteSource? byteSource,
    this.maxAttempts = 8,
  }) : _byteSource = byteSource ?? _secureBytes {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(
          maxAttempts, 'maxAttempts', 'Must be positive.');
    }
  }

  final OpaqueIdByteSource _byteSource;
  final int maxAttempts;

  SessionId generateSessionId({
    bool Function(SessionId value)? isAllocated,
  }) =>
      _generate('ses', SessionId.parse, isAllocated);

  RunId generateRunId({bool Function(RunId value)? isAllocated}) =>
      _generate('run', RunId.parse, isAllocated);

  EventId generateEventId({bool Function(EventId value)? isAllocated}) =>
      _generate('evt', EventId.parse, isAllocated);

  CommandId generateCommandId({
    bool Function(CommandId value)? isAllocated,
  }) =>
      _generate('cmd', CommandId.parse, isAllocated);

  WorkItemId generateWorkItemId({
    bool Function(WorkItemId value)? isAllocated,
  }) =>
      _generate('wrk', WorkItemId.parse, isAllocated);

  AttemptId generateAttemptId({
    bool Function(AttemptId value)? isAllocated,
  }) =>
      _generate('att', AttemptId.parse, isAllocated);

  ApprovalId generateApprovalId({
    bool Function(ApprovalId value)? isAllocated,
  }) =>
      _generate('apr', ApprovalId.parse, isAllocated);

  DeferredOperationId generateDeferredOperationId({
    bool Function(DeferredOperationId value)? isAllocated,
  }) =>
      _generate('dop', DeferredOperationId.parse, isAllocated);

  RuntimeResourceId generateRuntimeResourceId({
    bool Function(RuntimeResourceId value)? isAllocated,
  }) =>
      _generate('res', RuntimeResourceId.parse, isAllocated);

  SnapshotId generateSnapshotId({
    bool Function(SnapshotId value)? isAllocated,
  }) =>
      _generate('snp', SnapshotId.parse, isAllocated);

  T _generate<T extends OpaqueId>(
    String prefix,
    T Function(String value) parse,
    bool Function(T value)? isAllocated,
  ) {
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      final bytes = _readBytes(attempt);
      final candidate = parse('${prefix}_${_encodeCrockford(bytes)}');
      if (isAllocated?.call(candidate) != true) {
        return candidate;
      }
    }
    throw OpaqueIdGenerationException(
      kind: OpaqueIdGenerationFailure.collisionLimitExceeded,
      attempts: maxAttempts,
      message: 'Opaque ID collision retry limit was exhausted.',
    );
  }

  List<int> _readBytes(int attempt) {
    late final List<int> bytes;
    try {
      bytes = _byteSource(_opaqueIdByteLength);
    } on Object catch (error) {
      throw OpaqueIdGenerationException(
        kind: OpaqueIdGenerationFailure.sourceUnavailable,
        attempts: attempt,
        message: 'The configured entropy source failed.',
        cause: error,
      );
    }
    if (bytes.length != _opaqueIdByteLength ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw OpaqueIdGenerationException(
        kind: OpaqueIdGenerationFailure.invalidSourceBytes,
        attempts: attempt,
        message: 'The entropy source must return exactly 20 bytes.',
      );
    }
    return bytes;
  }
}

List<int> _secureBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

String _encodeCrockford(List<int> bytes) {
  final encoded = StringBuffer();
  var buffer = 0;
  var bits = 0;

  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      encoded.write(_crockfordAlphabet[(buffer >> bits) & 31]);
      buffer &= (1 << bits) - 1;
    }
  }

  if (bits != 0) {
    throw StateError('A 160-bit identifier must align to Crockford symbols.');
  }
  return encoded.toString();
}
