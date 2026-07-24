import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class VirtualAgentClock extends AgentClock {
  VirtualAgentClock(DateTime initialWallTimeUtc)
      : _wallTimeUtc = _requireUtc(initialWallTimeUtc);

  DateTime _wallTimeUtc;
  Duration _monotonicElapsed = Duration.zero;
  final List<_PendingDelay> _pending = <_PendingDelay>[];

  @override
  DateTime get wallTimeUtc => _wallTimeUtc;

  @override
  Duration get monotonicElapsed => _monotonicElapsed;

  @override
  Future<void> delay(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    if (duration == Duration.zero) {
      return Future<void>.value();
    }
    final pending = _PendingDelay(_monotonicElapsed + duration);
    _pending.add(pending);
    return pending.completer.future;
  }

  void advance(Duration elapsed, {Duration? wallTimeDelta}) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'Must not be negative.');
    }
    _monotonicElapsed += elapsed;
    _wallTimeUtc = _wallTimeUtc.add(wallTimeDelta ?? elapsed);

    final ready = _pending
        .where((pending) => pending.target <= _monotonicElapsed)
        .toList(growable: false);
    _pending.removeWhere((pending) => ready.contains(pending));
    for (final pending in ready) {
      pending.completer.complete();
    }
  }

  void setWallTimeUtc(DateTime value) {
    _wallTimeUtc = _requireUtc(value);
  }
}

final class _PendingDelay {
  _PendingDelay(this.target);

  final Duration target;
  final Completer<void> completer = Completer<void>();
}

DateTime _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'value', 'Wall time must be UTC.');
  }
  return value;
}
