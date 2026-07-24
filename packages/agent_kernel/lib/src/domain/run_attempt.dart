import '../id/opaque_id.dart';

enum RunAttemptState { started, active, fenced, terminal }

final class RunAttempt {
  const RunAttempt({
    required this.id,
    required this.state,
    required this.executionEpoch,
  });

  final AttemptId id;
  final RunAttemptState state;
  final int executionEpoch;

  RunAttempt copyWith({RunAttemptState? state}) => RunAttempt(
        id: id,
        state: state ?? this.state,
        executionEpoch: executionEpoch,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'state': state.name,
        'executionEpoch': executionEpoch,
      };
}
