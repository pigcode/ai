import '../id/opaque_id.dart';
import 'terminal_proposal.dart';

final class CancellationIntent {
  const CancellationIntent({
    required this.commandId,
    required this.runId,
  });

  final CommandId commandId;
  final RunId runId;
}

final class CancellationBarrier {
  const CancellationBarrier({
    required this.runId,
    required this.attemptId,
    required this.executionEpoch,
    this.intentCommandId,
    this.driverAcknowledged = false,
    this.executionContainmentProven = false,
  });

  final RunId runId;
  final AttemptId attemptId;
  final int executionEpoch;
  final CommandId? intentCommandId;
  final bool driverAcknowledged;
  final bool executionContainmentProven;
}

enum CancellationDisposition {
  awaitingAuthoritativeBarrier,
  cancelled,
  interrupted,
}

final class Cancellation {
  const Cancellation();

  CancellationDisposition evaluate({
    required CancellationIntent? intent,
    required CancellationBarrier barrier,
    required AttemptId authoritativeAttemptId,
    required int authoritativeExecutionEpoch,
  }) {
    final authoritative = barrier.attemptId == authoritativeAttemptId &&
        barrier.executionEpoch == authoritativeExecutionEpoch;
    if (!authoritative) {
      return CancellationDisposition.awaitingAuthoritativeBarrier;
    }
    final matchesIntent = intent != null &&
        intent.runId == barrier.runId &&
        intent.commandId == barrier.intentCommandId;
    if (matchesIntent || barrier.executionContainmentProven) {
      return CancellationDisposition.cancelled;
    }
    if (barrier.driverAcknowledged) {
      return CancellationDisposition.awaitingAuthoritativeBarrier;
    }
    return CancellationDisposition.interrupted;
  }

  TerminalOutcome? terminalOutcome(CancellationDisposition disposition) =>
      switch (disposition) {
        CancellationDisposition.awaitingAuthoritativeBarrier => null,
        CancellationDisposition.cancelled => TerminalOutcome.cancelled,
        CancellationDisposition.interrupted => TerminalOutcome.interrupted,
      };
}
