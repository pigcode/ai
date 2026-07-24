import 'dart:convert';
import 'dart:io';

import 'src/lsp_peer_harness.dart';
import 'src/tooling_peer_cache.dart';
import 'src/tooling_process_harness.dart';

const _knownPeers = <String>{
  'dart-3.6.0',
  'dart-3.12.2',
  'typescript-5.3.0',
};

Future<void> main(List<String> arguments) async {
  final peers = _selectedPeers(arguments);
  final root = Directory.current.absolute;
  final cache = ToolingPeerCache(root: root);
  for (final peer in peers) {
    final report = peer.startsWith('dart-')
        ? await _runDart(cache, peer.substring('dart-'.length))
        : await _runTypeScript(cache);
    stdout.writeln(jsonEncode(report.toJson()));
  }
}

Set<String> _selectedPeers(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == '--all') {
    return _knownPeers;
  }
  final index = arguments.indexOf('--peer');
  if (index < 0 || index + 1 >= arguments.length) {
    throw ArgumentError(
      'Use --all or --peer ${_knownPeers.join('|')}.',
    );
  }
  final peer = arguments[index + 1];
  if (!_knownPeers.contains(peer)) {
    throw ArgumentError('Unknown LSP peer: $peer.');
  }
  return <String>{peer};
}

Future<LspPeerReport> _runDart(
  ToolingPeerCache cache,
  String release,
) async {
  final sdk = await cache.ensureDartSdk(release);
  final dart = ToolingPeerCache.dartExecutable(sdk);
  final workspace = Directory.fromUri(
    cache.root.uri.resolve('tool/fixtures/lsp/dart_workspace/'),
  );
  final resolve = await Process.run(
    dart.path,
    const <String>['pub', 'get'],
    workingDirectory: workspace.path,
    environment: <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
      'PUB_CACHE': Directory.fromUri(
        cache.cacheRoot.uri.resolve('pub-cache/$release/'),
      ).path,
    },
    includeParentEnvironment: false,
  );
  if (resolve.exitCode != 0) {
    throw StateError(
      'Dart $release fixture pub get failed: ${resolve.stderr}',
    );
  }
  return runLspPeer(
    LspPeerCommand(
      peer: 'dart-$release',
      family: 'dart-language-server',
      release: release,
      process: ToolingProcessCommand(
        executable: dart.path,
        arguments: const <String>[
          'language-server',
          '--client-id=pigcode',
          '--client-version=1.0.0',
        ],
        workingDirectory: workspace.path,
      ),
      workspaceUri: workspace.uri.toString(),
      documentUri: workspace.uri.resolve('lib/main.dart').toString(),
      languageId: 'dart',
    ),
  );
}

Future<LspPeerReport> _runTypeScript(ToolingPeerCache cache) async {
  final fixture = await cache.ensureTypeScriptPeer();
  final workspace = Directory.fromUri(
    cache.root.uri.resolve('tool/fixtures/lsp/typescript_workspace/'),
  );
  final entrypoint = File.fromUri(
    fixture.uri.resolve(
      'node_modules/typescript-language-server/lib/cli.mjs',
    ),
  );
  if (!entrypoint.existsSync()) {
    throw const ToolingPeerException(
      'tooling_typescript_entrypoint_missing',
      'Pinned TypeScript language server entrypoint is missing.',
    );
  }
  return runLspPeer(
    LspPeerCommand(
      peer: 'typescript-5.3.0',
      family: 'typescript-language-server',
      release: '5.3.0+typescript-6.0.3',
      process: ToolingProcessCommand(
        executable: 'node',
        arguments: <String>[entrypoint.path, '--stdio'],
        workingDirectory: workspace.path,
      ),
      workspaceUri: workspace.uri.toString(),
      documentUri: workspace.uri.resolve('index.ts').toString(),
      languageId: 'typescript',
    ),
  );
}
