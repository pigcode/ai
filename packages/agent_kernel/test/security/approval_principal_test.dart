import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('P3-TM-ELEV-03 approval cannot cross principals', () {
    final binding = _binding();

    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 24),
        currentPrincipal: 'principal:alice',
        runCancelled: false,
      ),
      isTrue,
    );
    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 24),
        currentPrincipal: 'principal:bob',
        runCancelled: false,
      ),
      isFalse,
    );
  });

  test('P3-TM-TAMPER-01 every approval scope field is content-bound', () {
    final binding = _binding();
    final evidence = ApprovalEvidence(
      bindingDigest: binding.digest,
      decision: ApprovalDecision.approve,
    );
    final rebound = ApprovalBinding(
      principal: binding.principal,
      workItemId: binding.workItemId,
      toolIdentity: binding.toolIdentity,
      arguments: binding.arguments,
      workspaceScopeReference: 'workspace:other',
      environmentAllowlistDigest: binding.environmentAllowlistDigest,
      capabilityGrantVersion: binding.capabilityGrantVersion,
      policyVersion: binding.policyVersion,
      expiresAt: binding.expiresAt,
    );

    expect(evidence.validates(binding), isTrue);
    expect(evidence.validates(rebound), isFalse);
  });
}

ApprovalBinding _binding() => ApprovalBinding(
      principal: 'principal:alice',
      workItemId: WorkItemId.parse('wrk_00000000000000000000000000000000'),
      toolIdentity: 'tool:test',
      arguments: const <String, Object?>{'path': 'workspace/file.txt'},
      workspaceScopeReference: 'workspace:test',
      environmentAllowlistDigest: ''.padLeft(64, 'a'),
      capabilityGrantVersion: 'grant/v1',
      policyVersion: 'policy/v1',
      expiresAt: DateTime.utc(2026, 7, 25),
    );
