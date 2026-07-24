import '../id/opaque_id.dart';

enum RuntimeResourceOwner { run, session }

enum RuntimeResourceState { registered, active, released, outcomeUnknown }

final class RuntimeResource {
  const RuntimeResource({
    required this.id,
    required this.state,
    required this.owner,
    this.originRunId,
    this.ownerRunId,
    this.ownershipTransferDigest,
    this.terminalDigest,
  });

  final RuntimeResourceId id;
  final RuntimeResourceState state;
  final RuntimeResourceOwner owner;
  final RunId? originRunId;
  final RunId? ownerRunId;
  final String? ownershipTransferDigest;
  final String? terminalDigest;

  RuntimeResource copyWith({
    RuntimeResourceState? state,
    RuntimeResourceOwner? owner,
    RunId? ownerRunId,
    bool clearOwnerRun = false,
    String? ownershipTransferDigest,
    String? terminalDigest,
  }) =>
      RuntimeResource(
        id: id,
        state: state ?? this.state,
        owner: owner ?? this.owner,
        originRunId: originRunId,
        ownerRunId: clearOwnerRun ? null : ownerRunId ?? this.ownerRunId,
        ownershipTransferDigest:
            ownershipTransferDigest ?? this.ownershipTransferDigest,
        terminalDigest: terminalDigest ?? this.terminalDigest,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'state': state.name,
        'owner': owner.name,
        if (originRunId != null) 'originRunId': originRunId!.value,
        if (ownerRunId != null) 'ownerRunId': ownerRunId!.value,
        if (ownershipTransferDigest != null)
          'ownershipTransferDigest': ownershipTransferDigest,
        if (terminalDigest != null) 'terminalDigest': terminalDigest,
      };
}
