import '../id/opaque_id.dart';
import '../json/canonical_json.dart';
import '../json/domain_json.dart';

enum ApprovalDecision {
  approve,
  deny,
}

final class ApprovalBinding {
  ApprovalBinding({
    required this.principal,
    required this.workItemId,
    required this.toolIdentity,
    required Map<String, Object?> arguments,
    required this.workspaceScopeReference,
    required this.environmentAllowlistDigest,
    required this.capabilityGrantVersion,
    required this.policyVersion,
    required this.expiresAt,
  }) : arguments = DomainJson.freeze(arguments)! as Map<String, Object?> {
    if (!expiresAt.isUtc) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'Approval expiry must be UTC.',
      );
    }
  }

  final String principal;
  final WorkItemId workItemId;
  final String toolIdentity;
  final Map<String, Object?> arguments;
  final String workspaceScopeReference;
  final String environmentAllowlistDigest;
  final String capabilityGrantVersion;
  final String policyVersion;
  final DateTime expiresAt;

  String get digest => canonicalJsonSha256(toJson());

  bool isValid({
    required DateTime nowUtc,
    required String currentPrincipal,
    required bool runCancelled,
  }) =>
      !runCancelled &&
      currentPrincipal == principal &&
      nowUtc.isBefore(expiresAt);

  Map<String, Object?> toJson() => <String, Object?>{
        'principal': principal,
        'workItemId': workItemId.value,
        'toolIdentity': toolIdentity,
        'arguments': arguments,
        'workspaceScopeReference': workspaceScopeReference,
        'environmentAllowlistDigest': environmentAllowlistDigest,
        'capabilityGrantVersion': capabilityGrantVersion,
        'policyVersion': policyVersion,
        'expiresAt': expiresAt.toIso8601String(),
      };
}

final class ApprovalEvidence {
  const ApprovalEvidence({
    required this.bindingDigest,
    required this.decision,
    this.consumed = false,
  });

  final String bindingDigest;
  final ApprovalDecision decision;
  final bool consumed;

  bool validates(ApprovalBinding binding) =>
      !consumed && bindingDigest == binding.digest;

  ApprovalEvidence consume() {
    if (consumed) {
      throw StateError('Approval evidence is one-shot.');
    }
    return ApprovalEvidence(
      bindingDigest: bindingDigest,
      decision: decision,
      consumed: true,
    );
  }
}
