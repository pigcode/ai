import 'dart:convert';
import 'dart:io';

import 'src/dtd_peer_harness.dart';
import 'src/tooling_peer_cache.dart';

const _knownPeers = <String>{
  'dart-3.6.0',
  'dart-3.12.2',
};

Future<void> main(List<String> arguments) async {
  final peers = _selectedPeers(arguments);
  final root = Directory.current.absolute;
  final cache = ToolingPeerCache(root: root);
  for (final peer in peers) {
    final release = peer.substring('dart-'.length);
    final sdk = await cache.ensureDartSdk(release);
    final dart = ToolingPeerCache.dartExecutable(sdk);
    final fixture = File.fromUri(
      root.uri.resolve(
        'tool/fixtures/dart_tooling/dtd_client_fixture.dart',
      ),
    );
    final pubCache = Directory.fromUri(
      cache.cacheRoot.uri.resolve('pub-cache/$release/'),
    )..createSync(recursive: true);
    final report = await runDtdPeer(
      DtdPeerCommand(
        peer: 'dart-$release-dtd',
        release: release,
        dartExecutable: dart.path,
        fixturePath: fixture.path,
        workingDirectory: root.path,
        environment: <String, String>{'PUB_CACHE': pubCache.path},
      ),
    );
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
    throw ArgumentError('Unknown DTD peer: $peer.');
  }
  return <String>{peer};
}
