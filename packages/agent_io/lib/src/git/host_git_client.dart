import 'dart:convert';
import 'dart:io';

import '../exec/sandboxed_process.dart';
import '../sandbox/sandbox_backend.dart';
import '../sandbox/sandbox_policy.dart';

final class HostGitResult {
  const HostGitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class HostGitClient {
  HostGitClient({
    required this.workspace,
    required this.launcher,
    List<SandboxNetworkEndpoint> networkAllowlist =
        const <SandboxNetworkEndpoint>[],
  }) : networkAllowlist = List<SandboxNetworkEndpoint>.unmodifiable(
          networkAllowlist,
        );

  final Directory workspace;
  final SandboxedProcessLauncher launcher;
  final List<SandboxNetworkEndpoint> networkAllowlist;

  Future<SandboxedProcess> start(
    List<String> arguments, {
    List<String> additionalDenyReadPaths = const <String>[],
  }) {
    return launcher.launch(
      _policy(additionalDenyReadPaths),
      HostCommand(
        executable: '/usr/bin/git',
        arguments: arguments,
        workingDirectory: workspace.path,
        environment: const <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_TERMINAL_PROMPT': '0',
          'GIT_ASKPASS': '/usr/bin/false',
        },
      ),
    );
  }

  Future<HostGitResult> run(
    List<String> arguments, {
    List<String> additionalDenyReadPaths = const <String>[],
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final process = await start(
      arguments,
      additionalDenyReadPaths: additionalDenyReadPaths,
    );
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () async {
        await launcher.cleanup(process);
        return process.exitCode;
      },
    );
    final result = HostGitResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
    await launcher.cleanup(process);
    return result;
  }

  SandboxPolicy _policy(List<String> additionalDenyReadPaths) {
    final home = Platform.environment['HOME'];
    final roots = <SandboxPathRule>[
      SandboxPathRule(
        path: workspace.absolute.path,
        access: SandboxPathAccess.readWrite,
      ),
    ];
    for (final path in <String>[
      '${workspace.absolute.path}/.git',
      '${workspace.absolute.path}/.gitconfig',
      if (home != null) '$home/.gitconfig',
    ]) {
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        roots.add(
          SandboxPathRule(path: path, access: SandboxPathAccess.readOnly),
        );
      }
    }
    return SandboxPolicy(
      roots: roots,
      networkAllowlist: networkAllowlist,
      denyReadPaths: <String>[
        if (home != null) ...<String>[
          '$home/.ssh',
          '$home/.aws',
          '$home/.git-credentials',
          '$home/.config/gh',
        ],
        ...additionalDenyReadPaths,
      ],
    );
  }
}
