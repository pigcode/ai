enum PolicyDecisionKind {
  allow,
  deny,
  requireApproval,
}

final class PolicyDecision {
  const PolicyDecision(this.kind, {required this.policyVersion});

  final PolicyDecisionKind kind;
  final String policyVersion;
}
