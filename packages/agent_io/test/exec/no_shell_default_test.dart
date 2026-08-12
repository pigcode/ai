import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

void main() {
  final policy = SandboxPolicy(
    roots: <SandboxPathRule>[
      SandboxPathRule(
        path: Directory.current.path,
        access: SandboxPathAccess.readOnly,
      ),
    ],
  );

  test('P4-TM-PROC-02 default launch preserves argv without a shell', () async {
    final launcher =
        SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
    final process = await launcher.launch(
      policy,
      HostCommand(
        executable: Platform.resolvedExecutable,
        arguments: <String>[
          resolveTestWorkspacePath(
            packageRelative: 'test/fixtures/argv_probe.dart',
            workspaceRelative:
                'packages/agent_io/test/fixtures/argv_probe.dart',
          ),
          'two words',
          'plain-token',
        ],
      ),
    );

    final evidence = jsonDecode(await utf8.decoder.bind(process.stdout).join())
        as Map<String, Object?>;
    final parentExecutable = evidence['parentExecutable']! as String;
    expect(parentExecutable, isNotEmpty);
    expect(
      <String>['sh', 'bash', 'zsh', 'fish'],
      isNot(contains(parentExecutable.split('/').last)),
    );
    expect(
      evidence['arguments'],
      <String>['two words', 'plain-token'],
    );
    expect(await process.exitCode, 0);
  }, skip: _seatbeltSkip);

  test('P4-TM-PROC-03 shell metacharacters fail closed', () async {
    final launcher =
        SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
    const injected = 'safe;touch /tmp/escaped';
    final control = await Process.start(
      '/usr/bin/printf',
      const <String>['%s', injected],
      runInShell: false,
    );
    expect(
      await utf8.decoder.bind(control.stdout).join(),
      injected,
    );
    expect(
      await control.exitCode.timeout(const Duration(seconds: 2)),
      0,
    );

    await expectLater(
      launcher.launch(
        policy,
        HostCommand(
          executable: '/usr/bin/printf',
          arguments: const <String>[injected],
        ),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.shellInjectionRejected,
        ),
      ),
    );
  }, skip: _seatbeltSkip);
}

final Object _seatbeltSkip = Platform.isMacOS
    ? false
    : 'SKIP-MANIFEST PROC-02/03 platform=${Platform.operatingSystem} '
        'backend=seatbelt-required';
