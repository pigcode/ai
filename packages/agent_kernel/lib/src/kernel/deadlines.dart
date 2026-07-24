import '../time/agent_clock.dart';

enum AgentDeadlineScope {
  activityTimeout,
  absoluteDeadline,
  workItemDeadline,
  recoveryWindow,
  cancelGrace,
  sliceBudget,
  observerIdle,
}

enum AgentDeadlineAction {
  requestCancellation,
  reconcile,
  suspendForCheckpoint,
  detachObserver,
  none,
}

final class AgentDeadlines {
  AgentDeadlines(Map<AgentDeadlineScope, DateTime> deadlines)
      : deadlines = Map<AgentDeadlineScope, DateTime>.unmodifiable(
          deadlines.map(
            (scope, deadline) => MapEntry(scope, _requireUtc(deadline)),
          ),
        );

  final Map<AgentDeadlineScope, DateTime> deadlines;

  AgentDeadlines recordProgress({
    required DateTime nowUtc,
    required Duration activityTimeout,
  }) {
    _requireUtc(nowUtc);
    if (activityTimeout.isNegative) {
      throw ArgumentError.value(activityTimeout, 'activityTimeout');
    }
    if (!deadlines.containsKey(AgentDeadlineScope.activityTimeout)) {
      return this;
    }
    return AgentDeadlines(<AgentDeadlineScope, DateTime>{
      ...deadlines,
      AgentDeadlineScope.activityTimeout: nowUtc.add(activityTimeout),
    });
  }

  Duration remaining(AgentClock clock, AgentDeadlineScope scope) {
    final deadline = deadlines[scope];
    return deadline == null ? Duration.zero : clock.remainingUntil(deadline);
  }

  Set<AgentDeadlineScope> expired(DateTime nowUtc) {
    _requireUtc(nowUtc);
    return <AgentDeadlineScope>{
      for (final entry in deadlines.entries)
        if (!entry.value.isAfter(nowUtc)) entry.key,
    };
  }

  AgentDeadlineAction actionFor(
    AgentDeadlineScope scope, {
    required bool durableCheckpointResume,
  }) =>
      switch (scope) {
        AgentDeadlineScope.activityTimeout ||
        AgentDeadlineScope.absoluteDeadline ||
        AgentDeadlineScope.workItemDeadline =>
          AgentDeadlineAction.requestCancellation,
        AgentDeadlineScope.recoveryWindow ||
        AgentDeadlineScope.cancelGrace =>
          AgentDeadlineAction.reconcile,
        AgentDeadlineScope.sliceBudget => durableCheckpointResume
            ? AgentDeadlineAction.suspendForCheckpoint
            : AgentDeadlineAction.none,
        AgentDeadlineScope.observerIdle => AgentDeadlineAction.detachObserver,
      };
}

DateTime _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'value', 'Deadline must be UTC.');
  }
  return value;
}
