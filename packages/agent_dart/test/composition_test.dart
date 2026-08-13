import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent_dart/pigcode_ai_agent_dart.dart';
import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../../../tool/src/tooling_peer_cache.dart';

void main() {
  test('production capability binding accepts only real probe reports', () {
    final report = SandboxCapabilityProbe(
      platform: SandboxPlatform.macosArm64,
      sandboxExecExists: () => true,
      macosMajorVersion: () => 15,
    ).probe();
    final capabilities = bindProductionNativeCapabilities(report);
    expect(capabilities.productionTrusted, isTrue);
    expect(capabilities.sandboxCapabilityDigest, report.digest);

    final forged = SandboxCapabilityReport.untrusted(
      platform: SandboxPlatform.macosArm64,
      backend: 'seatbelt',
      available: true,
      minimumSatisfied: true,
      sandboxExecPresent: true,
    );
    expect(
      () => bindProductionNativeCapabilities(forged),
      throwsA(isA<HostCapabilityException>()),
    );
  });

  test('tooling process launches only through SandboxedProcessLauncher',
      () async {
    final backend = _RecordingBackend();
    final launcher = SandboxedProcessLauncher.unsafeDev(backend);
    final workspace = DartToolingWorkspace(
      launcher: launcher,
      policy: SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: Directory.current.absolute.path,
            access: SandboxPathAccess.readOnly,
          ),
        ],
      ),
    );
    final process = await workspace.launch(
      HostCommand(executable: '/usr/bin/true'),
    );
    await process.exitCode;
    await launcher.cleanup(process);
    expect(backend.startCount, 1);
  });

  test('runInTerminal and applyEdit remain proposals until approved', () {
    final dap = DapDebugCapability();
    final lsp = LspEditCapability();
    final terminal = dap.proposeRunInTerminal(<String, Object?>{
      'cwd': Directory.current.path,
      'args': <Object?>['/usr/bin/true'],
    });
    final edit = lsp.proposeApplyEdit(<String, Object?>{
      'edit': <String, Object?>{'changes': <String, Object?>{}},
    });

    expect(terminal.executed, isFalse);
    expect(edit.executed, isFalse);
    expect(terminal.effectControl.name, 'interceptable');
    expect(edit.effectControl.name, 'interceptable');
  });

  test(
    'real Dart LSP runs inside composition sandbox and edit stays proposed',
    () async {
      final repository = _repositoryRoot();
      final cache = ToolingPeerCache(root: repository);
      await cache.ensureDartSdk('3.12.2').timeout(const Duration(seconds: 30));
      final launcher =
          SandboxedProcessLauncher.unsafeDev(SeatbeltSandboxBackend());
      final workspace = DartToolingWorkspace(
        launcher: launcher,
        policy: SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: repository.path,
              access: SandboxPathAccess.readWrite,
            ),
            SandboxPathRule(
              path: File(Platform.resolvedExecutable).parent.path,
              access: SandboxPathAccess.readOnly,
            ),
            SandboxPathRule(
              path: '${Platform.environment['HOME']}/.pub-cache',
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
      );
      final proposalRoot =
          Directory.systemTemp.createTempSync('pigcode_lsp_proposal_');
      final toolingHome = Directory(
        '${repository.path}/.dart_tool/phase4-lsp-home',
      )..createSync(recursive: true);
      final target = File('${proposalRoot.path}/target.dart')
        ..writeAsStringSync('const before = true;\n');
      SandboxedProcess? process;
      try {
        process = await workspace.launch(
          HostCommand(
            executable: Platform.resolvedExecutable,
            arguments: const <String>[
              'run',
              'tool/run_lsp_peer_matrix.dart',
              '--peer',
              'dart-3.12.2',
            ],
            workingDirectory: repository.path,
            environment: <String, String>{
              ...Platform.environment,
              'CI': 'true',
              'DART_SUPPRESS_ANALYTICS': 'true',
              'HOME': toolingHome.path,
            },
          ),
        );
        final stdoutFuture = utf8.decoder.bind(process.stdout).join();
        final stderrFuture = utf8.decoder.bind(process.stderr).join();
        final exitCode =
            await process.exitCode.timeout(const Duration(seconds: 60));
        final output = await stdoutFuture;
        final errors = await stderrFuture;
        expect(exitCode, 0, reason: errors);
        final report = jsonDecode(
          output
              .split('\n')
              .firstWhere((line) => line.trimLeft().startsWith('{')),
        ) as Map<String, Object?>;
        expect(report['peer'], 'dart-3.12.2');
        expect(
          report['scenarios'],
          containsAll(<String>[
            'initialize',
            'open',
            'hover',
            'completion',
            'shutdown',
          ]),
        );
        expect(process.capability.backend, 'seatbelt');

        final before = target.readAsStringSync();
        final proposal = LspEditCapability().proposeApplyEdit(
          <String, Object?>{
            'label': 'unapproved edit',
            'edit': <String, Object?>{
              'changes': <String, Object?>{
                target.uri.toString(): <Object?>[
                  <String, Object?>{
                    'range': <String, Object?>{
                      'start': <String, Object?>{'line': 0, 'character': 0},
                      'end': <String, Object?>{'line': 0, 'character': 0},
                    },
                    'newText': '// should-not-apply\n',
                  },
                ],
              },
            },
          },
        );
        expect(proposal.executed, isFalse);
        expect(proposal.effectControl, DartHostEffectControl.interceptable);
        expect(target.readAsStringSync(), before);
      } finally {
        if (process != null) {
          final cleanup = await launcher.cleanup(process);
          expect(cleanup.confirmed, isTrue);
        }
        proposalRoot.deleteSync(recursive: true);
        if (toolingHome.existsSync()) toolingHome.deleteSync(recursive: true);
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST real Dart LSP composition requires Seatbelt',
  );

  test('composition pubspec has no MCP reverse dependency', () {
    final pubspec = File(
      File('pubspec.yaml').existsSync()
          ? 'pubspec.yaml'
          : 'packages/agent_dart/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, isNot(contains('pigcode_ai_mcp')));
  });

  test(
    'P4-TM-PROC-05 observedOnly has no approval and sandbox still enforces',
    () async {
      final root = Directory.systemTemp.createTempSync('p4-proc05-root-');
      final outside = Directory.systemTemp.createTempSync('p4-proc05-outside-');
      final target = '${outside.path}/denied';
      final backend = SeatbeltSandboxBackend();
      final driver = NativeAgentDriver<Object?, Object?, Object?>(
        bindProductionNativeCapabilities(backend.probe()),
      );
      final disposition = driver.effectDisposition('external.shell');
      final launcher = SandboxedProcessLauncher.unsafeDev(backend);
      try {
        final process = await launcher.launch(
          SandboxPolicy(
            roots: <SandboxPathRule>[
              SandboxPathRule(
                path: root.path,
                access: SandboxPathAccess.readWrite,
              ),
            ],
          ),
          HostCommand(
              executable: '/usr/bin/touch', arguments: <String>[target]),
        );
        expect(
          await process.exitCode.timeout(const Duration(seconds: 5)),
          isNot(0),
        );
        expect(File(target).existsSync(), isFalse);
        expect(disposition.approvalEvidenceAllowed, isFalse);
        expect(disposition.sandboxRequired, isTrue);
        await launcher.cleanup(process);
      } finally {
        root.deleteSync(recursive: true);
        outside.deleteSync(recursive: true);
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'SKIP-MANIFEST PROC-05 Seatbelt evidence requires macOS',
  );
}

final class _RecordingBackend implements SandboxBackend {
  int startCount = 0;

  @override
  bool get establishesProcessGroup => false;

  @override
  SandboxCapabilityReport probe() => SandboxCapabilityReport.untrusted(
        platform: SandboxPlatform.current,
        backend: 'recording-test',
        available: true,
        minimumSatisfied: false,
      );

  @override
  Future<SandboxedProcess> start(
    SandboxPolicy policy,
    HostCommand command,
  ) async {
    startCount += 1;
    return SandboxedProcess(
      await Process.start(command.executable, command.arguments),
      probe(),
    );
  }
}

Directory _repositoryRoot() {
  final current = Directory.current.absolute;
  if (File.fromUri(
    current.uri.resolve('compatibility/phase-4-native-containment.json'),
  ).existsSync()) {
    return current;
  }
  final candidate = Directory.fromUri(current.uri.resolve('../../'));
  if (File.fromUri(
    candidate.uri.resolve('compatibility/phase-4-native-containment.json'),
  ).existsSync()) {
    return candidate.absolute;
  }
  throw StateError('Cannot locate repository root from ${current.path}.');
}
