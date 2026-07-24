import 'dart:io';

import '../src/analysis_server_peer_harness.dart';

void main() {
  final minimum = AnalysisServerPeerReport(
    peer: 'dart-3.6.0-analysis-server',
    release: '3.6.0',
    apiVersion: '1.38.0',
    transport: 'stdio-ndjson',
    capabilities: const <String, Object?>{
      'supportsUris': false,
      'statusSubscription': true,
    },
    scenarios: const <String>[
      'version',
      'clientCapabilities',
      'setRoots',
      'status',
      'errors',
      'hover',
      'shutdown',
    ],
    errorCount: 1,
    hoverCount: 1,
    elapsedMilliseconds: 1,
  );
  _expect(
    validateAnalysisServerPeerReport(minimum).isEmpty,
    'Complete minimum Analysis Server report should pass.',
  );

  final invalid = AnalysisServerPeerReport(
    peer: minimum.peer,
    release: minimum.release,
    apiVersion: '1.40.1',
    transport: minimum.transport,
    capabilities: const <String, Object?>{},
    scenarios: const <String>[],
    errorCount: 0,
    hoverCount: 0,
    elapsedMilliseconds: 0,
  );
  _expect(
    validateAnalysisServerPeerReport(invalid).isNotEmpty,
    'Skipped or release-guessed Analysis Server report must fail.',
  );
  stdout.writeln('PASS Analysis Server peer matrix report gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
