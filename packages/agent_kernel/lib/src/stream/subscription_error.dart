enum SubscriptionErrorCode {
  queueOverflow,
  sequenceConflict,
  cursorCompacted,
  sessionMismatch,
  closed,
}

final class SubscriptionError implements Exception {
  const SubscriptionError(this.code, this.message);

  final SubscriptionErrorCode code;
  final String message;

  @override
  String toString() => 'SubscriptionError(${code.name}): $message';
}
