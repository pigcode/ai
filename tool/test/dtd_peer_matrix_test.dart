import 'dart:io';

import '../src/dtd_peer_harness.dart';

void main() {
  final report = DtdPeerReport(
    peer: 'dart-3.6.0-dtd',
    release: '3.6.0',
    sdkRevision: 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04',
    inventoryDigest:
        'f76a7f5a18251640a19bb5be1dfa7304f7d10b7b4237fe66bfccbf6e118e06d3',
    transport: 'websocket-json-rpc',
    scenarios: const <String>[
      'machineEvent',
      'stream',
      'service',
      'fileSystemDenied',
      'invalidRootSecret',
      'cleanup',
    ],
    observedErrorCodes: const <int>{142},
    elapsedMilliseconds: 1,
  );
  _expect(
    validateDtdPeerReport(report).isEmpty,
    'Complete DTD report should pass.',
  );

  final invalid = DtdPeerReport(
    peer: report.peer,
    release: report.release,
    sdkRevision: report.sdkRevision,
    inventoryDigest: '',
    transport: report.transport,
    scenarios: const <String>[],
    observedErrorCodes: const <int>{},
    elapsedMilliseconds: 0,
  );
  _expect(
    validateDtdPeerReport(invalid).isNotEmpty,
    'Empty or skipped DTD report must fail.',
  );
  final source = File('tool/src/dtd_peer_harness.dart').readAsStringSync();
  _expect(
    !source.contains('wireVersion') && !source.contains('dtdUri:'),
    'DTD report must not expose a fabricated version or daemon URI.',
  );
  stdout.writeln('PASS DTD peer matrix report gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
