import 'dart:io';

import '../src/agent_sandbox_crash_harness.dart';

Future<void> main() async {
  _expect(
    agentSandboxCrashScenarios.length == 10,
    'Containment inventory must remain an explicit 10-point matrix.',
  );
  final reports = await runAgentSandboxCrashMatrix(
    agentSandboxCrashScenarios,
  );
  _expect(reports.length == 10, 'Crash matrix did not complete.');
  for (final report in reports) {
    _expect(
      validateAgentSandboxCrashReport(report).isEmpty,
      '${report.scenario} violations: '
      '${validateAgentSandboxCrashReport(report)}',
    );
    _expect(report.capabilityReprobed, '${report.scenario} reused capability.');
    _expect(
      report.boundaryEvidence['scenario'] == report.scenario,
      '${report.scenario} boundary evidence is not scenario-bound.',
    );
    _expect(report.storeArtifactState.isNotEmpty, 'Missing artifact state.');
  }

  await _expectMutationDetected(
    'effect-mid-execution',
    AgentSandboxCrashMutation.leaveResidualProcess,
    'residual-process',
  );
  await _expectMutationDetected(
    'restart-recovery-mid-capability-rebuild',
    AgentSandboxCrashMutation.reuseCapabilitySnapshot,
    'capability-not-reprobed',
  );
  await _expectMutationDetected(
    'effect-after-execution-before-outcome',
    AgentSandboxCrashMutation.replayUnknownOutcome,
    'outcome-replayed',
  );
  await _expectMutationDetected(
    'sandbox-setup-before-apply',
    AgentSandboxCrashMutation.claimRestrictedWithoutApply,
    'false-restricted-claim',
  );
  stdout.writeln('PASS Agent sandbox SIGKILL matrix (10 scenarios)');
}

Future<void> _expectMutationDetected(
  String scenario,
  AgentSandboxCrashMutation mutation,
  String expectedViolation,
) async {
  final report = await runAgentSandboxCrashScenario(
    scenario,
    mutation: mutation,
  );
  final violations = validateAgentSandboxCrashReport(report);
  _expect(
    violations.contains(expectedViolation),
    '$mutation was not detected: $violations',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
