import 'dart:async';

final class RestartableProcessException implements Exception {
  const RestartableProcessException(this.exitCode);

  final int exitCode;
}

final class RestartBudget {
  RestartBudget({
    required this.maxAttempts,
    this.initialBackoff = const Duration(milliseconds: 50),
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts');
    }
  }

  final int maxAttempts;
  final Duration initialBackoff;

  Future<T> run<T>(Future<T> Function(int attempt) operation) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await operation(attempt);
      } on RestartableProcessException {
        if (attempt == maxAttempts) rethrow;
        final multiplier = 1 << (attempt - 1);
        await Future<void>.delayed(initialBackoff * multiplier);
      }
    }
    throw StateError('unreachable');
  }
}
