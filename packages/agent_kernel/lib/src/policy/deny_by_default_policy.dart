import 'agent_policy.dart';
import 'policy_decision.dart';

final class DenyByDefaultPolicy implements AgentPolicy {
  const DenyByDefaultPolicy({this.version = 'deny-by-default/v1'});

  @override
  final String version;

  @override
  PolicyDecision evaluate(WorkItemRequest request, DateTime nowUtc) =>
      PolicyDecision(PolicyDecisionKind.deny, policyVersion: version);
}
