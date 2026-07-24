import '../id/opaque_id.dart';

enum EffectControl { managed, interceptable, observedOnly, unknown }

enum WorkItemState {
  proposed,
  policyEvaluated,
  awaitingApproval,
  approved,
  denied,
  executing,
  cancellationRequested,
  succeeded,
  failed,
  cancelled,
  outcomeUnknown;

  bool get isTerminal => switch (this) {
        denied || succeeded || failed || cancelled || outcomeUnknown => true,
        _ => false,
      };
}

final class WorkItem {
  const WorkItem({
    required this.id,
    required this.runId,
    required this.state,
    required this.effectControl,
    this.approvalId,
  });

  final WorkItemId id;
  final RunId runId;
  final WorkItemState state;
  final EffectControl effectControl;
  final ApprovalId? approvalId;

  WorkItem copyWith({
    WorkItemState? state,
    EffectControl? effectControl,
    ApprovalId? approvalId,
  }) =>
      WorkItem(
        id: id,
        runId: runId,
        state: state ?? this.state,
        effectControl: effectControl ?? this.effectControl,
        approvalId: approvalId ?? this.approvalId,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'runId': runId.value,
        'state': state.name,
        'effectControl': effectControl.name,
        if (approvalId != null) 'approvalId': approvalId!.value,
      };
}
