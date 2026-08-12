import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 5 && arguments[0] == '--recover') {
    await _recoverHost(
      arguments[1],
      Directory(arguments[2]),
      arguments[3],
      injectCapabilityBoundary: arguments[4] == 'inject-capability-boundary',
    );
    return;
  }
  if (arguments.length != 2) {
    exitCode = 64;
    return;
  }
  final scenario = arguments[0];
  final root = Directory(arguments[1]);
  await root.create(recursive: true);
  final hostDataDirectory = '${root.path}/host-data';
  final sessionIdentity = 'crash-matrix-$scenario';
  final recovery = ProcessRecoveryCoordinator(hostDataDirectory);
  final state = <String, Object?>{
    'cleanupLedgerPath': recovery.ledgerPathFor(sessionIdentity),
    'hostDataDirectory': hostDataDirectory,
    'outcome': 'unknown',
    'pgid': null,
    'processIdentity': null,
    'restrictedClaim': false,
    'sandboxApplied': false,
    'scenario': scenario,
    'sessionIdentity': sessionIdentity,
  };
  state['capabilityBefore'] = _capabilitySnapshot();
  await _writeState(root, state);
  await _appendJournal(root, <String, Object?>{
    'event': 'host-started',
    'outcome': 'unknown',
    'scenario': scenario,
  });

  if (scenario == 'probe-before-after') {
    await _boundary(root, scenario, 'probe-before-after', <String, Object?>{
      'capabilityBefore': state['capabilityBefore'],
      'secondProbeCommitted': false,
    });
  }

  if (scenario == 'restart-recovery-mid-capability-rebuild') {
    await _appendJournal(root, <String, Object?>{
      'event': 'recovery-required',
      'outcome': 'unknown',
    });
    await _boundary(
      root,
      scenario,
      'restart-primary-crashed-before-recovery',
      <String, Object?>{'capabilityBefore': state['capabilityBefore']},
    );
  }

  late final SandboxedProcessLauncher launcher;
  final observer = (
    SandboxStartupPhase phase,
    Map<String, Object?> evidence,
  ) async {
    if (phase == SandboxStartupPhase.sandboxSetupPreparedBeforeApply &&
        scenario == 'sandbox-setup-before-apply') {
      await _writeState(root, state);
      await _boundary(
        root,
        scenario,
        'profile-validated-before-apply',
        <String, Object?>{
          'ledgerExists':
              File(state['cleanupLedgerPath']! as String).existsSync(),
          'startupEvidence': evidence,
        },
      );
    }
    if (phase == SandboxStartupPhase.sandboxAppliedBeforeExecAck) {
      final pending = await ProcessCleanupLedger(
        state['cleanupLedgerPath']! as String,
      ).pending(state['sessionIdentity']! as String);
      if (pending.length != 1) {
        throw StateError('Sandbox apply must have one write-ahead PGID.');
      }
      final record = pending.single;
      state
        ..['pgid'] = record.processGroupId
        ..['processIdentity'] = record.processIdentity
        ..['restrictedClaim'] = true
        ..['sandboxApplied'] = true;
      await _writeJson(
        File('${root.path}/sandbox-evidence.json'),
        <String, Object?>{
          'controlFrame': evidence,
          'phase': 'sandbox-ready-observed',
          'pgid': record.processGroupId,
          'processIdentity': record.processIdentity,
        },
      );
      await _writeState(root, state);
      if (scenario == 'sandbox-after-apply-before-exec') {
        await _boundary(
          root,
          scenario,
          'sandbox-ready-before-exec-ack',
          <String, Object?>{
            'ledgerRecord': record.toJson(),
            'sandboxControlFrame': evidence,
            'targetExecObserved': false,
          },
        );
      }
    }
  };
  final backend = Platform.isMacOS
      ? SeatbeltSandboxBackend(startupObserver: observer)
      : LandlockSeccompSandboxBackend(startupObserver: observer);
  launcher = SandboxedProcessLauncher(
    backend,
    hostDataDirectory: hostDataDirectory,
    sessionIdentity: sessionIdentity,
  );
  final process = await launcher.launch(
    _policy(root),
    HostCommand(
      executable: Platform.resolvedExecutable,
      arguments: <String>[
        File(
          'tool/fixtures/agent_sandbox_effect_worker.dart',
        ).absolute.path,
        root.path,
      ],
      workingDirectory: root.path,
    ),
  );
  state
    ..['pgid'] = process.processGroupId
    ..['processIdentity'] = ProcessGroup.captureIdentity(process.processGroupId)
    ..['restrictedClaim'] = process.capability.productionReady
    ..['sandboxApplied'] = true;
  await _writeState(root, state);
  final workerErrors = process.stderr.transform(utf8.decoder).join();
  final worker = StreamIterator<String>(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  if (!await worker.moveNext().timeout(const Duration(seconds: 3)) ||
      worker.current != 'WORKER_READY') {
    throw StateError(
      'Sandbox target exec was not externally observed: '
      '${await workerErrors.timeout(const Duration(seconds: 1))}',
    );
  }
  await _appendJournal(root, <String, Object?>{
    'event': 'effect-proposed',
    'outcome': 'unknown',
  });

  if (scenario == 'effect-before-execution') {
    await _boundary(
      root,
      scenario,
      'journal-unknown-before-effect',
      <String, Object?>{
        'effectCount': _effectCount(root),
        'workerExecObserved': true,
      },
    );
  }
  if (scenario == 'effect-mid-execution' ||
      scenario == 'effect-after-execution-before-outcome' ||
      scenario == 'outcome-after-write-before-receipt') {
    process.stdin.writeln('EXECUTE');
    await process.stdin.flush();
    await _expectWorkerLine(worker, 'EFFECT_STARTED');
  }
  if (scenario == 'effect-mid-execution') {
    await _boundary(
      root,
      scenario,
      'side-effect-started-before-completion',
      <String, Object?>{
        'effectCount': _effectCount(root),
        'workerState': _readJson(File('${root.path}/worker-state.json')),
      },
    );
  }
  if (scenario == 'effect-after-execution-before-outcome' ||
      scenario == 'outcome-after-write-before-receipt') {
    process.stdin.writeln('FINISH');
    await process.stdin.flush();
    await _expectWorkerLine(worker, 'EFFECT_COMPLETED');
  }
  if (scenario == 'effect-after-execution-before-outcome') {
    await _boundary(
      root,
      scenario,
      'effect-completed-before-outcome',
      <String, Object?>{
        'effectCount': _effectCount(root),
        'journalOutcome': 'unknown',
      },
    );
  }
  if (scenario == 'outcome-after-write-before-receipt') {
    await _appendJournal(root, <String, Object?>{
      'event': 'effect-outcome-written',
      'outcome': 'completed',
    });
    state['outcome'] = 'completed';
    await _writeState(root, state);
    await _boundary(
      root,
      scenario,
      'outcome-durable-before-receipt',
      <String, Object?>{
        'effectCount': _effectCount(root),
        'receiptWritten': false,
      },
    );
  }
  if (scenario == 'cleanup-after-cancel-before-confirm') {
    await _appendJournal(root, <String, Object?>{
      'event': 'cancel-requested',
      'outcome': 'unknown',
    });
    Process.killPid(-process.pid, ProcessSignal.sigterm);
    await _boundary(
      root,
      scenario,
      'cancel-signal-before-cleanup-confirmation',
      <String, Object?>{
        'ledgerPending': true,
        'processIdentity': state['processIdentity'],
      },
    );
  }
  if (scenario == 'cleanup-after-confirm-before-record') {
    final cleanup = await ProcessGroup(process.pid).cleanup();
    if (!cleanup.confirmed ||
        ProcessGroup.captureIdentity(process.pid) != null) {
      throw StateError('Cleanup was not confirmed before the boundary.');
    }
    await _boundary(
      root,
      scenario,
      'process-dead-before-ledger-confirmation',
      <String, Object?>{
        'kernelCleanupConfirmed': cleanup.confirmed,
        'ledgerPending': true,
      },
    );
  }
  throw StateError('Scenario did not define a crash boundary: $scenario');
}

SandboxPolicy _policy(Directory root) => SandboxPolicy(
      roots: <SandboxPathRule>[
        SandboxPathRule(
          path: root.path,
          access: SandboxPathAccess.readWrite,
        ),
        SandboxPathRule(
          path: Directory.current.absolute.path,
          access: SandboxPathAccess.readOnly,
        ),
        SandboxPathRule(
          path: File(Platform.resolvedExecutable).parent.path,
          access: SandboxPathAccess.readOnly,
        ),
      ],
    );

Future<void> _recoverHost(
  String scenario,
  Directory root,
  String mutation, {
  required bool injectCapabilityBoundary,
}) async {
  final state = _readJson(File('${root.path}/store-artifact.json'));
  final capabilityBefore = state['capabilityBefore']! as Map<String, Object?>;
  final capabilityAfter =
      mutation == 'reuse-capability-snapshot' && !injectCapabilityBoundary
          ? Map<String, Object?>.from(capabilityBefore)
          : _capabilitySnapshot();
  if (injectCapabilityBoundary) {
    await _boundary(
      root,
      scenario,
      'fresh-probe-before-capability-commit',
      <String, Object?>{
        'capabilityAfterProbe': capabilityAfter,
        'capabilityBefore': capabilityBefore,
      },
    );
  }

  final countBefore = _effectCount(root);
  final journal = await _readJournal(root);
  final outcome =
      journal.map((event) => event['outcome']).whereType<String>().lastOrNull;
  if (mutation == 'replay-unknown-outcome' && outcome == 'unknown') {
    await File('${root.path}/side-effect-count.txt')
        .writeAsString('${countBefore + 1}', flush: true);
  }

  final ledger = ProcessCleanupLedger(state['cleanupLedgerPath']! as String);
  final sessionIdentity = state['sessionIdentity']! as String;
  final beforeRecords = await ledger.pending(sessionIdentity);
  final recovery = await ProcessRecoveryCoordinator(
    state['hostDataDirectory']! as String,
  ).recoverPending();
  if (!recovery.confirmed) {
    throw StateError('production process recovery was not confirmed');
  }
  final recoveredGroups = <int>{
    for (final result in recovery.results) result.record.processGroupId,
  };
  for (final record in beforeRecords) {
    if (!recoveredGroups.contains(record.processGroupId)) {
      throw StateError('production recovery omitted a pending ledger record');
    }
  }
  final afterRecords = await ledger.pending(sessionIdentity);
  final pgid = state['pgid'] as int?;
  final expectedIdentity = state['processIdentity'] as String?;
  final currentIdentity =
      pgid == null ? null : ProcessGroup.captureIdentity(pgid);
  int? mutationResidualPid;
  String? mutationResidualIdentity;
  if (mutation == 'leave-residual-process') {
    final residual = await Process.start(
      '/bin/sleep',
      const <String>['30'],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    mutationResidualPid = residual.pid;
    mutationResidualIdentity = await _waitForIdentity(residual.pid);
  }
  await _writeJson(
    File('${root.path}/recovery-artifact.json'),
    <String, Object?>{
      'capabilityAfter': capabilityAfter,
      'capabilityBefore': capabilityBefore,
      'cleanupLedgerPendingAfter': afterRecords.length,
      'cleanupLedgerPendingBefore': beforeRecords.length,
      'effectCountAfter': _effectCount(root),
      'effectCountBefore': countBefore,
      'effectiveRestrictedClaim': mutation == 'claim-restricted-without-apply'
          ? true
          : state['restrictedClaim'],
      'expectedProcessIdentity': expectedIdentity,
      'journalEvents': journal,
      'mutationResidualIdentity': mutationResidualIdentity,
      'mutationResidualPid': mutationResidualPid,
      'outcome': outcome,
      'processAliveAfter':
          (currentIdentity != null && currentIdentity == expectedIdentity) ||
              mutationResidualIdentity != null,
      'productionRecoveryResults': <Map<String, Object?>>[
        for (final result in recovery.results)
          <String, Object?>{
            'pgid': result.record.processGroupId,
            'status': result.status.name,
          },
      ],
      'recoveryPid': pid,
      'scenario': scenario,
    },
  );
}

Future<String?> _waitForIdentity(int processId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  do {
    final identity = ProcessGroup.captureIdentity(processId);
    if (identity != null) return identity;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  } while (DateTime.now().isBefore(deadline));
  return null;
}

Map<String, Object?> _capabilitySnapshot() {
  final report = Platform.isMacOS
      ? SeatbeltSandboxBackend().probe()
      : LandlockSeccompSandboxBackend().probe();
  return <String, Object?>{
    'available': report.available,
    'backend': report.backend,
    'landlockAbi': report.landlockAbi,
    'minimumSatisfied': report.minimumSatisfied,
    'observedAtMicros': DateTime.now().microsecondsSinceEpoch,
    'platform': report.platform.name,
    'probePid': pid,
    'productionReady': report.productionReady,
    'sandboxExecPresent': report.sandboxExecPresent,
    'seccompSupported': report.seccompSupported,
  };
}

Future<void> _expectWorkerLine(
  StreamIterator<String> worker,
  String expected,
) async {
  if (!await worker.moveNext().timeout(const Duration(seconds: 3)) ||
      worker.current != expected) {
    throw StateError('Expected worker line $expected.');
  }
}

Future<void> _boundary(
  Directory root,
  String scenario,
  String phase,
  Map<String, Object?> details,
) async {
  final evidenceId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  await _writeJson(
    File('${root.path}/boundary-evidence.json'),
    <String, Object?>{
      'details': details,
      'evidenceId': evidenceId,
      'observerPid': pid,
      'phase': phase,
      'scenario': scenario,
    },
  );
  stdout.writeln('BOUNDARY $scenario $evidenceId');
  await stdout.flush();
  await Completer<void>().future;
}

Future<void> _appendJournal(
  Directory root,
  Map<String, Object?> event,
) async {
  final sink =
      File('${root.path}/host-journal.jsonl').openWrite(mode: FileMode.append);
  sink.writeln(jsonEncode(event));
  await sink.flush();
  await sink.close();
}

Future<List<Map<String, Object?>>> _readJournal(Directory root) async {
  final file = File('${root.path}/host-journal.jsonl');
  if (!await file.exists()) return <Map<String, Object?>>[];
  return file
      .readAsLinesSync()
      .where((line) => line.isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, Object?>)
      .toList(growable: false);
}

int _effectCount(Directory root) {
  final file = File('${root.path}/side-effect-count.txt');
  if (!file.existsSync()) return 0;
  return int.parse(file.readAsStringSync().trim());
}

Future<void> _writeState(
  Directory root,
  Map<String, Object?> state,
) =>
    _writeJson(File('${root.path}/store-artifact.json'), state);

Future<void> _writeJson(File file, Map<String, Object?> value) async {
  final temporary = File('${file.path}.tmp.$pid');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

Map<String, Object?> _readJson(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
