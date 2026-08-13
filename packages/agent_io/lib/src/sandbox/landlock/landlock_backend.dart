import 'dart:convert';
import 'dart:io';

import '../../exec/sandboxed_process.dart';
import '../../package_asset.dart';
import '../sandbox_backend.dart';
import '../sandbox_capability.dart';
import '../sandbox_errors.dart';
import '../sandbox_policy.dart';
import '../sandbox_prepared_backend.dart';
import '../sandbox_startup_handshake.dart';
import 'landlock_ffi.dart';
import 'seccomp_ffi.dart';

final class LandlockSeccompSandboxBackend implements PreparedSandboxBackend {
  LandlockSeccompSandboxBackend({
    SandboxCapabilityProbe? capabilityProbe,
    String? runnerPath,
    SandboxStartupObserver? startupObserver,
    this.unsafeStandaloneStart = false,
  })  : _capabilityProbe = capabilityProbe ?? _nativeProbe(),
        _runnerPath = runnerPath,
        _startupObserver = startupObserver;

  final SandboxCapabilityProbe _capabilityProbe;
  final String? _runnerPath;
  final SandboxStartupObserver? _startupObserver;
  final bool unsafeStandaloneStart;

  @override
  bool get establishesProcessGroup => true;

  static SandboxCapabilityProbe _nativeProbe() {
    final landlock = LandlockFfi();
    final seccomp = SeccompFfi();
    return SandboxCapabilityProbe(
      platform: SandboxPlatform.current,
      landlockAbi: landlock.probeAbi,
      seccompSupported: () => seccomp.isSupported,
    );
  }

  @override
  SandboxCapabilityReport probe() => _capabilityProbe.probe();

  Future<HostCommand> _prepare(SandboxPolicy policy, HostCommand command,
      {bool groupPersisted = false}) async {
    LandlockFfi.validatePolicyExpressibility(policy);
    final capability = probe();
    capability.requireProductionReady();
    final encodedPolicy = base64Url.encode(
      utf8.encode(jsonEncode(_policyJson(policy))),
    );
    final runnerPath = await resolveAgentIoPackageAsset(
      'src/sandbox/landlock/sandbox_runner_entrypoint.dart',
      overridePath: _runnerPath,
    );
    await _startupObserver?.call(
      SandboxStartupPhase.sandboxSetupPreparedBeforeApply,
      <String, Object?>{
        'policyBytes': utf8.encode(encodedPolicy).length,
        'type': 'sandbox-setup-prepared',
      },
    );
    return HostCommand(
      executable: Platform.resolvedExecutable,
      arguments: <String>[
        runnerPath,
        if (groupPersisted) '--group-persisted',
        '--policy',
        encodedPolicy,
        '--',
        command.executable,
        ...command.arguments,
      ],
      workingDirectory: command.workingDirectory,
      environment: command.environment,
    );
  }

  @override
  Future<HostCommand> prepareForPty(
    SandboxPolicy policy,
    HostCommand command,
  ) =>
      _prepare(policy, command, groupPersisted: true);

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
      process.exitCode.then((_) => launcher.cleanup(process));
      return process;
    }
    throw const HostCapabilityException(
      HostCapabilityError.processCleanupFailed,
      'standalone-landlock-start-requires-stable-launcher',
    );
  }

  @override
  Future<SandboxedProcess> startPrepared(
    SandboxPolicy policy,
    HostCommand command, {
    required PersistProcessGroup persistProcessGroup,
  }) async {
    final capability = probe();
    final prepared = await _prepare(policy, command);
    try {
      final process = await Process.start(
        prepared.executable,
        prepared.arguments,
        workingDirectory: prepared.workingDirectory,
        environment: sandboxLaunchEnvironment(prepared.environment),
        includeParentEnvironment: false,
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
        'landlock-runner-start-failed',
      );
    }
  }

  static Map<String, Object?> _policyJson(SandboxPolicy policy) =>
      <String, Object?>{
        'roots': policy.roots
            .map(
              (root) => <String, Object?>{
                'access': root.access.name,
                'path': root.path,
              },
            )
            .toList(),
        'networkAllowlist': policy.networkAllowlist
            .map(
              (endpoint) => <String, Object?>{
                'host': endpoint.host,
                'port': endpoint.port,
              },
            )
            .toList(),
        'denyReadPaths': policy.denyReadPaths,
        'requiresPty': policy.requiresPty,
      };
}
