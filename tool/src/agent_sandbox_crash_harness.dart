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
const _watchdogInterval = Duration(milliseconds: 100);
const _crashScenarioHardBudget = Duration(minutes: 2);
const _boundaryInactivityBudget = Duration(seconds: 45);
const _recoveryInactivityBudget = Duration(seconds: 30);
const _processExitInactivityBudget = Duration(seconds: 15);
const _outputDrainInactivityBudget = Duration(seconds: 10);

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

final class AgentSandboxCrashTimeout implements Exception {
  const AgentSandboxCrashTimeout({
    required this.scenario,
    required this.stage,
    required this.lastObservedPhase,
    required this.elapsed,
    required this.inactiveFor,
    required this.progress,
    required this.reason,
  });

  final String scenario;
  final String stage;
  final String lastObservedPhase;
  final Duration elapsed;
  final Duration inactiveFor;
  final Map<String, Object?> progress;
  final String reason;

  @override
  String toString() => 'AgentSandboxCrashTimeout('
      'scenario=$scenario, stage=$stage, reason=$reason, '
      'lastObservedPhase=$lastObservedPhase, elapsed=$elapsed, '
      'inactiveFor=$inactiveFor, progress=${jsonEncode(progress)})';
}

final class _CrashProgressWatchdog {
  _CrashProgressWatchdog(this.scenario, this.root)
      : _lastProgress = _describeCrashProgress(root),
        _scenarioElapsed = (Stopwatch()..start()),
        _inactiveFor = (Stopwatch()..start()) {
    _fingerprint = jsonEncode(_lastProgress);
  }

  final String scenario;
  final Directory root;
  final Stopwatch _scenarioElapsed;
  final Stopwatch _inactiveFor;
  late String _fingerprint;
  Map<String, Object?> _lastProgress;

  Future<T> waitFor<T>(
    Future<T> operation, {
    required String stage,
    required Duration inactivityBudget,
  }) {
    _recordCurrentProgress();
    _inactiveFor.reset();
    final timeout = Completer<T>();
    final timer = Timer.periodic(_watchdogInterval, (_) {
      if (timeout.isCompleted) return;
      _recordCurrentProgress();
      final hardExpired = _scenarioElapsed.elapsed >= _crashScenarioHardBudget;
      final inactive = _inactiveFor.elapsed >= inactivityBudget;
      if (!hardExpired && !inactive) return;
      timeout.completeError(
        AgentSandboxCrashTimeout(
          scenario: scenario,
          stage: stage,
          lastObservedPhase: _lastObservedPhase(_lastProgress),
          elapsed: _scenarioElapsed.elapsed,
          inactiveFor: _inactiveFor.elapsed,
          progress: Map<String, Object?>.unmodifiable(_lastProgress),
          reason: hardExpired ? 'scenario-hard-deadline' : 'stage-inactivity',
        ),
      );
    });
    return Future.any<T>(<Future<T>>[operation, timeout.future])
        .whenComplete(timer.cancel);
  }

  void _recordCurrentProgress() {
    final progress = _describeCrashProgress(root);
    final fingerprint = jsonEncode(progress);
    if (fingerprint == _fingerprint) return;
    _fingerprint = fingerprint;
    _lastProgress = progress;
    _inactiveFor.reset();
  }
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
  final watchdog = _CrashProgressWatchdog(scenario, temporary);
  final children = <Process>[];
  try {
    final child = await _startFixture(<String>[
      scenario,
      temporary.path,
    ], root);
    children.add(child);
    var boundary = await _killAtBoundary(
      child,
      temporary,
      scenario,
      scenario == 'restart-recovery-mid-capability-rebuild'
          ? 'restart-primary-crashed-before-recovery'
          : _boundaryPhases[scenario]!,
      watchdog,
    );

    if (scenario == 'restart-recovery-mid-capability-rebuild') {
      final recovery = await _startFixture(<String>[
        '--recover',
        scenario,
        temporary.path,
        mutation.wireName,
        'inject-capability-boundary',
      ], root);
      children.add(recovery);
      boundary = await _killAtBoundary(
        recovery,
        temporary,
        scenario,
        _boundaryPhases[scenario]!,
        watchdog,
      );
    }

    final recovery = await _startFixture(<String>[
      '--recover',
      scenario,
      temporary.path,
      mutation.wireName,
      'complete',
    ], root);
    children.add(recovery);
    final recoveryErrors = recovery.stderr.transform(utf8.decoder).join();
    final recoveryOutput = recovery.stdout.drain<void>();
    final recoveryExit = await watchdog.waitFor(
      recovery.exitCode,
      stage: 'await-recovery-process-exit',
      inactivityBudget: _recoveryInactivityBudget,
    );
    await watchdog.waitFor(
      recoveryOutput,
      stage: 'drain-recovery-stdout',
      inactivityBudget: _outputDrainInactivityBudget,
    );
    final recoveryErrorText = await watchdog.waitFor(
      recoveryErrors,
      stage: 'drain-recovery-stderr',
      inactivityBudget: _outputDrainInactivityBudget,
    );
    if (recoveryExit != 0) {
      throw StateError(
        'Recovery Host failed for $scenario: $recoveryErrorText',
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
    for (final process in children) {
      process.kill(ProcessSignal.sigkill);
    }
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
  _CrashProgressWatchdog watchdog,
) async {
  final stderrBuffer = StringBuffer();
  child.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
  final lines = StreamIterator<String>(
    child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    final reached = await watchdog.waitFor(
      Future.any<bool>(<Future<bool>>[
        lines.moveNext(),
        child.exitCode.then<bool>(
          (exitCode) => throw StateError(
            'Crash fixture exited $exitCode before $expectedPhase: '
            '$stderrBuffer progress=${_describeCrashProgress(temporary)}',
          ),
        ),
      ]),
      stage: 'await-boundary:$expectedPhase',
      inactivityBudget: _boundaryInactivityBudget,
    );
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
    await watchdog.waitFor(
      child.exitCode,
      stage: 'await-crashed-process-exit:$expectedPhase',
      inactivityBudget: _processExitInactivityBudget,
    );
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
    await ProcessGroup(pgid).cleanup();
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

Map<String, Object?> _describeCrashProgress(Directory root) {
  final artifacts = <String, Object?>{};
  for (final name in <String>[
    'store-artifact.json',
    'sandbox-evidence.json',
    'worker-state.json',
    'boundary-evidence.json',
  ]) {
    final file = File('${root.path}/$name');
    if (!file.existsSync()) continue;
    try {
      artifacts[name] = _readJson(file);
    } on Object catch (error) {
      artifacts[name] = 'unreadable: $error';
    }
  }
  final journal = File('${root.path}/host-journal.jsonl');
  if (journal.existsSync()) {
    try {
      artifacts['host-journal.jsonl'] = journal.readAsLinesSync();
    } on Object catch (error) {
      artifacts['host-journal.jsonl'] = 'unreadable: $error';
    }
  }
  final cleanup = Directory('${root.path}/host-data/process-cleanup');
  if (cleanup.existsSync()) {
    final entries = cleanup
        .listSync(followLinks: false)
        .whereType<File>()
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    artifacts['process-cleanup'] = <String, Object?>{
      for (final file in entries)
        file.uri.pathSegments.last: _readProgressFile(file),
    };
  }
  return artifacts;
}

Object? _readProgressFile(File file) {
  try {
    final contents = file.readAsStringSync();
    try {
      return jsonDecode(contents);
    } on FormatException {
      return contents;
    }
  } on Object catch (error) {
    return 'unreadable: $error';
  }
}

String _lastObservedPhase(Map<String, Object?> progress) {
  final recovery = progress['recovery-artifact.json'];
  if (recovery is Map<String, Object?>) return 'recovery-artifact-written';
  final boundary = progress['boundary-evidence.json'];
  if (boundary is Map<String, Object?> && boundary['phase'] is String) {
    return boundary['phase']! as String;
  }
  final worker = progress['worker-state.json'];
  if (worker is Map<String, Object?> && worker['phase'] is String) {
    return 'worker-${worker['phase']}';
  }
  final sandbox = progress['sandbox-evidence.json'];
  if (sandbox is Map<String, Object?> && sandbox['phase'] is String) {
    return sandbox['phase']! as String;
  }
  final journal = progress['host-journal.jsonl'];
  if (journal is List<Object?> && journal.isNotEmpty) {
    try {
      final event = jsonDecode(journal.last! as String) as Map<String, Object?>;
      if (event['event'] is String) return event['event']! as String;
    } on Object {
      return 'journal-unreadable';
    }
  }
  if (progress.containsKey('store-artifact.json')) return 'store-initialized';
  return 'fixture-spawned';
}

SandboxCapabilityReport _probeCurrentCapability() {
  if (Platform.isMacOS) return SeatbeltSandboxBackend().probe();
  return LandlockSeccompSandboxBackend().probe();
}
