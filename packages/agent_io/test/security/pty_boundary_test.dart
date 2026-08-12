import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

void main() {
  final supported = Platform.isMacOS;

  test('P4-TM-PROC-02 PTY broker is forkpty and never invokes a shell', () {
    expect(HostPtySession.platformBroker, 'forkpty');
    expect(HostPtySession.usesShell, isFalse);
  });

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
      final temp = Directory.systemTemp.createTempSync('pigcode_pty_');
      try {
        final control = await _runUnsandboxedFloodControl(
          const Duration(milliseconds: 400),
          4096,
        );
        expect(control.timedOut, isTrue);
        expect(control.outputBytes, lessThanOrEqualTo(4096));

        final session = HostPtySession(
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend()),
          maxOutputBytes: 4096,
        );
        final result = await session.run(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: temp.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
            requiresPty: true,
          ),
          HostCommand(executable: '/usr/bin/yes'),
          executionTimeout: const Duration(milliseconds: 400),
        );
        expect(
          result.timedOut,
          isTrue,
          reason: 'exit=${result.exitCode} output=${result.output}',
        );
        expect(result.output.length, lessThanOrEqualTo(4096));
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
    'PTY group is durable before ACK and production recovery cleans Host crash',
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
      try {
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 8)),
          isTrue,
          reason: await errors.timeout(
            const Duration(milliseconds: 1),
            onTimeout: () => '',
          ),
        );
        final ready = jsonDecode(lines.current) as Map<String, Object?>;
        expect(ready['phase'], 'processGroupPersistedBeforeAck');
        processGroupId = ready['pgid']! as int;
        expect(ProcessGroup.captureIdentity(processGroupId), isNotNull);

        host.kill(ProcessSignal.sigkill);
        await host.exitCode.timeout(const Duration(seconds: 3));
        final coordinator = ProcessRecoveryCoordinator(dataRoot.path);
        final report = await coordinator
            .recoverPending()
            .timeout(const Duration(seconds: 8));
        expect(report.confirmed, isTrue);
        expect(report.results.single.status, ProcessRecoveryStatus.cleaned);
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
      try {
        final process = await LandlockSeccompSandboxBackend().start(
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
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: ioctlSupported
        ? false
        : 'SKIP-MANIFEST PTY ioctl platform=${Platform.operatingSystem} '
            'abi=${abi ?? 'missing'}',
  );
}

Future<_FloodControlResult> _runUnsandboxedFloodControl(
  Duration timeout,
  int maxOutputBytes,
) async {
  final process = await Process.start(
    '/usr/bin/yes',
    const <String>[],
    runInShell: false,
  );
  var outputBytes = 0;
  final stdoutDone = process.stdout.listen((chunk) {
    outputBytes += math.min(chunk.length, maxOutputBytes - outputBytes);
  }).asFuture<void>();
  final stderrDone = process.stderr.drain<void>();
  var timedOut = false;
  try {
    await process.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 2));
  }
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  return _FloodControlResult(
    timedOut: timedOut,
    outputBytes: outputBytes,
  );
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
    required this.timedOut,
    required this.outputBytes,
  });

  final bool timedOut;
  final int outputBytes;
}
