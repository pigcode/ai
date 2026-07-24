import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('every approval-bound field changes the digest', () {
    final original = _binding();
    final mutations = <ApprovalBinding>[
      _binding(principal: 'principal:other'),
      _binding(workItemId: _otherWork),
      _binding(toolIdentity: 'tool:other'),
      _binding(arguments: const <String, Object?>{'value': 2}),
      _binding(workspaceScopeReference: 'workspace:other'),
      _binding(environmentAllowlistDigest: _otherDigest),
      _binding(capabilityGrantVersion: 'grant/v2'),
      _binding(policyVersion: 'policy/v2'),
      _binding(expiresAt: DateTime.utc(2026, 7, 26)),
    ];

    for (final mutation in mutations) {
      expect(mutation.digest, isNot(original.digest));
    }
  });

  test('expiry, principal change, and Run cancellation invalidate approval',
      () {
    final binding = _binding();
    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 24),
        currentPrincipal: 'principal:test',
        runCancelled: false,
      ),
      isTrue,
    );
    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 26),
        currentPrincipal: 'principal:test',
        runCancelled: false,
      ),
      isFalse,
    );
    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 24),
        currentPrincipal: 'principal:other',
        runCancelled: false,
      ),
      isFalse,
    );
    expect(
      binding.isValid(
        nowUtc: DateTime.utc(2026, 7, 24),
        currentPrincipal: 'principal:test',
        runCancelled: true,
      ),
      isFalse,
    );
  });

  test('approval evidence is content-bound and one-shot', () {
    final binding = _binding();
    final evidence = ApprovalEvidence(
      bindingDigest: binding.digest,
      decision: ApprovalDecision.approve,
    );

    expect(evidence.validates(binding), isTrue);
    final consumed = evidence.consume();
    expect(consumed.validates(binding), isFalse);
    expect(consumed.consume, throwsStateError);
  });
}

ApprovalBinding _binding({
  String principal = 'principal:test',
  WorkItemId? workItemId,
  String toolIdentity = 'tool:test',
  Map<String, Object?> arguments = const <String, Object?>{'value': 1},
  String workspaceScopeReference = 'workspace:test',
  String environmentAllowlistDigest = _digest,
  String capabilityGrantVersion = 'grant/v1',
  String policyVersion = 'policy/v1',
  DateTime? expiresAt,
}) =>
    ApprovalBinding(
      principal: principal,
      workItemId: workItemId ?? _work,
      toolIdentity: toolIdentity,
      arguments: arguments,
      workspaceScopeReference: workspaceScopeReference,
      environmentAllowlistDigest: environmentAllowlistDigest,
      capabilityGrantVersion: capabilityGrantVersion,
      policyVersion: policyVersion,
      expiresAt: expiresAt ?? DateTime.utc(2026, 7, 25),
    );

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _work = WorkItemId.parse('wrk_00000000000000000000000000000000');
final _otherWork = WorkItemId.parse('wrk_10000000000000000000000000000000');
