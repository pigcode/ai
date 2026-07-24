final class ReplayViolation implements Exception {
  const ReplayViolation(
    this.code,
    this.message, {
    this.sequence,
    this.eventType,
  });

  final String code;
  final String message;
  final int? sequence;
  final String? eventType;

  @override
  String toString() => 'ReplayViolation($code): $message';
}
