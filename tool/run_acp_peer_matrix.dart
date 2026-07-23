import 'dart:convert';
import 'dart:io';

import 'src/acp_peer_harness.dart';

const _typescriptDirectory = 'tool/fixtures/acp/typescript';
const _rustRevision = 'ce023279824149008659dd8f4b8b70266a7e8210';
const _rustRepository = 'https://github.com/agentclientprotocol/rust-sdk.git';

Future<void> main(List<String> arguments) async {
  final peer = _parsePeer(arguments);
  final root = Directory.current.absolute.path;
  final report = switch (peer) {
    'dart' => await runAcpPeer(
        AcpPeerCommand(
          peer: 'dart-fixed',
          executable: Platform.resolvedExecutable,
          arguments: const <String>['tool/fixtures/acp_peer.dart'],
          workingDirectory: root,
          promptText: 'interop 🐷',
          artifacts: const <String, String>{
            'source': 'tool/fixtures/acp_peer.dart',
          },
        ),
      ),
    'typescript' => await _runTypescript(root),
    'rust' => await _runRust(root),
    _ => throw StateError('Unreachable peer selection.'),
  };
  final outputDirectory = Directory('.dart_tool/acp_peer_reports')
    ..createSync(recursive: true);
  final output = File('${outputDirectory.path}/$peer.json');
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  stdout.writeln(
    'PASS ACP ${report.peer} matrix ${jsonEncode(report.toJson())}',
  );
}

Future<AcpPeerReport> _runTypescript(String root) async {
  await _runChecked(
    'npm',
    const <String>['ci', '--ignore-scripts'],
    workingDirectory: _typescriptDirectory,
  );
  final installed = jsonDecode(
    File(
      '$_typescriptDirectory/node_modules/'
      '@agentclientprotocol/sdk/package.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  if (installed['version'] != '1.3.0') {
    throw StateError('TypeScript ACP SDK is not exact version 1.3.0.');
  }
  return runAcpPeer(
    AcpPeerCommand(
      peer: 'typescript-v1.3.0',
      executable: 'node',
      arguments: const <String>['agent.mjs'],
      workingDirectory: '$root/$_typescriptDirectory',
      promptText: 'interop 🐷',
      artifacts: const <String, String>{
        'source': 'tool/fixtures/acp/typescript/agent.mjs',
        'packageLock': 'tool/fixtures/acp/typescript/package-lock.json',
      },
    ),
  );
}

Future<AcpPeerReport> _runRust(String root) async {
  final checkout = Directory('.dart_tool/acp_peers/rust-sdk-v2.0.0');
  if (!checkout.existsSync()) {
    checkout.parent.createSync(recursive: true);
    await _runChecked(
      'git',
      const <String>[
        'clone',
        '--depth',
        '1',
        '--branch',
        'v2.0.0',
        _rustRepository,
        '.dart_tool/acp_peers/rust-sdk-v2.0.0',
      ],
      workingDirectory: root,
      deadline: const Duration(minutes: 2),
    );
  }
  final revision = await _runChecked(
    'git',
    const <String>['rev-parse', 'HEAD'],
    workingDirectory: checkout.path,
  );
  if (revision.trim() != _rustRevision) {
    throw StateError(
      'Rust ACP peer checkout is ${revision.trim()}, expected $_rustRevision.',
    );
  }
  await _runChecked(
    'cargo',
    const <String>[
      'build',
      '--locked',
      '--package',
      'agent-client-protocol-test',
      '--bin',
      'testy',
      '--no-default-features',
    ],
    workingDirectory: checkout.path,
    deadline: const Duration(minutes: 10),
  );
  final binary = '${checkout.path}/target/debug/testy';
  return runAcpPeer(
    AcpPeerCommand(
      peer: 'rust-testy-v2.0.0',
      executable: binary,
      arguments: const <String>[],
      workingDirectory: root,
      promptText: 'full',
      artifacts: <String, String>{
        'binary': binary,
        'cargoLock': '${checkout.path}/Cargo.lock',
      },
      environment: const <String, String>{'RUST_LOG': 'error'},
    ),
    deadline: const Duration(minutes: 2),
  );
}

String _parsePeer(List<String> arguments) {
  if (arguments.length != 2 ||
      arguments.first != '--peer' ||
      !const <String>{'dart', 'typescript', 'rust'}.contains(arguments.last)) {
    stderr.writeln(
      'Usage: dart run tool/run_acp_peer_matrix.dart '
      '--peer dart|typescript|rust',
    );
    exitCode = 64;
    throw const FormatException('Invalid ACP peer selection.');
  }
  return arguments.last;
}

Future<String> _runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Duration deadline = const Duration(minutes: 1),
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  ).timeout(deadline);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed with ${result.exitCode}:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return result.stdout as String;
}
