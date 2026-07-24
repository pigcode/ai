import 'dart:io';

import '../src/vm_service_peer_harness.dart';

void main() {
  const report = VmServicePeerReport(
    peer: 'dart-3.6.0-vm-service',
    release: '3.6.0',
    sdkRevision: 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04',
    wireVersion: '4.16',
    transport: 'websocket-json-rpc',
    observedProtocols: <String>['VM Service@4.16'],
    scenarios: <String>[
      'machineEvent',
      'version',
      'supportedProtocols',
      'vm',
      'stream',
      'isolate',
      'object',
      'temporaryIdExpired',
      'disconnect',
      'cleanup',
    ],
    sentinelKind: 'Expired',
    elapsedMilliseconds: 1,
  );
  _expect(
    validateVmServicePeerReport(report).isEmpty,
    'Complete VM Service report should pass.',
  );

  const invalid = VmServicePeerReport(
    peer: 'dart-3.6.0-vm-service',
    release: '3.6.0',
    sdkRevision: 'invalid',
    wireVersion: '4.15',
    transport: 'websocket-json-rpc',
    observedProtocols: <String>[],
    scenarios: <String>[],
    sentinelKind: '',
    elapsedMilliseconds: 0,
  );
  _expect(
    validateVmServicePeerReport(invalid).isNotEmpty,
    'Empty or skipped VM Service report must fail.',
  );

  final reportJson = report.toJson();
  _expect(
    !reportJson.containsKey('webSocketUri') &&
        !reportJson.containsKey('objectId') &&
        !reportJson.containsKey('isolateId'),
    'VM Service report must not expose connection or temporary identifiers.',
  );
  stdout.writeln('PASS VM Service peer matrix report gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
