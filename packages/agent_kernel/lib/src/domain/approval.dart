import '../id/opaque_id.dart';

enum ApprovalState { pending, approved, denied }

final class Approval {
  const Approval({
    required this.id,
    required this.workItemId,
    required this.state,
    this.bindingDigest,
  });

  final ApprovalId id;
  final WorkItemId workItemId;
  final ApprovalState state;
  final String? bindingDigest;

  Approval copyWith({ApprovalState? state}) => Approval(
        id: id,
        workItemId: workItemId,
        state: state ?? this.state,
        bindingDigest: bindingDigest,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'workItemId': workItemId.value,
        'state': state.name,
        if (bindingDigest != null) 'bindingDigest': bindingDigest,
      };
}
