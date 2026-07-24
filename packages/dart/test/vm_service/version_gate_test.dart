import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('rejects unsupported major during the first RPC', () {
    final connection = VmServiceConnection();
    final version = connection.beginVersionQuery();

    expect(
      () => connection.completeVersionQuery(
        version.id,
        const <String, Object?>{'type': 'Version', 'major': 5, 'minor': 0},
      ),
      throwsA(
        isA<ToolingVersionError>().having(
          (error) => error.code,
          'code',
          'vm_service_major_unsupported',
        ),
      ),
    );
    expect(connection.lifecycle, VmServiceConnectionLifecycle.closed);
  });

  test('rejects a newer RPC before sending on protocol 4.16', () {
    final connection = _readyMinimumConnection();
    expect(
      () => connection.beginRequest(
        'getQueuedMicrotasks',
        params: const <String, Object?>{'isolateId': 'isolates/1'},
      ),
      throwsA(isA<ToolingVersionError>()),
    );
  });
}

VmServiceConnection _readyMinimumConnection() {
  final connection = VmServiceConnection();
  final version = connection.beginVersionQuery();
  connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'type': 'Version', 'major': 4, 'minor': 16},
  );
  final protocols = connection.beginSupportedProtocolsQuery();
  connection.completeSupportedProtocolsQuery(
    protocols.id,
    const <String, Object?>{
      'type': 'ProtocolList',
      'protocols': <Object?>[],
    },
  );
  return connection;
}
