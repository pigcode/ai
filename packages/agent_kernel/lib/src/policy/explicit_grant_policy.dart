import '../domain/work_item.dart';
import 'agent_policy.dart';
import 'policy_decision.dart';

final class ExplicitPolicyGrant {
  ExplicitPolicyGrant({
    required this.principal,
    required this.toolIdentity,
    required this.workspaceScopeReference,
    required this.environmentAllowlistDigest,
    required this.capabilityGrantVersion,
    required Set<EffectControl> effectControls,
    required this.requireApproval,
    this.expiresAt,
  }) : effectControls = Set<EffectControl>.unmodifiable(effectControls);

  final String principal;
  final String toolIdentity;
  final String workspaceScopeReference;
  final String environmentAllowlistDigest;
  final String capabilityGrantVersion;
  final Set<EffectControl> effectControls;
  final bool requireApproval;
  final DateTime? expiresAt;

  bool matches(WorkItemRequest request, DateTime nowUtc) =>
      principal == request.principal &&
      toolIdentity == request.toolIdentity &&
      workspaceScopeReference == request.workspaceScopeReference &&
      environmentAllowlistDigest == request.environmentAllowlistDigest &&
      capabilityGrantVersion == request.capabilityGrantVersion &&
      effectControls.contains(request.effectControl) &&
      (expiresAt == null || nowUtc.isBefore(expiresAt!));
}

final class ExplicitGrantPolicy implements AgentPolicy {
  ExplicitGrantPolicy({
    required this.version,
    required Iterable<ExplicitPolicyGrant> grants,
  }) : grants = List<ExplicitPolicyGrant>.unmodifiable(grants);

  @override
  final String version;
  final List<ExplicitPolicyGrant> grants;

  @override
  PolicyDecision evaluate(WorkItemRequest request, DateTime nowUtc) {
    for (final grant in grants) {
      if (grant.matches(request, nowUtc)) {
        return PolicyDecision(
          grant.requireApproval
              ? PolicyDecisionKind.requireApproval
              : PolicyDecisionKind.allow,
          policyVersion: version,
        );
      }
    }
    return PolicyDecision(PolicyDecisionKind.deny, policyVersion: version);
  }
}
