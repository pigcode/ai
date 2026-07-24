import 'package:test/test.dart';

import '../support/virtual_agent_clock.dart';

void main() {
  final epoch = DateTime.utc(2026, 7, 24, 0);

  test('wall-clock rollback does not roll back monotonic elapsed time', () {
    final clock = VirtualAgentClock(epoch);

    clock.advance(const Duration(seconds: 5));
    clock.setWallTimeUtc(epoch.subtract(const Duration(days: 1)));

    expect(clock.wallTimeUtc, epoch.subtract(const Duration(days: 1)));
    expect(clock.monotonicElapsed, const Duration(seconds: 5));
  });

  test('virtual timers complete only after an exact monotonic advance',
      () async {
    final clock = VirtualAgentClock(epoch);
    var completed = false;
    final delayed = clock.delay(const Duration(seconds: 5)).then((_) {
      completed = true;
    });

    clock.advance(const Duration(seconds: 4));
    await Future<void>.value();
    expect(completed, isFalse);

    clock.advance(const Duration(seconds: 1));
    await delayed;
    expect(completed, isTrue);
  });

  test('persisted UTC deadline recovery clamps remaining time at zero', () {
    final clock = VirtualAgentClock(epoch);
    final deadline = epoch.add(const Duration(minutes: 2));

    expect(clock.remainingUntil(deadline), const Duration(minutes: 2));
    clock.advance(const Duration(minutes: 3));
    expect(clock.remainingUntil(deadline), Duration.zero);
  });

  test('wall timestamps and persisted deadlines must be UTC', () {
    final local = DateTime(2026, 7, 24);

    expect(() => VirtualAgentClock(local), throwsArgumentError);
    expect(
      () => VirtualAgentClock(epoch).remainingUntil(local),
      throwsArgumentError,
    );
  });
}
