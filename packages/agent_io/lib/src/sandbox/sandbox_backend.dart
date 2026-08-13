import 'dart:io';

import 'sandbox_capability.dart';
import 'sandbox_policy.dart';

final class HostCommand {
  HostCommand({
    required this.executable,
    List<String> arguments = const <String>[],
    this.workingDirectory,
    Map<String, String>? environment,
  })  : arguments = List<String>.unmodifiable(arguments),
        environment = environment == null
            ? null
            : Map<String, String>.unmodifiable(environment);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

final class SandboxedProcess {
  SandboxedProcess(
    this.process,
    this.capability, {
    Stream<List<int>>? stdout,
    Stream<List<int>>? stderr,
    int? processGroupId,
  })  : _stdout = stdout ?? process.stdout,
        _stderr = stderr ?? process.stderr,
        processGroupId = processGroupId ?? process.pid;

  final Process process;
  final SandboxCapabilityReport capability;
  final int processGroupId;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;

  int get pid => process.pid;
  IOSink get stdin => process.stdin;
  Stream<List<int>> get stdout => _stdout;
  Stream<List<int>> get stderr => _stderr;
  Future<int> get exitCode => process.exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      process.kill(signal);
}

abstract interface class SandboxBackend {
  bool get establishesProcessGroup;

  SandboxCapabilityReport probe();

  Future<SandboxedProcess> start(
    SandboxPolicy policy,
    HostCommand command,
  );
}
