import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/work_policy_fixture.dart';

void main() {
  test('deny-by-default returns a real deny decision', () {
    const policy = DenyByDefaultPolicy();
    final decision = policy.evaluate(
      workRequest(_run),
      DateTime.utc(2026, 7, 24),
    );

    expect(decision.kind, PolicyDecisionKind.deny);
    expect(decision.policyVersion, 'deny-by-default/v1');
  });

  test('explicit immutable grant matches all bound fields', () {
    final policy = workPolicy(effectControl: EffectControl.managed);
    final now = DateTime.utc(2026, 7, 24);

    expect(
      policy.evaluate(workRequest(_run), now).kind,
      PolicyDecisionKind.allow,
    );
    expect(
      policy
          .evaluate(
            workRequest(_run, principal: 'principal:other'),
            now,
          )
          .kind,
      PolicyDecisionKind.deny,
    );
  });

  test('all effect controls remain distinct policy inputs', () {
    final now = DateTime.utc(2026, 7, 24);
    for (final effectControl in EffectControl.values) {
      final policy = workPolicy(effectControl: effectControl);
      expect(
        policy
            .evaluate(
              workRequest(_run, effectControl: effectControl),
              now,
            )
            .kind,
        PolicyDecisionKind.allow,
        reason: effectControl.name,
      );
      final different = EffectControl.values.firstWhere(
        (candidate) => candidate != effectControl,
      );
      expect(
        policy
            .evaluate(
              workRequest(_run, effectControl: different),
              now,
            )
            .kind,
        PolicyDecisionKind.deny,
      );
    }
  });

  test('explicit grant can require one-shot approval and expire', () {
    final now = DateTime.utc(2026, 7, 24);
    final policy = ExplicitGrantPolicy(
      version: 'policy/v2',
      grants: <ExplicitPolicyGrant>[
        ExplicitPolicyGrant(
          principal: 'principal:test',
          toolIdentity: 'tool:test',
          workspaceScopeReference: 'workspace:test',
          environmentAllowlistDigest:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          capabilityGrantVersion: 'grant/v1',
          effectControls: const <EffectControl>{EffectControl.interceptable},
          requireApproval: true,
          expiresAt: now.add(const Duration(minutes: 1)),
        ),
      ],
    );
    final request = workRequest(
      _run,
      effectControl: EffectControl.interceptable,
    );

    expect(
      policy.evaluate(request, now).kind,
      PolicyDecisionKind.requireApproval,
    );
    expect(
      policy.evaluate(request, now.add(const Duration(minutes: 2))).kind,
      PolicyDecisionKind.deny,
    );
  });
}

final _run = RunId.parse('run_00000000000000000000000000000000');
