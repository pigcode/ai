import '../id/opaque_id.dart';
import '../json/domain_json.dart';

enum TerminalOutcome {
  completed,
  failed,
  cancelled,
  interrupted,
}

final class TerminalProposal {
  TerminalProposal({
    required this.runId,
    required this.attemptId,
    required this.executionEpoch,
    required this.outcome,
    required this.sourceId,
    required this.sourceWatermark,
    required this.causationId,
    required Map<String, Object?> payload,
    this.hasMatchingCancellationIntent = false,
    this.executionContainmentProven = false,
  }) : payload = DomainJson.freeze(payload)! as Map<String, Object?> {
    if (executionEpoch <= 0 || sourceWatermark < 0) {
      throw ArgumentError(
        'Terminal proposal epochs must be positive and watermark nonnegative.',
      );
    }
  }

  final RunId runId;
  final AttemptId attemptId;
  final int executionEpoch;
  final TerminalOutcome outcome;
  final String sourceId;
  final int sourceWatermark;
  final OpaqueId causationId;
  final Map<String, Object?> payload;
  final bool hasMatchingCancellationIntent;
  final bool executionContainmentProven;
}
