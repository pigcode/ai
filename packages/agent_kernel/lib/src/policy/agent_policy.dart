import '../domain/work_item.dart';
import '../id/opaque_id.dart';
import '../json/domain_json.dart';
import 'policy_decision.dart';

final class WorkItemRequest {
  WorkItemRequest({
    required this.runId,
    required this.principal,
    required this.toolIdentity,
    required Map<String, Object?> arguments,
    required this.workspaceScopeReference,
    required this.environmentAllowlistDigest,
    required this.capabilityGrantVersion,
    required this.effectControl,
    required this.approvalExpiresAt,
  }) : arguments = DomainJson.freeze(arguments)! as Map<String, Object?> {
    if (!approvalExpiresAt.isUtc) {
      throw ArgumentError.value(
        approvalExpiresAt,
        'approvalExpiresAt',
        'Approval expiry must be UTC.',
      );
    }
  }

  final RunId runId;
  final String principal;
  final String toolIdentity;
  final Map<String, Object?> arguments;
  final String workspaceScopeReference;
  final String environmentAllowlistDigest;
  final String capabilityGrantVersion;
  final EffectControl effectControl;
  final DateTime approvalExpiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'runId': runId.value,
        'principal': principal,
        'toolIdentity': toolIdentity,
        'arguments': arguments,
        'workspaceScopeReference': workspaceScopeReference,
        'environmentAllowlistDigest': environmentAllowlistDigest,
        'capabilityGrantVersion': capabilityGrantVersion,
        'effectControl': effectControl.name,
        'approvalExpiresAt': approvalExpiresAt.toIso8601String(),
      };
}

abstract interface class AgentPolicy {
  String get version;

  PolicyDecision evaluate(WorkItemRequest request, DateTime nowUtc);
}
