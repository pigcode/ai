import 'dart:io';

import 'sandbox_backend.dart';
import 'sandbox_capability.dart';
import 'sandbox_policy.dart';

final class UnsafeDevSandboxBackend implements SandboxBackend {
  @override
  bool get establishesProcessGroup => false;

  @override
  SandboxCapabilityReport probe() => SandboxCapabilityReport.untrusted(
        platform: SandboxPlatform.current,
        backend: 'unsafe-process',
        available: true,
        minimumSatisfied: false,
        labels: const <String>{'unsafe/dev-only'},
      );

  @override
  Future<SandboxedProcess> start(
    SandboxPolicy policy,
    HostCommand command,
  ) async {
    final process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: command.environment,
      runInShell: false,
    );
    return SandboxedProcess(process, probe());
  }
}
