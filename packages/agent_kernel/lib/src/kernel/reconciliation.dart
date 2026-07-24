enum ReconciliationTrigger {
  lostResponse,
  ordinalGap,
  restartUncertain,
  cancellationUncertain,
}

final class ReconciliationPlan {
  const ReconciliationPlan({
    required this.trigger,
    required this.replayPrompt,
    required this.retryExternalEffect,
  });

  factory ReconciliationPlan.failClosed(ReconciliationTrigger trigger) =>
      ReconciliationPlan(
        trigger: trigger,
        replayPrompt: false,
        retryExternalEffect: false,
      );

  final ReconciliationTrigger trigger;
  final bool replayPrompt;
  final bool retryExternalEffect;
}
