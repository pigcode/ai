import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/dap_peer_harness.dart';
import 'src/tooling_peer_cache.dart';
import 'src/tooling_process_harness.dart';

const _knownPeers = <String>{
  'dart-3.6.0',
  'dart-3.12.2',
  'js-debug-1.117.0',
};

Future<void> main(List<String> arguments) async {
  final peers = _selectedPeers(arguments);
  final cache = ToolingPeerCache(root: Directory.current.absolute);
  for (final peer in peers) {
    final report = peer.startsWith('dart-')
        ? await _runDart(cache, peer.substring('dart-'.length))
        : await _runJsDebug(cache);
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
    throw ArgumentError('Unknown DAP peer: $peer.');
  }
  return <String>{peer};
}

Future<DapPeerReport> _runDart(
  ToolingPeerCache cache,
  String release,
) async {
  final sdk = await cache.ensureDartSdk(release);
  final dart = ToolingPeerCache.dartExecutable(sdk);
  final workspace = Directory.fromUri(
    cache.root.uri.resolve('tool/fixtures/dap/dart_app/'),
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
      'Dart $release DAP fixture pub get failed: ${resolve.stderr}',
    );
  }
  final program = File.fromUri(workspace.uri.resolve('bin/main.dart')).absolute;
  final transport = await DapStdioPeerTransport.start(
    ToolingProcessCommand(
      executable: dart.path,
      arguments: const <String>['debug_adapter'],
      workingDirectory: workspace.path,
    ),
  );
  return runDapPeer(
    DapPeerCommand(
      peer: 'dart-$release',
      family: 'dart-debug-adapter',
      release: release,
      transportName: 'stdio-content-length',
      transport: transport,
      launchArguments: <String, Object?>{
        'program': program.path,
        'cwd': workspace.absolute.path,
        'noDebug': false,
      },
      sourcePath: program.path,
      breakpointLine: 2,
    ),
  );
}

Future<DapPeerReport> _runJsDebug(ToolingPeerCache cache) async {
  final pin = cache.manifest.releaseArchive('js-debug-v1.117.0');
  final release = await cache.ensureReleaseArchive(pin.peerId);
  final entrypoint = File.fromUri(release.uri.resolve(pin.entrypoint));
  final server = await Process.start(
    'node',
    <String>[entrypoint.path, '0', '127.0.0.1'],
    workingDirectory: release.path,
    environment: <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    },
    includeParentEnvironment: false,
  );
  final port = await _readServerPort(server);
  final transport = await DapSocketPeerTransport.connect(
    server: server,
    port: port,
  );
  final workspace = Directory.fromUri(
    cache.root.uri.resolve('tool/fixtures/dap/javascript_app/'),
  );
  final program = File.fromUri(workspace.uri.resolve('main.js')).absolute;
  return runDapPeer(
    DapPeerCommand(
      peer: 'js-debug-1.117.0',
      family: 'vscode-js-debug',
      release: '1.117.0',
      transportName: 'tcp-content-length',
      transport: transport,
      launchArguments: <String, Object?>{
        'type': 'pwa-node',
        'request': 'launch',
        'name': 'Pigcode fixture',
        'program': program.path,
        'cwd': workspace.absolute.path,
        'console': 'internalConsole',
        'stopOnEntry': true,
      },
      sourcePath: program.path,
      breakpointLine: 3,
      supportsStartDebugging: true,
    ),
  );
}

Future<int> _readServerPort(Process server) async {
  final lines = StreamIterator<String>(
    server.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    for (var index = 0; index < 20; index += 1) {
      final available =
          await lines.moveNext().timeout(const Duration(seconds: 10));
      if (!available) {
        break;
      }
      final match = RegExp(
        r'^Debug server listening at .+:([0-9]{1,5})$',
      ).firstMatch(lines.current);
      if (match != null) {
        final port = int.parse(match.group(1)!);
        if (port > 0 && port <= 65535) {
          return port;
        }
      }
    }
  } finally {
    await lines.cancel();
  }
  server.kill();
  await server.exitCode;
  throw StateError('js-debug did not report its TCP port.');
}
