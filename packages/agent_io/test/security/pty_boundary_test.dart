import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import 'package:pigcode_ai_agent_io/src/sandbox/sandbox_startup_handshake.dart';
import '../support/workspace_path.dart';

void main() {
  final supported = Platform.isMacOS;

  test('P4-TM-PROC-02 PTY broker uses openpty + posix_spawn without a shell',
      () {
    expect(HostPtySession.platformBroker, 'openpty+posix_spawn');
    expect(HostPtySession.usesShell, isFalse);
  });

  test(
    'PTY parent durably records the group before releasing the child',
    () async {
      final temp = await Directory.systemTemp.createTemp('pty-write-ahead-');
      final ledgerPath = '${temp.path}/cleanup.json';
      const sessionIdentity = 'pty-parent-write-ahead';
      final targetStarted = File('${temp.path}/target-started');
      final writeAheadObserved = Completer<Map<String, Object?>>();
      final releaseObserver = Completer<void>();
      SandboxedProcess? process;
      var startCompleted = false;
      final launcher = SandboxedProcessLauncher.unsafeDev(
        SeatbeltSandboxBackend(),
        cleanupLedgerPath: ledgerPath,
        sessionIdentity: sessionIdentity,
        startupObserver: (phase, evidence) async {
          if (phase != SandboxStartupPhase.parentProcessWriteAheadReported) {
            return;
          }
          final records =
              await ProcessCleanupLedger(ledgerPath).pending(sessionIdentity);
          expect(records, hasLength(1));
          expect(records.single.processGroupId, evidence['pgid']);
          expect(records.single.processIdentity, evidence['identity']);
          expect(targetStarted.existsSync(), isFalse);
          writeAheadObserved.complete(evidence);
          await releaseObserver.future;
        },
      );
      final startup = HostPtySession(launcher)
          .start(
            _ptyPolicy(temp),
            HostCommand(
              executable: '/usr/bin/touch',
              arguments: <String>[targetStarted.path],
            ),
          )
          .whenComplete(() => startCompleted = true);
      unawaited(
        startup.then<void>(
          (_) {
            if (!writeAheadObserved.isCompleted) {
              writeAheadObserved.completeError(
                StateError('PTY start returned before parent write-ahead'),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!writeAheadObserved.isCompleted) {
              writeAheadObserved.completeError(error, stackTrace);
            }
          },
        ),
      );
      try {
        final evidence = await writeAheadObserved.future;
        expect(startCompleted, isFalse);
        expect(targetStarted.existsSync(), isFalse);
        expect(
          ProcessGroup.captureIdentity(evidence['pgid']! as int),
          evidence['identity'],
        );

        releaseObserver.complete();
        process = await startup;
        expect(await process.exitCode, 0);
        expect(targetStarted.existsSync(), isTrue);
        expect((await launcher.cleanup(process)).confirmed, isTrue);
      } finally {
        if (!releaseObserver.isCompleted) releaseObserver.complete();
        final active = process;
        if (active != null &&
            ProcessGroup.captureIdentity(active.processGroupId) != null) {
          try {
            await launcher.cleanup(active);
          } on Object {
            Process.killPid(-active.processGroupId, ProcessSignal.sigkill);
          }
        }
        await temp.delete(recursive: true);
      }
    },
    skip: supported
        ? false
        : 'SKIP-MANIFEST PTY write-ahead requires macOS posix_spawn',
  );

  test(
    'P4-TM-PTY-01 PTY command inherits kernel filesystem containment',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_pty_');
      try {
        final root = Directory('${temp.path}/root')..createSync();
        final outside = File('${temp.path}/secret')
          ..writeAsStringSync('pty-secret');
        final session = HostPtySession(
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend()),
        );
        final result = await session.run(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
            requiresPty: true,
          ),
          HostCommand(
            executable: '/bin/cat',
            arguments: <String>[outside.path],
          ),
        );
        expect(result.exitCode, isNot(0));
        expect(result.output, isNot(contains('pty-secret')));
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: supported
        ? false
        : 'SKIP-MANIFEST PTY boundary platform=${Platform.operatingSystem} '
            'sandbox-exec=${File('/usr/bin/sandbox-exec').existsSync()}',
  );

  test(
    'P4-TM-PTY-02 Host buffer bounds sandboxed and control PTY floods',
    () async {
      const outputLimit = 4096;
      final temp = Directory.systemTemp.createTempSync('pigcode_pty_');
      try {
        final control = await _runUnsandboxedFloodControl(outputLimit);
        expect(control.runningAtLimit, isTrue);
        expect(control.cleanupConfirmed, isTrue);
        expect(control.outputBytes, outputLimit);

        final sandboxed = await _runSandboxedFloodControl(
          temp,
          outputLimit,
        );
        expect(sandboxed.runningAtLimit, isTrue);
        expect(sandboxed.cleanupConfirmed, isTrue);
        expect(sandboxed.outputBytes, outputLimit);

        final bounded = await _runBoundedPtyOutput(temp, outputLimit);
        expect(bounded.timedOut, isFalse);
        expect(
          utf8.encode(bounded.output),
          hasLength(outputLimit),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: supported
        ? false
        : 'SKIP-MANIFEST PTY flood platform=${Platform.operatingSystem} '
            'sandbox-exec=${File('/usr/bin/sandbox-exec').existsSync()}',
  );

  test('P4-TM-PTY-03 PTY process is included in tree cleanup', () async {
    final temp = Directory.systemTemp.createTempSync('pigcode_pty_');
    try {
      final launcher =
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
      final session = HostPtySession(launcher);
      final process = await session.start(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: temp.path,
              access: SandboxPathAccess.readWrite,
            ),
          ],
          requiresPty: true,
        ),
        HostCommand(
          executable: '/bin/sleep',
          arguments: const <String>['30'],
        ),
      );
      final pid = process.processGroupId;
      final identity = ProcessGroup.captureIdentity(pid);
      expect(identity, isNotNull);
      expect((await launcher.cleanup(process)).confirmed, isTrue);
      await _expectIdentityGone(pid, identity!);
    } finally {
      temp.deleteSync(recursive: true);
    }
  },
      skip: supported
          ? false
          : 'SKIP-MANIFEST PTY cleanup platform=${Platform.operatingSystem} '
              'sandbox-exec=${File('/usr/bin/sandbox-exec').existsSync()}');

  test(
    'PTY group is durable before child release and recovery cleans Host crash',
    () async {
      final dataRoot = await Directory.systemTemp.createTemp('pty-data-');
      final workspace = await Directory.systemTemp.createTemp('pty-workspace-');
      final fixture = resolveTestWorkspacePath(
        packageRelative: 'test/fixtures/pty_crash_host.dart',
        workspaceRelative:
            'packages/agent_io/test/fixtures/pty_crash_host.dart',
      );
      final host = await Process.start(
        Platform.resolvedExecutable,
        <String>[fixture, dataRoot.path, workspace.path],
        runInShell: false,
      );
      final errors = host.stderr.transform(utf8.decoder).join();
      final lines = StreamIterator<String>(
        host.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      var processGroupId = -1;
      String? processIdentity;
      try {
        final hasReadyLine = await Future.any<bool>(<Future<bool>>[
          lines.moveNext(),
          host.exitCode.then<bool>((exitCode) async {
            throw StateError(
              'PTY crash host exited $exitCode before ready: ${await errors}',
            );
          }),
        ]);
        expect(
          hasReadyLine,
          isTrue,
          reason: hasReadyLine ? null : await errors,
        );
        final ready = jsonDecode(lines.current) as Map<String, Object?>;
        expect(ready['phase'], 'processGroupPersistedBeforeAck');
        processGroupId = ready['pgid']! as int;
        processIdentity = ProcessGroup.captureIdentity(processGroupId);
        expect(processIdentity, isNotNull);
        expect(
          File('${workspace.path}/released').existsSync(),
          isFalse,
          reason: 'target executed before durable-ledger ACK released child',
        );

        host.kill(ProcessSignal.sigkill);
        await host.exitCode.timeout(const Duration(seconds: 3));
        await _expectIdentityGone(processGroupId, processIdentity!);
        final coordinator = ProcessRecoveryCoordinator(dataRoot.path);
        final report = await coordinator
            .recoverPending()
            .timeout(const Duration(seconds: 8));
        expect(report.confirmed, isTrue);
        expect(
          report.results.single.status,
          ProcessRecoveryStatus.alreadyExited,
          reason:
              'broker must kill the suspended child when ACK channel closes',
        );
        await _expectIdentityGone(
          processGroupId,
          report.results.single.record.processIdentity,
        );
      } finally {
        host.kill(ProcessSignal.sigkill);
        if (processGroupId > 0 &&
            ProcessGroup.captureIdentity(processGroupId) != null) {
          Process.killPid(-processGroupId, ProcessSignal.sigkill);
        }
        await lines.cancel();
        await workspace.delete(recursive: true);
        await dataRoot.delete(recursive: true);
      }
    },
    skip: supported
        ? false
        : 'SKIP-MANIFEST PTY crash-window recovery requires macOS Seatbelt',
  );

  final linuxCapability = LandlockSeccompSandboxBackend().probe();
  final probedAbi4 = Platform.isLinux &&
      linuxCapability.productionReady &&
      linuxCapability.landlockAbi == 4;
  test(
    'P4-TM-PTY-04 runtime-probed ABI4 records ioctl unsupported',
    () {
      final report = PtyCapabilityReport.fromSandbox(
        linuxCapability,
      );
      expect(report.deviceIoctlRestricted, isFalse);
      expect(report.manifestStatus, 'unsupported-landlock-abi4');
    },
    skip: probedAbi4
        ? false
        : 'SKIP-MANIFEST PTY ioctl runtime-probe '
            'platform=${Platform.operatingSystem} '
            'backend=${linuxCapability.backend} '
            'abi=${linuxCapability.landlockAbi ?? 'missing'}',
  );

  final abi = linuxCapability.landlockAbi;
  final ioctlSupported = Platform.isLinux &&
      linuxCapability.productionReady &&
      abi != null &&
      abi >= 5;
  test(
    'P4-TM-PTY-04 Landlock ABI5 kernel denies device ioctl',
    () async {
      final root = Directory.systemTemp.createTempSync('pigcode_ioctl_');
      final hostData =
          Directory.systemTemp.createTempSync('pigcode_ioctl_host_');
      final launcher = SandboxedProcessLauncher(
        LandlockSeccompSandboxBackend(),
        hostDataDirectory: hostData.path,
        sessionIdentity: 'pty-ioctl-abi5',
      );
      SandboxedProcess? process;
      try {
        process = await launcher.launch(
          SandboxPolicy(
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
            requiresPty: true,
          ),
          HostCommand(
            executable: Platform.resolvedExecutable,
            arguments: <String>[
              resolveTestWorkspacePath(
                packageRelative: 'test/fixtures/ioctl_probe.dart',
                workspaceRelative:
                    'packages/agent_io/test/fixtures/ioctl_probe.dart',
              ),
            ],
          ),
        );
        process.stdout.drain<void>();
        process.stderr.drain<void>();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 8)),
          0,
        );
        expect((await launcher.cleanup(process)).confirmed, isTrue);
        process = null;
      } finally {
        final active = process;
        if (active != null) {
          try {
            await launcher.cleanup(active).timeout(const Duration(seconds: 3));
          } on Object {
            Process.killPid(-active.processGroupId, ProcessSignal.sigkill);
          }
        }
        root.deleteSync(recursive: true);
        hostData.deleteSync(recursive: true);
      }
    },
    skip: ioctlSupported
        ? false
        : 'SKIP-MANIFEST PTY ioctl platform=${Platform.operatingSystem} '
            'abi=${abi ?? 'missing'}',
  );
}

Future<_FloodControlResult> _runUnsandboxedFloodControl(
  int maxOutputBytes,
) async {
  final process = await Process.start(
    '/usr/bin/yes',
    const <String>[],
    runInShell: false,
  );
  final identity = ProcessGroup.captureIdentity(process.pid);
  if (identity == null) throw StateError('missing control process identity');
  final output = _BoundedFloodOutput(maxOutputBytes);
  final stdoutDone = process.stdout.listen(output.add).asFuture<void>();
  final stderrDone = process.stderr.drain<void>();
  try {
    await output.limitReached.timeout(const Duration(seconds: 3));
    final runningAtLimit =
        ProcessGroup.captureIdentity(process.pid) == identity;
    final killSent = process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 3));
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    await _expectIdentityGone(process.pid, identity);
    return _FloodControlResult(
      runningAtLimit: runningAtLimit,
      cleanupConfirmed: killSent,
      outputBytes: output.outputBytes,
    );
  } finally {
    if (ProcessGroup.captureIdentity(process.pid) == identity) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 3));
    }
  }
}

Future<_FloodControlResult> _runSandboxedFloodControl(
  Directory temp,
  int maxOutputBytes,
) async {
  final launcher = SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
  final process = await HostPtySession(launcher).start(
    _ptyPolicy(temp),
    HostCommand(executable: '/usr/bin/yes'),
  );
  final identity = ProcessGroup.captureIdentity(process.processGroupId);
  if (identity == null) throw StateError('missing sandboxed process identity');
  final output = _BoundedFloodOutput(maxOutputBytes);
  final stdoutDone = process.stdout.listen(output.add).asFuture<void>();
  final stderrDone = process.stderr.listen(output.add).asFuture<void>();
  try {
    await output.limitReached.timeout(const Duration(seconds: 3));
    final runningAtLimit =
        ProcessGroup.captureIdentity(process.processGroupId) == identity;
    final cleanup =
        await launcher.cleanup(process).timeout(const Duration(seconds: 3));
    await process.exitCode.timeout(const Duration(seconds: 3));
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    await _expectIdentityGone(process.processGroupId, identity);
    return _FloodControlResult(
      runningAtLimit: runningAtLimit,
      cleanupConfirmed: cleanup.confirmed,
      outputBytes: output.outputBytes,
    );
  } finally {
    if (ProcessGroup.captureIdentity(process.processGroupId) == identity) {
      try {
        await launcher.cleanup(process).timeout(const Duration(seconds: 3));
      } on Object {
        Process.killPid(-process.processGroupId, ProcessSignal.sigkill);
      }
    }
  }
}

Future<PtyRunResult> _runBoundedPtyOutput(
  Directory temp,
  int maxOutputBytes,
) async {
  int? processGroupId;
  String? processIdentity;
  final launcher = SandboxedProcessLauncher.unsafeDev(
    SeatbeltSandboxBackend(),
    startupObserver: (_, evidence) async {
      if (evidence['type'] != 'group-ready') return;
      processGroupId = evidence['pgid']! as int;
      processIdentity = evidence['identity']! as String;
    },
  );
  try {
    final result = await HostPtySession(
      launcher,
      maxOutputBytes: maxOutputBytes,
    ).run(
      _ptyPolicy(temp),
      HostCommand(
        executable: '/usr/bin/printf',
        arguments: <String>[
          '%s',
          List<String>.filled(maxOutputBytes * 2, 'x').join(),
        ],
      ),
    );
    final groupId = processGroupId;
    final identity = processIdentity;
    if (groupId == null || identity == null) {
      throw StateError('missing bounded PTY process identity');
    }
    final cleanup = await launcher.cleanupRecorded(groupId);
    expect(cleanup.confirmed, isTrue);
    await _expectIdentityGone(groupId, identity);
    return result;
  } finally {
    final groupId = processGroupId;
    final identity = processIdentity;
    if (groupId != null &&
        identity != null &&
        ProcessGroup.captureIdentity(groupId) == identity) {
      try {
        await launcher
            .cleanupRecorded(groupId)
            .timeout(const Duration(seconds: 3));
      } on Object {
        Process.killPid(-groupId, ProcessSignal.sigkill);
      }
    }
  }
}

SandboxPolicy _ptyPolicy(Directory temp) => SandboxPolicy(
      roots: <SandboxPathRule>[
        SandboxPathRule(
          path: temp.path,
          access: SandboxPathAccess.readWrite,
        ),
      ],
      requiresPty: true,
    );

final class _BoundedFloodOutput {
  _BoundedFloodOutput(this.limit);

  final int limit;
  final Completer<void> _limitReached = Completer<void>();
  int outputBytes = 0;

  Future<void> get limitReached => _limitReached.future;

  void add(List<int> chunk) {
    outputBytes += math.min(chunk.length, limit - outputBytes);
    if (outputBytes == limit && !_limitReached.isCompleted) {
      _limitReached.complete();
    }
  }
}

Future<void> _expectIdentityGone(int pid, String identity) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final current = ProcessGroup.captureIdentity(pid);
    if (current == null || current != identity) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(
    ProcessGroup.captureIdentity(pid),
    isNot(identity),
    reason: 'PTY pid=$pid retained kernel identity=$identity after cleanup',
  );
}

final class _FloodControlResult {
  const _FloodControlResult({
    required this.runningAtLimit,
    required this.cleanupConfirmed,
    required this.outputBytes,
  });

  final bool runningAtLimit;
  final bool cleanupConfirmed;
  final int outputBytes;
}
