import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/dart_fixture_compiler.dart';
import '../support/workspace_path.dart';

void main() {
  test('regular-file masks remove every directory-only Landlock right', () {
    final readOnly = LandlockFfi.allowedAccessForPathType(
      LandlockFfi.readOnlyAccessMask,
      LandlockPathType.file,
    );
    final readWrite = LandlockFfi.allowedAccessForPathType(
      LandlockFfi.readWriteAccessMask,
      LandlockPathType.file,
    );

    expect(readOnly & LandlockFfi.directoryOnlyAccessMask, 0);
    expect(readWrite & LandlockFfi.directoryOnlyAccessMask, 0);
    expect(readOnly, (1 << 0) | (1 << 2));
    expect(readWrite, (1 << 0) | (1 << 1) | (1 << 2) | (1 << 14));
    expect(LandlockFfi.runtimeFileAccessMask, 1 << 2);
    expect(
      LandlockFfi.runtimeFileAccessMask & ((1 << 1) | (1 << 15)),
      0,
      reason: '/dev/null needs neither WRITE_FILE nor IOCTL_DEV',
    );
  });

  test('directory masks retain complete hierarchy rights', () {
    final allowed = LandlockFfi.allowedAccessForPathType(
      LandlockFfi.readWriteAccessMask,
      LandlockPathType.directory,
    );

    expect(allowed, LandlockFfi.readWriteAccessMask);
    expect(
      allowed & LandlockFfi.directoryOnlyAccessMask,
      LandlockFfi.directoryOnlyAccessMask,
    );
  });

  test('Dart runtime dependency is the exact required procfs file', () {
    expect(
      LandlockFfi.runtimeDependencyPaths,
      contains('/proc/self/maps'),
    );
    expect(LandlockFfi.runtimeDependencyPaths, isNot(contains('/proc')));
    expect(LandlockFfi.runtimeDependencyPaths, isNot(contains('/proc/self')));
    expect(
      LandlockFfi.requiredRuntimeDependencyPaths,
      contains('/proc/self/maps'),
    );
  });

  final ffi = LandlockFfi();
  final abi = ffi.probeAbi();
  final supported =
      Platform.isLinux && abi != null && abi >= 4 && SeccompFfi().isSupported;
  final skipReason = supported
      ? false
      : 'SKIP-MANIFEST landlock-enforcement '
          'platform=${Platform.operatingSystem} abi=${abi ?? 'missing'}';

  test(
    'P4-TM-PATH-01/04 Linux kernel rejects root escape and read-only write',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_landlock_');
      try {
        final readOnly = Directory('${temp.path}/ro')..createSync();
        final readWrite = Directory('${temp.path}/rw')..createSync();
        final outside = File('${temp.path}/outside-secret')
          ..writeAsStringSync('landlock-secret');
        final backend =
            LandlockSeccompSandboxBackend(unsafeStandaloneStart: true);
        final policy = SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: readOnly.path,
              access: SandboxPathAccess.readOnly,
            ),
            SandboxPathRule(
              path: readWrite.path,
              access: SandboxPathAccess.readWrite,
            ),
          ],
        );

        final read = await _run(
          backend,
          policy,
          HostCommand(
            executable: '/bin/cat',
            arguments: <String>[outside.path],
          ),
        );
        final write = await _run(
          backend,
          policy,
          HostCommand(
            executable: '/bin/sh',
            arguments: <String>[
              '-c',
              'printf denied > "\$1"',
              'fixture',
              '${readOnly.path}/denied',
            ],
          ),
        );

        expect(read.exitCode, isNot(0));
        expect(read.stdout, isNot(contains('landlock-secret')));
        expect(write.exitCode, isNot(0));
        expect(File('${readOnly.path}/denied').existsSync(), isFalse);
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: skipReason,
  );

  test(
    'P4-TM-DLP-01 Linux kernel rejects non-allowlisted TCP connect',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_landlock_');
      final root = Directory('${temp.path}/root')..createSync();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final result = await _run(
          LandlockSeccompSandboxBackend(unsafeStandaloneStart: true),
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
          ),
          HostCommand(
            executable: '/usr/bin/nc',
            arguments: <String>[
              '-z',
              InternetAddress.loopbackIPv4.address,
              '${server.port}',
            ],
          ),
        );
        expect(result.exitCode, isNot(0));
        final bindProbe = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final deniedBindPort = bindProbe.port;
        await bindProbe.close();
        final bind = await _run(
          LandlockSeccompSandboxBackend(unsafeStandaloneStart: true),
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
          ),
          HostCommand(
            executable: '/usr/bin/nc',
            arguments: <String>[
              '-l',
              InternetAddress.loopbackIPv4.address,
              '$deniedBindPort',
            ],
          ),
        );
        expect(bind.exitCode, isNot(0));
      } finally {
        await server.close();
        temp.deleteSync(recursive: true);
      }
    },
    skip: skipReason,
  );

  test(
    'P4-TM-DLP-02 Linux Landlock permits only allowlisted TCP ports',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_landlock_');
      final root = Directory('${temp.path}/root')..createSync();
      final connectServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final bindProbe =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final bindPort = bindProbe.port;
      await bindProbe.close();
      try {
        final policy = SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: root.path,
              access: SandboxPathAccess.readWrite,
            ),
          ],
          networkAllowlist: <SandboxNetworkEndpoint>[
            SandboxNetworkEndpoint(host: '*', port: connectServer.port),
            SandboxNetworkEndpoint(host: '*', port: bindPort),
          ],
        );
        final backend =
            LandlockSeccompSandboxBackend(unsafeStandaloneStart: true);

        final connect = await _run(
          backend,
          policy,
          HostCommand(
            executable: '/usr/bin/nc',
            arguments: <String>[
              '-z',
              InternetAddress.loopbackIPv4.address,
              '${connectServer.port}',
            ],
          ),
        );
        final bind = await backend.start(
          policy,
          HostCommand(
            executable: '/usr/bin/nc',
            arguments: <String>[
              '-l',
              InternetAddress.loopbackIPv4.address,
              '$bindPort',
            ],
          ),
        );
        bind.stdout.drain<void>();
        bind.stderr.drain<void>();

        expect(connect.exitCode, 0);
        Socket? observer;
        try {
          observer = await _connectUntilListening(bindPort);
        } finally {
          observer?.destroy();
          bind.kill(ProcessSignal.sigkill);
          await bind.exitCode.timeout(const Duration(seconds: 2));
        }
      } finally {
        await connectServer.close();
        temp.deleteSync(recursive: true);
      }
    },
    skip: skipReason,
  );

  test(
    'Linux Dart VM reaches main without widening procfs',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_landlock_');
      final root = Directory('${temp.path}/root')..createSync();
      final fixtureRoot = Directory('${temp.path}/fixture');
      try {
        final probe = await compileDartFixture(
          sourcePath: resolveTestWorkspacePath(
            packageRelative: 'test/fixtures/dart_runtime_dependency_probe.dart',
            workspaceRelative: 'packages/agent_io/test/fixtures/'
                'dart_runtime_dependency_probe.dart',
          ),
          outputDirectory: fixtureRoot,
          outputName: 'dart_runtime_dependency_probe',
        );
        final result = await _run(
          LandlockSeccompSandboxBackend(unsafeStandaloneStart: true),
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
              SandboxPathRule(
                path: fixtureRoot.path,
                access: SandboxPathAccess.readOnly,
              ),
            ],
          ),
          HostCommand(executable: probe.path),
        );

        expect(result.exitCode, 0, reason: _diagnostics(result));
        expect(
          result.stdout,
          contains('DART_MAIN_REACHED'),
          reason: _diagnostics(result),
        );
        expect(
          result.stdout,
          contains('NON_REQUIRED_PROCFS_DENIED'),
          reason: _diagnostics(result),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: skipReason,
  );

  test(
    'Linux Dart target reaches main and seccomp returns EPERM for ptrace',
    () async {
      final temp = Directory.systemTemp.createTempSync('pigcode_landlock_');
      final root = Directory('${temp.path}/root')..createSync();
      final fixtureRoot = Directory('${temp.path}/fixture');
      try {
        final probe = await compileDartFixture(
          sourcePath: resolveTestWorkspacePath(
            packageRelative: 'test/fixtures/ptrace_probe.dart',
            workspaceRelative:
                'packages/agent_io/test/fixtures/ptrace_probe.dart',
          ),
          outputDirectory: fixtureRoot,
          outputName: 'ptrace_probe',
        );
        final result = await _run(
          LandlockSeccompSandboxBackend(unsafeStandaloneStart: true),
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
              SandboxPathRule(
                path: fixtureRoot.path,
                access: SandboxPathAccess.readOnly,
              ),
            ],
          ),
          HostCommand(executable: probe.path),
        );
        expect(result.exitCode, 77, reason: _diagnostics(result));
        expect(
          result.stdout,
          contains('PTRACE_RESULT=-1 ERRNO=1'),
          reason: _diagnostics(result),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: skipReason,
  );
}

Future<({int exitCode, String stdout, String stderr})> _run(
  SandboxBackend backend,
  SandboxPolicy policy,
  HostCommand command,
) async {
  final process = await backend.start(policy, command);
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();
  try {
    return (
      exitCode: await process.exitCode.timeout(const Duration(seconds: 8)),
      stdout: await output,
      stderr: await errors,
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    rethrow;
  }
}

String _diagnostics(
  ({int exitCode, String stdout, String stderr}) result,
) =>
    'stdout:\n${result.stdout}\nstderr:\n${result.stderr}';

Future<Socket> _connectUntilListening(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      return await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 100),
      );
    } on SocketException catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  throw StateError('sandbox bind did not listen on port $port: $lastError');
}
