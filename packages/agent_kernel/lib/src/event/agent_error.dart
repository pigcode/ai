import 'agent_event_metadata.dart';

enum AgentErrorCode {
  invalidRequest,
  unsupported,
  unauthenticated,
  permissionDenied,
  preconditionFailed,
  contentModified,
  executionFailed,
  cancelled,
  timedOut,
  unavailable,
  staleHandle,
  transportLost,
  driverUnavailable,
  internal,
}

enum AgentErrorScope {
  command,
  session,
  run,
  workItem,
  driver,
  store,
  observer,
  host,
}

enum AgentErrorPhase {
  validation,
  acceptance,
  execution,
  cancellation,
  reconciliation,
  recovery,
  observation,
}

enum AgentErrorSource {
  kernel,
  policy,
  driver,
  store,
  host,
  protocol,
  observer,
}

enum AgentRetryDisposition {
  never,
  afterRefresh,
  afterBackoff,
  reconcile,
}

enum AgentEffect {
  none,
  partial,
  complete,
  unknown,
}

class AgentError implements Exception {
  AgentError({
    required this.code,
    required this.scope,
    required this.phase,
    required this.source,
    required this.retryDisposition,
    required this.effect,
    required this.safeMessage,
    required this.namespacedDetails,
  }) {
    if (safeMessage.isEmpty) {
      throw ArgumentError.value(
        safeMessage,
        'safeMessage',
        'Must not be empty.',
      );
    }
    validateSafePersistedText(safeMessage);
  }

  final AgentErrorCode code;
  final AgentErrorScope scope;
  final AgentErrorPhase phase;
  final AgentErrorSource source;
  final AgentRetryDisposition retryDisposition;
  final AgentEffect effect;
  final String safeMessage;
  final AgentEventMetadata namespacedDetails;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code.name,
        'scope': scope.name,
        'phase': phase.name,
        'source': source.name,
        'retryDisposition': retryDisposition.name,
        'effect': effect.name,
        'safeMessage': safeMessage,
        'namespacedDetails': namespacedDetails.toJson(),
      };

  @override
  String toString() => 'AgentError(${code.name}): $safeMessage';
}

final class AgentCommandError extends AgentError {
  AgentCommandError({
    required super.code,
    required super.scope,
    required super.phase,
    required super.source,
    required super.retryDisposition,
    required super.effect,
    required super.safeMessage,
    required super.namespacedDetails,
  });

  @override
  String toString() => 'AgentCommandError(${code.name}): $safeMessage';
}
