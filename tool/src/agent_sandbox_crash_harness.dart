import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';

const agentSandboxCrashScenarios = <String>[
  'probe-before-after',
  'sandbox-setup-before-apply',
  'sandbox-after-apply-before-exec',
  'effect-before-execution',
  'effect-mid-execution',
  'effect-after-execution-before-outcome',
  'outcome-after-write-before-receipt',
  'cleanup-after-cancel-before-confirm',
  'cleanup-after-confirm-before-record',
  'restart-recovery-mid-capability-rebuild',
];

const _fixturePath = 'tool/fixtures/agent_sandbox_crash_child.dart';
const _deadline = Duration(seconds: 12);

const _boundaryPhases = <String, String>{
  'probe-before-after': 'probe-before-after',
  'sandbox-setup-before-apply': 'profile-validated-before-apply',
  'sandbox-after-apply-before-exec': 'sandbox-ready-before-exec-ack',
  'effect-before-execution': 'journal-unknown-before-effect',
  'effect-mid-execution': 'side-effect-started-before-completion',
  'effect-after-execution-before-outcome': 'effect-completed-before-outcome',
  'outcome-after-write-before-receipt': 'outcome-durable-before-receipt',
  'cleanup-after-cancel-before-confirm':
      'cancel-signal-before-cleanup-confirmation',
  'cleanup-after-confirm-before-record':
      'process-dead-before-ledger-confirmation',
  'restart-recovery-mid-capability-rebuild':
      'fresh-probe-before-capability-commit',
};

enum AgentSandboxCrashMutation {
  none('none'),
  leaveResidualProcess('leave-residual-process'),
  reuseCapabilitySnapshot('reuse-capability-snapshot'),
  replayUnknownOutcome('replay-unknown-outcome'),
  claimRestrictedWithoutApply('claim-restricted-without-apply');

  const AgentSandboxCrashMutation(this.wireName);

  final String wireName;
}

final class AgentSandboxCrashReport {
  const AgentSandboxCrashReport({
    required this.scenario,
    required this.falseRestrictedClaim,
    required this.residualProcess,
    required this.cleanupConfirmed,
    required this.outcomeReplayed,
    required this.capabilityReprobed,
    required this.boundaryEvidence,
    required this.storeArtifactState,
  });

  final String scenario;
  final bool falseRestrictedClaim;
  final bool residualProcess;
  final bool cleanupConfirmed;
  final bool outcomeReplayed;
  final bool capabilityReprobed;
  final Map<String, Object?> boundaryEvidence;
  final Map<String, Object?> storeArtifactState;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityReprobed': capabilityReprobed,
        'boundaryEvidence': boundaryEvidence,
        'cleanupConfirmed': cleanupConfirmed,
        'falseRestrictedClaim': falseRestrictedClaim,
        'outcomeReplayed': outcomeReplayed,
        'residualProcess': residualProcess,
        'scenario': scenario,
        'storeArtifactState': storeArtifactState,
      };
}

List<String> validateAgentSandboxCrashReport(
  AgentSandboxCrashReport report,
) =>
    <String>[
      if (report.falseRestrictedClaim) 'false-restricted-claim',
      if (report.residualProcess) 'residual-process',
      if (!report.cleanupConfirmed) 'cleanup-unconfirmed',
      if (report.outcomeReplayed) 'outcome-replayed',
      if (!report.capabilityReprobed) 'capability-not-reprobed',
      if (report.boundaryEvidence['phase'] != _boundaryPhases[report.scenario])
        'boundary-phase-mismatch',
    ];

Future<List<AgentSandboxCrashReport>> runAgentSandboxCrashMatrix(
  Iterable<String> scenarios,
) async {
  final reports = <AgentSandboxCrashReport>[];
  for (final scenario in scenarios) {
    if (!agentSandboxCrashScenarios.contains(scenario)) {
      throw ArgumentError.value(scenario, 'scenario');
    }
    reports.add(await runAgentSandboxCrashScenario(scenario));
  }
  return reports;
}

Future<AgentSandboxCrashReport> runAgentSandboxCrashScenario(
  String scenario, {
  AgentSandboxCrashMutation mutation = AgentSandboxCrashMutation.none,
  Directory? workspaceRoot,
}) async {
  final root = workspaceRoot ?? Directory.current.absolute;
  final temporary = Directory.systemTemp.createTempSync(
    'pigcode-agent-sandbox-crash-',
  );
  Process? child;
  try {
    child = await _startFixture(<String>[scenario, temporary.path], root);
    var boundary = await _killAtBoundary(
      child,
      temporary,
      scenario,
      scenario == 'restart-recovery-mid-capability-rebuild'
          ? 'restart-primary-crashed-before-recovery'
          : _boundaryPhases[scenario]!,
    );

    if (scenario == 'restart-recovery-mid-capability-rebuild') {
      final recovery = await _startFixture(<String>[
        '--recover',
        scenario,
        temporary.path,
        mutation.wireName,
        'inject-capability-boundary',
      ], root);
      boundary = await _killAtBoundary(
        recovery,
        temporary,
        scenario,
        _boundaryPhases[scenario]!,
      );
    }

    final recovery = await _startFixture(<String>[
      '--recover',
      scenario,
      temporary.path,
      mutation.wireName,
      'complete',
    ], root);
    final recoveryErrors = recovery.stderr.transform(utf8.decoder).join();
    final recoveryOutput = recovery.stdout.drain<void>();
    final recoveryExit = await recovery.exitCode.timeout(_deadline);
    await recoveryOutput;
    if (recoveryExit != 0) {
      throw StateError(
        'Recovery Host failed for $scenario: ${await recoveryErrors}',
      );
    }

    final state = _readJson(
      File('${temporary.path}/store-artifact.json'),
    );
    final recovered = _readJson(
      File('${temporary.path}/recovery-artifact.json'),
    );
    _verifyBoundaryEvidence(temporary, scenario, boundary, state);
    final sandboxEvidenceFile = File('${temporary.path}/sandbox-evidence.json');
    final sandboxAppliedEvidence = sandboxEvidenceFile.existsSync()
        ? _readJson(sandboxEvidenceFile)
        : null;
    final restrictedClaim = recovered['effectiveRestrictedClaim']! as bool;
    final sandboxActuallyApplied = state['sandboxApplied'] == true &&
        sandboxAppliedEvidence?['phase'] == 'sandbox-ready-observed';
    final before = recovered['capabilityBefore']! as Map<String, Object?>;
    final after = recovered['capabilityAfter']! as Map<String, Object?>;
    final productionRecovery =
        (recovered['productionRecoveryResults']! as List<Object?>)
            .cast<Map<String, Object?>>();
    final productionCleanupConfirmed = productionRecovery.every(
      (result) =>
          result['status'] == ProcessRecoveryStatus.cleaned.name ||
          result['status'] == ProcessRecoveryStatus.alreadyExited.name,
    );
    final report = AgentSandboxCrashReport(
      scenario: scenario,
      falseRestrictedClaim: restrictedClaim && !sandboxActuallyApplied,
      residualProcess: recovered['processAliveAfter']! as bool,
      cleanupConfirmed: productionCleanupConfirmed &&
          recovered['cleanupLedgerPendingAfter'] == 0 &&
          recovered['processAliveAfter'] == false,
      outcomeReplayed: (recovered['effectCountAfter']! as int) >
          (recovered['effectCountBefore']! as int),
      capabilityReprobed: _capabilityWasReprobed(before, after),
      boundaryEvidence: Map<String, Object?>.unmodifiable(boundary),
      storeArtifactState: Map<String, Object?>.unmodifiable(state),
    );
    await _emergencyCleanup(temporary);
    return report;
  } finally {
    child?.kill(ProcessSignal.sigkill);
    await _emergencyCleanup(temporary);
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  }
}

Future<Process> _startFixture(
  List<String> arguments,
  Directory workspaceRoot,
) =>
    Process.start(
      Platform.resolvedExecutable,
      <String>[
        File.fromUri(workspaceRoot.uri.resolve(_fixturePath)).path,
        ...arguments,
      ],
      workingDirectory: workspaceRoot.path,
      runInShell: false,
    );

Future<Map<String, Object?>> _killAtBoundary(
  Process child,
  Directory temporary,
  String scenario,
  String expectedPhase,
) async {
  final stderrBuffer = StringBuffer();
  child.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
  final lines = StreamIterator<String>(
    child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    final reached = await lines.moveNext().timeout(_deadline);
    final parts = reached ? lines.current.split(' ') : const <String>[];
    if (parts.length != 3 || parts[0] != 'BOUNDARY' || parts[1] != scenario) {
      throw StateError(
        'Crash fixture missed $scenario boundary: '
        '${reached ? lines.current : '<closed>'} $stderrBuffer',
      );
    }
    final evidence = _readJson(
      File('${temporary.path}/boundary-evidence.json'),
    );
    if (evidence['evidenceId'] != parts[2] ||
        evidence['scenario'] != scenario ||
        evidence['phase'] != expectedPhase ||
        evidence['observerPid'] != child.pid) {
      throw StateError('Boundary evidence did not bind the observed process.');
    }
    child.kill(ProcessSignal.sigkill);
    await child.exitCode.timeout(_deadline);
    return evidence;
  } finally {
    await lines.cancel();
  }
}

void _verifyBoundaryEvidence(
  Directory root,
  String scenario,
  Map<String, Object?> boundary,
  Map<String, Object?> state,
) {
  final details = boundary['details']! as Map<String, Object?>;
  switch (scenario) {
    case 'probe-before-after':
      if (details['secondProbeCommitted'] != false) {
        throw StateError('Probe boundary was not between probes.');
      }
    case 'sandbox-setup-before-apply':
      if (details['ledgerExists'] != false ||
          File('${root.path}/sandbox-evidence.json').existsSync()) {
        throw StateError('Sandbox setup boundary occurred after apply.');
      }
    case 'sandbox-after-apply-before-exec':
      if (details['targetExecObserved'] != false ||
          details['ledgerRecord'] is! Map<String, Object?>) {
        throw StateError('Sandbox-ready boundary lacked handshake evidence.');
      }
    case 'effect-before-execution':
      if (details['workerExecObserved'] != true ||
          details['effectCount'] != 0) {
        throw StateError('Effect-before boundary was not before execution.');
      }
    case 'effect-mid-execution':
      final worker = details['workerState']! as Map<String, Object?>;
      if (details['effectCount'] != 1 || worker['phase'] != 'started') {
        throw StateError('Mid-effect boundary lacked running evidence.');
      }
    case 'effect-after-execution-before-outcome':
      if (details['effectCount'] != 1 ||
          details['journalOutcome'] != 'unknown') {
        throw StateError('Post-effect boundary had a durable outcome.');
      }
    case 'outcome-after-write-before-receipt':
      if (details['effectCount'] != 1 ||
          details['receiptWritten'] != false ||
          state['outcome'] != 'completed') {
        throw StateError('Outcome boundary lacked durable outcome evidence.');
      }
    case 'cleanup-after-cancel-before-confirm':
      if (details['ledgerPending'] != true ||
          details['processIdentity'] == null) {
        throw StateError('Cancel boundary lacked pending cleanup evidence.');
      }
    case 'cleanup-after-confirm-before-record':
      if (details['kernelCleanupConfirmed'] != true ||
          details['ledgerPending'] != true) {
        throw StateError(
            'Cleanup boundary was not between confirm and record.');
      }
    case 'restart-recovery-mid-capability-rebuild':
      final before = details['capabilityBefore']! as Map<String, Object?>;
      final after = details['capabilityAfterProbe']! as Map<String, Object?>;
      if (before['probePid'] == after['probePid']) {
        throw StateError('Recovery did not perform a fresh capability probe.');
      }
  }
}

bool _capabilityWasReprobed(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  if (before['probePid'] == after['probePid'] ||
      before['observedAtMicros'] == after['observedAtMicros']) {
    return false;
  }
  final current = _probeCurrentCapability();
  return after['backend'] == current.backend &&
      after['platform'] == current.platform.name &&
      after['available'] == current.available &&
      after['minimumSatisfied'] == current.minimumSatisfied &&
      after['productionReady'] == current.productionReady &&
      after['landlockAbi'] == current.landlockAbi &&
      after['seccompSupported'] == current.seccompSupported &&
      after['sandboxExecPresent'] == current.sandboxExecPresent;
}

Future<void> _emergencyCleanup(Directory root) async {
  final stateFile = File('${root.path}/store-artifact.json');
  if (!stateFile.existsSync()) return;
  final state = _readJson(stateFile);
  final pgid = state['pgid'] as int?;
  final expectedIdentity = state['processIdentity'] as String?;
  if (pgid != null && ProcessGroup.captureIdentity(pgid) == expectedIdentity) {
    await ProcessGroup(pgid).cleanup().timeout(_deadline);
  }
  final recoveryFile = File('${root.path}/recovery-artifact.json');
  if (recoveryFile.existsSync()) {
    final recovery = _readJson(recoveryFile);
    final residualPid = recovery['mutationResidualPid'] as int?;
    final residualIdentity = recovery['mutationResidualIdentity'] as String?;
    if (residualPid != null &&
        ProcessGroup.captureIdentity(residualPid) == residualIdentity) {
      Process.killPid(residualPid, ProcessSignal.sigkill);
    }
  }
  final ledgerPath = state['cleanupLedgerPath'] as String?;
  final sessionIdentity = state['sessionIdentity'] as String?;
  if (ledgerPath == null || sessionIdentity == null) return;
  final ledger = ProcessCleanupLedger(ledgerPath);
  for (final record in await ledger.pending(sessionIdentity)) {
    if (ProcessGroup.captureIdentity(record.processGroupId) == null) {
      await ledger.confirm(record);
    }
  }
}

Map<String, Object?> _readJson(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

SandboxCapabilityReport _probeCurrentCapability() {
  if (Platform.isMacOS) return SeatbeltSandboxBackend().probe();
  return LandlockSeccompSandboxBackend().probe();
}
