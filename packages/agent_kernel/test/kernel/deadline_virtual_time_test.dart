import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/virtual_agent_clock.dart';

void main() {
  test('progress refreshes only activity timeout', () {
    final now = DateTime.utc(2026, 7, 24);
    final absolute = now.add(const Duration(minutes: 10));
    final deadlines = AgentDeadlines(<AgentDeadlineScope, DateTime>{
      AgentDeadlineScope.activityTimeout: now.add(const Duration(minutes: 1)),
      AgentDeadlineScope.absoluteDeadline: absolute,
    });
    final refreshed = deadlines.recordProgress(
      nowUtc: now.add(const Duration(seconds: 30)),
      activityTimeout: const Duration(minutes: 2),
    );

    expect(
      refreshed.deadlines[AgentDeadlineScope.activityTimeout],
      now.add(const Duration(minutes: 2, seconds: 30)),
    );
    expect(
      refreshed.deadlines[AgentDeadlineScope.absoluteDeadline],
      absolute,
    );
  });

  test('restart computes remaining time from persisted UTC deadline', () {
    final now = DateTime.utc(2026, 7, 24);
    final clock = VirtualAgentClock(now);
    final deadlines = AgentDeadlines(<AgentDeadlineScope, DateTime>{
      AgentDeadlineScope.recoveryWindow: now.add(const Duration(minutes: 5)),
    });
    clock.advance(const Duration(minutes: 2));

    expect(
      deadlines.remaining(clock, AgentDeadlineScope.recoveryWindow),
      const Duration(minutes: 3),
    );
  });

  test('deadline scopes produce bounded actions', () {
    final deadlines = AgentDeadlines(const <AgentDeadlineScope, DateTime>{});
    expect(
      deadlines.actionFor(
        AgentDeadlineScope.cancelGrace,
        durableCheckpointResume: false,
      ),
      AgentDeadlineAction.reconcile,
    );
    expect(
      deadlines.actionFor(
        AgentDeadlineScope.observerIdle,
        durableCheckpointResume: false,
      ),
      AgentDeadlineAction.detachObserver,
    );
    expect(
      deadlines.actionFor(
        AgentDeadlineScope.sliceBudget,
        durableCheckpointResume: false,
      ),
      AgentDeadlineAction.none,
    );
    expect(
      deadlines.actionFor(
        AgentDeadlineScope.sliceBudget,
        durableCheckpointResume: true,
      ),
      AgentDeadlineAction.suspendForCheckpoint,
    );
  });
}
