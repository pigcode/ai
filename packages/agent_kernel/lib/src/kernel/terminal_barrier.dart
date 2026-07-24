import '../domain/agent_session.dart';
import '../domain/approval.dart';
import '../domain/deferred_operation.dart';
import '../domain/runtime_resource.dart';
import '../domain/work_item.dart';
import '../id/opaque_id.dart';
import 'terminal_proposal.dart';

enum ObservedEffectState {
  active,
  completed,
  outcomeUnknown,
  transferred,
}

final class ObservedEffectBarrier {
  const ObservedEffectBarrier({
    required this.runId,
    required this.state,
  });

  final RunId runId;
  final ObservedEffectState state;
}

enum TerminalBarrierBlocker {
  runNotFound,
  alreadyTerminal,
  staleAttempt,
  staleExecutionEpoch,
  sourceNotDrained,
  activeManagedWork,
  unresolvedApproval,
  runOwnedDeferredOperation,
  runOwnedRuntimeResource,
  unresolvedObservedEffect,
  cancellationAuthorityMissing,
}

final class TerminalBarrierResult {
  TerminalBarrierResult(Set<TerminalBarrierBlocker> blockers)
      : blockers = Set<TerminalBarrierBlocker>.unmodifiable(blockers);

  final Set<TerminalBarrierBlocker> blockers;

  bool get isReady => blockers.isEmpty;
}

final class TerminalBarrier {
  const TerminalBarrier();

  TerminalBarrierResult evaluate({
    required AgentSessionProjection projection,
    required TerminalProposal proposal,
    required Map<String, int> drainedSourceWatermarks,
    Iterable<ObservedEffectBarrier> observedEffects =
        const <ObservedEffectBarrier>[],
  }) {
    final blockers = <TerminalBarrierBlocker>{};
    final run = projection.runs[proposal.runId];
    if (run == null) {
      blockers.add(TerminalBarrierBlocker.runNotFound);
      return TerminalBarrierResult(blockers);
    }
    if (run.state.isTerminal || run.terminalEventId != null) {
      blockers.add(TerminalBarrierBlocker.alreadyTerminal);
    }
    if (run.currentAttemptId != proposal.attemptId) {
      blockers.add(TerminalBarrierBlocker.staleAttempt);
    } else {
      final attempt = run.attempts[proposal.attemptId];
      if (attempt == null ||
          attempt.executionEpoch != proposal.executionEpoch) {
        blockers.add(TerminalBarrierBlocker.staleExecutionEpoch);
      }
    }
    if ((drainedSourceWatermarks[proposal.sourceId] ?? -1) <
        proposal.sourceWatermark) {
      blockers.add(TerminalBarrierBlocker.sourceNotDrained);
    }
    if (projection.workItems.values.any(
      (work) =>
          work.runId == proposal.runId &&
          (work.effectControl == EffectControl.managed ||
              work.effectControl == EffectControl.interceptable) &&
          !work.state.isTerminal,
    )) {
      blockers.add(TerminalBarrierBlocker.activeManagedWork);
    }
    if (projection.approvals.values.any(
      (approval) =>
          approval.state == ApprovalState.pending &&
          projection.workItems[approval.workItemId]?.runId == proposal.runId,
    )) {
      blockers.add(TerminalBarrierBlocker.unresolvedApproval);
    }
    if (projection.deferredOperations.values.any(
      (operation) =>
          operation.originRunId == proposal.runId &&
          operation.owner == DeferredOperationOwner.run &&
          !operation.state.isTerminal,
    )) {
      blockers.add(TerminalBarrierBlocker.runOwnedDeferredOperation);
    }
    if (projection.resources.values.any(
      (resource) =>
          resource.owner == RuntimeResourceOwner.run &&
          resource.ownerRunId == proposal.runId &&
          resource.state != RuntimeResourceState.released &&
          resource.state != RuntimeResourceState.outcomeUnknown,
    )) {
      blockers.add(TerminalBarrierBlocker.runOwnedRuntimeResource);
    }
    if (observedEffects.any(
      (effect) =>
          effect.runId == proposal.runId &&
          effect.state == ObservedEffectState.active,
    )) {
      blockers.add(TerminalBarrierBlocker.unresolvedObservedEffect);
    }
    if (proposal.outcome == TerminalOutcome.cancelled &&
        !proposal.hasMatchingCancellationIntent &&
        !proposal.executionContainmentProven) {
      blockers.add(TerminalBarrierBlocker.cancellationAuthorityMissing);
    }
    return TerminalBarrierResult(blockers);
  }
}
