import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import '../../exec/sandboxed_process.dart';
import '../../package_asset.dart';
import '../sandbox_backend.dart';
import '../sandbox_capability.dart';
import '../sandbox_errors.dart';
import '../sandbox_policy.dart';
import '../sandbox_prepared_backend.dart';
import '../sandbox_startup_handshake.dart';
import 'sbpl_profile.dart';

final class SeatbeltSandboxBackend implements PreparedSandboxBackend {
  SeatbeltSandboxBackend({
    SandboxCapabilityProbe? capabilityProbe,
    SandboxStartupObserver? startupObserver,
    this.unsafeStandaloneStart = false,
  })  : _capabilityProbe = capabilityProbe ?? SandboxCapabilityProbe(),
        _startupObserver = startupObserver;

  static const executable = '/usr/bin/sandbox-exec';
  static const _setupDeadline = Duration(seconds: 5);

  final SandboxCapabilityProbe _capabilityProbe;
  final SandboxStartupObserver? _startupObserver;
  final bool unsafeStandaloneStart;

  @override
  bool get establishesProcessGroup => true;

  @override
  SandboxCapabilityReport probe() => _capabilityProbe.probe();

  Future<HostCommand> _prepare(
    SandboxPolicy policy,
    HostCommand command, {
    required bool startupHandshake,
  }) async {
    final capability = probe();
    capability.requireProductionReady();
    final readyRunner = startupHandshake
        ? await resolveAgentIoPackageAsset(
            'src/sandbox/seatbelt/sandbox_ready_runner.dart',
          )
        : null;
    final cryptoLibrary = startupHandshake
        ? await Isolate.resolvePackageUri(
            Uri.parse('package:crypto/crypto.dart'),
          )
        : null;
    final packageConfig = startupHandshake ? await Isolate.packageConfig : null;
    final profile = SbplProfile.generate(
      policy,
      trustedRuntimeReadPaths: readyRunner == null
          ? const <String>[]
          : <String>[
              command.executable,
              if (cryptoLibrary != null)
                File.fromUri(cryptoLibrary).parent.path,
              if (packageConfig != null) File.fromUri(packageConfig).path,
              File(Platform.resolvedExecutable).parent.path,
              File(readyRunner).parent.parent.parent.parent.path,
            ],
    );
    await _validateProfile(profile);
    await _startupObserver?.call(
      SandboxStartupPhase.sandboxSetupPreparedBeforeApply,
      <String, Object?>{
        'profileBytes': utf8.encode(profile).length,
        'type': 'sandbox-setup-prepared',
      },
    );
    final encodedCommand = startupHandshake
        ? base64Url.encode(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'arguments': command.arguments,
                'executable': command.executable,
              }),
            ),
          )
        : null;
    return HostCommand(
      executable: executable,
      arguments: <String>[
        '-p',
        profile,
        '--',
        if (startupHandshake) ...<String>[
          Platform.resolvedExecutable,
          if (packageConfig != null)
            '--packages=${File.fromUri(packageConfig).path}',
          readyRunner!,
          encodedCommand!,
        ] else ...<String>[
          command.executable,
          ...command.arguments,
        ],
      ],
      workingDirectory: command.workingDirectory ??
          (startupHandshake ? policy.roots.first.path : null),
      environment: command.environment,
    );
  }

  @override
  Future<HostCommand> prepareForPty(
    SandboxPolicy policy,
    HostCommand command,
  ) =>
      _prepare(policy, command, startupHandshake: true);

  @override
  Future<SandboxedProcess> start(
    SandboxPolicy policy,
    HostCommand command,
  ) async {
    probe().requireProductionReady();
    if (unsafeStandaloneStart) {
      final launcher = SandboxedProcessLauncher.unsafeDev(
        this,
        allowShellSyntaxForTests: true,
      );
      final process = await launcher.launch(policy, command);
      unawaited(process.exitCode.then((_) => launcher.cleanup(process)));
      return process;
    }
    throw const HostCapabilityException(
      HostCapabilityError.processCleanupFailed,
      'standalone-seatbelt-start-requires-stable-launcher',
    );
  }

  @override
  Future<SandboxedProcess> startPrepared(
    SandboxPolicy policy,
    HostCommand command, {
    required PersistProcessGroup persistProcessGroup,
  }) async {
    final capability = probe();
    final prepared = await _prepare(
      policy,
      command,
      startupHandshake: true,
    );
    final groupedCommand = base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'arguments': prepared.arguments,
          'executable': prepared.executable,
          'handshake': true,
        }),
      ),
    );
    try {
      final runnerPath = await resolveAgentIoPackageAsset(
        'src/exec/process_group_runner.dart',
      );
      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          runnerPath,
          groupedCommand,
        ],
        workingDirectory: prepared.workingDirectory,
        environment: prepared.environment,
        runInShell: false,
      );
      final output = await awaitSandboxStartup(
        process,
        persistProcessGroup: persistProcessGroup,
        observer: _startupObserver,
      );
      return SandboxedProcess(process, capability, stdout: output);
    } on ProcessException {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seatbelt-start-failed',
      );
    }
  }

  Future<void> _validateProfile(String profile) async {
    Process process;
    try {
      process = await Process.start(
        executable,
        <String>['-p', profile, '--', '/usr/bin/true'],
        runInShell: false,
      );
    } on ProcessException {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seatbelt-profile-compiler-unavailable',
      );
    }
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.drain<void>();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(_setupDeadline);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 1));
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seatbelt-profile-compile-timeout',
      );
    }
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    if (exitCode != 0) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seatbelt-profile-compile-failed',
      );
    }
  }
}
