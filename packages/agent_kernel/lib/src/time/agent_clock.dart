/// Supplies UTC wall time, monotonic elapsed time, and timer scheduling.
abstract class AgentClock {
  DateTime get wallTimeUtc;

  Duration get monotonicElapsed;

  Future<void> delay(Duration duration);

  Duration remainingUntil(DateTime deadlineUtc) {
    if (!deadlineUtc.isUtc) {
      throw ArgumentError.value(
        deadlineUtc,
        'deadlineUtc',
        'Persisted deadlines must be UTC.',
      );
    }
    final remaining = deadlineUtc.difference(wallTimeUtc);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// The production clock backed by UTC wall time and a monotonic stopwatch.
final class SystemAgentClock extends AgentClock {
  SystemAgentClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  DateTime get wallTimeUtc => DateTime.now().toUtc();

  @override
  Duration get monotonicElapsed => _stopwatch.elapsed;

  @override
  Future<void> delay(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    return Future<void>.delayed(duration);
  }
}
