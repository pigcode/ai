import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exec/sandboxed_process.dart';
import '../package_asset.dart';
import '../sandbox/sandbox_backend.dart';
import '../sandbox/sandbox_capability.dart';
import '../sandbox/sandbox_errors.dart';
import '../sandbox/sandbox_policy.dart';
import '../sandbox/sandbox_prepared_backend.dart';

final class PtyCapabilityReport {
  const PtyCapabilityReport({
    required this.deviceIoctlRestricted,
    required this.manifestStatus,
  });

  factory PtyCapabilityReport.fromSandbox(SandboxCapabilityReport report) {
    final abi = report.landlockAbi;
    return PtyCapabilityReport(
      deviceIoctlRestricted: abi != null && abi >= 5,
      manifestStatus: abi == 4
          ? 'unsupported-landlock-abi4'
          : abi != null && abi >= 5
              ? 'restricted'
              : 'platform-not-applicable',
    );
  }

  final bool deviceIoctlRestricted;
  final String manifestStatus;
}

final class PtyRunResult {
  const PtyRunResult({
    required this.exitCode,
    required this.output,
    required this.timedOut,
  });

  final int exitCode;
  final String output;
  final bool timedOut;
}

final class HostPtySession {
  HostPtySession(
    this.launcher, {
    this.maxOutputBytes = 64 * 1024,
    this.startupBudget = const Duration(seconds: 30),
    String? runnerPath,
  }) : _runnerPath = runnerPath {
    if (maxOutputBytes < 1) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (startupBudget <= Duration.zero) {
      throw ArgumentError.value(startupBudget, 'startupBudget');
    }
  }

  final SandboxedProcessLauncher launcher;
  final int maxOutputBytes;
  final Duration startupBudget;
  final String? _runnerPath;

  static const String platformBroker = 'openpty+posix_spawn';
  static const bool usesShell = false;

  Future<SandboxedProcess> start(
    SandboxPolicy policy,
    HostCommand command,
  ) async {
    if (!policy.requiresPty) {
      throw const HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        'pty-policy-required',
      );
    }
    final runner = await resolveAgentIoPackageAsset(
      'src/pty/pty_runner_entrypoint.dart',
      overridePath: _runnerPath,
    );
    final backend = launcher.backend;
    if (backend is! PreparedSandboxBackend) {
      throw const HostCapabilityException(
        HostCapabilityError.ptyUnavailable,
        'pty-backend-preparation-unavailable',
      );
    }
    final prepared = await backend.prepareForPty(policy, command);
    final encoded = base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'executable': prepared.executable,
          'arguments': prepared.arguments,
        }),
      ),
    );
    return launcher.launchBroker(
      HostCommand(
        executable: Platform.resolvedExecutable,
        arguments: <String>[runner, encoded],
        workingDirectory: prepared.workingDirectory ?? policy.roots.first.path,
        environment: prepared.environment,
      ),
      launcher.backend.probe(),
      startupBudget: startupBudget,
    );
  }

  Future<PtyRunResult> run(
    SandboxPolicy policy,
    HostCommand command, {
    Duration executionTimeout = const Duration(seconds: 8),
  }) async {
    final process = await start(policy, command);
    final output = _BoundedOutput(maxOutputBytes);
    final stdoutDone = process.stdout.listen(output.add).asFuture<void>();
    final stderrDone = process.stderr.listen(output.add).asFuture<void>();
    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(executionTimeout);
    } on TimeoutException {
      timedOut = true;
      await launcher.cleanup(process);
      exitCode = await process.exitCode.timeout(const Duration(seconds: 2));
    }
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    return PtyRunResult(
      exitCode: exitCode,
      output: output.text,
      timedOut: timedOut,
    );
  }
}

final class _BoundedOutput {
  _BoundedOutput(this.limit);

  final int limit;
  final List<int> _bytes = <int>[];

  void add(List<int> chunk) {
    final remaining = limit - _bytes.length;
    if (remaining <= 0) return;
    _bytes.addAll(chunk.take(remaining));
  }

  String get text => utf8.decode(_bytes, allowMalformed: true);
}
