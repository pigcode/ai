import '../id/opaque_id.dart';

enum DeferredOperationOwner { run, session }

enum DeferredCancellationPolicy {
  cancelWithOwner,
  transferToSession,
  manual,
}

enum DeferredOperationState {
  pending,
  completed,
  failed,
  cancelled,
  outcomeUnknown;

  bool get isTerminal => this != pending;
}

final class DeferredOperation {
  const DeferredOperation({
    required this.id,
    required this.originRunId,
    required this.owner,
    required this.state,
    required this.cancellationPolicy,
    this.deadlineAt,
    this.ownershipTransferDigest,
    this.terminalDigest,
    this.terminalResult,
  });

  final DeferredOperationId id;
  final RunId originRunId;
  final DeferredOperationOwner owner;
  final DeferredOperationState state;
  final DeferredCancellationPolicy cancellationPolicy;
  final DateTime? deadlineAt;
  final String? ownershipTransferDigest;
  final String? terminalDigest;
  final Object? terminalResult;

  DeferredOperation copyWith({
    DeferredOperationOwner? owner,
    DeferredOperationState? state,
    String? ownershipTransferDigest,
    String? terminalDigest,
    Object? terminalResult,
  }) =>
      DeferredOperation(
        id: id,
        originRunId: originRunId,
        owner: owner ?? this.owner,
        state: state ?? this.state,
        cancellationPolicy: cancellationPolicy,
        deadlineAt: deadlineAt,
        ownershipTransferDigest:
            ownershipTransferDigest ?? this.ownershipTransferDigest,
        terminalDigest: terminalDigest ?? this.terminalDigest,
        terminalResult: terminalResult ?? this.terminalResult,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'originRunId': originRunId.value,
        'owner': owner.name,
        'state': state.name,
        'cancellationPolicy': cancellationPolicy.name,
        if (deadlineAt != null) 'deadlineAt': deadlineAt!.toIso8601String(),
        if (ownershipTransferDigest != null)
          'ownershipTransferDigest': ownershipTransferDigest,
        if (terminalDigest != null) 'terminalDigest': terminalDigest,
        if (terminalResult != null) 'terminalResult': terminalResult,
      };
}
