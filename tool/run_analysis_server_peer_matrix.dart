import 'dart:convert';
import 'dart:io';

import 'src/analysis_server_peer_harness.dart';
import 'src/tooling_peer_cache.dart';

const _knownPeers = <String>{
  'dart-3.6.0',
  'dart-3.12.2',
};

const _apiVersions = <String, String>{
  '3.6.0': '1.38.0',
  '3.12.2': '1.40.1',
};

Future<void> main(List<String> arguments) async {
  final peers = _selectedPeers(arguments);
  final root = Directory.current.absolute;
  final cache = ToolingPeerCache(root: root);
  for (final peer in peers) {
    final release = peer.substring('dart-'.length);
    final report = await _runPeer(cache, release);
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
    throw ArgumentError('Unknown Analysis Server peer: $peer.');
  }
  return <String>{peer};
}

Future<AnalysisServerPeerReport> _runPeer(
  ToolingPeerCache cache,
  String release,
) async {
  final sdk = await cache.ensureDartSdk(release);
  final dart = ToolingPeerCache.dartExecutable(sdk);
  final workspace = Directory.fromUri(
    cache.root.uri.resolve(
      'tool/fixtures/dart_tooling/analyzer_workspace/',
    ),
  );
  final source = File.fromUri(workspace.uri.resolve('lib/main.dart'));
  final pubCache = Directory.fromUri(
    cache.cacheRoot.uri.resolve('pub-cache/$release/'),
  )..createSync(recursive: true);
  final environment = <String, String>{'PUB_CACHE': pubCache.path};
  final sourceText = source.readAsStringSync();
  final hoverOffset = sourceText.indexOf('greeting');
  if (hoverOffset < 0) {
    throw StateError('Analyzer fixture hover target is missing.');
  }
  final workspacePath = workspace.path.endsWith(Platform.pathSeparator)
      ? workspace.path.substring(0, workspace.path.length - 1)
      : workspace.path;
  return runAnalysisServerPeer(
    AnalysisServerPeerCommand(
      peer: 'dart-$release-analysis-server',
      release: release,
      expectedApiVersion: _apiVersions[release]!,
      dartExecutable: dart.path,
      workingDirectory: workspace.path,
      workspaceReference: workspacePath,
      sourceReference: source.path,
      hoverOffset: hoverOffset,
      environment: environment,
    ),
  );
}
