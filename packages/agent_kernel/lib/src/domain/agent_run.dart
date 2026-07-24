import '../id/opaque_id.dart';
import 'run_attempt.dart';

enum AgentRunState {
  pending,
  inProgress,
  suspending,
  suspended,
  resuming,
  cancelling,
  reconciling,
  completed,
  failed,
  cancelled,
  interrupted;

  bool get isTerminal => switch (this) {
        completed || failed || cancelled || interrupted => true,
        _ => false,
      };
}

final class AgentRun {
  AgentRun({
    required this.id,
    required this.state,
    Map<AttemptId, RunAttempt> attempts = const <AttemptId, RunAttempt>{},
    this.currentAttemptId,
    this.terminalEventId,
  }) : attempts = Map<AttemptId, RunAttempt>.unmodifiable(attempts);

  final RunId id;
  final AgentRunState state;
  final Map<AttemptId, RunAttempt> attempts;
  final AttemptId? currentAttemptId;
  final EventId? terminalEventId;

  AgentRun copyWith({
    AgentRunState? state,
    Map<AttemptId, RunAttempt>? attempts,
    AttemptId? currentAttemptId,
    bool clearCurrentAttempt = false,
    EventId? terminalEventId,
  }) =>
      AgentRun(
        id: id,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        currentAttemptId: clearCurrentAttempt
            ? null
            : currentAttemptId ?? this.currentAttemptId,
        terminalEventId: terminalEventId ?? this.terminalEventId,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'state': state.name,
        'attempts': <String, Object?>{
          for (final entry in attempts.entries)
            entry.key.value: entry.value.toJson(),
        },
        if (currentAttemptId != null)
          'currentAttemptId': currentAttemptId!.value,
        if (terminalEventId != null) 'terminalEventId': terminalEventId!.value,
      };
}
