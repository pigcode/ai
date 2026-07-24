import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('requires version then supported protocols before ordinary RPCs', () {
    final connection = VmServiceConnection();
    expect(
      () => connection.beginRequest('getVM', params: const {}),
      throwsA(isA<ToolingProtocolStateError>()),
    );

    final version = connection.beginVersionQuery();
    expect(version.id, '1');
    connection.completeVersionQuery(
      version.id,
      const <String, Object?>{'type': 'Version', 'major': 4, 'minor': 21},
    );
    expect(
      connection.lifecycle,
      VmServiceConnectionLifecycle.versionNegotiated,
    );

    final protocols = connection.beginSupportedProtocolsQuery();
    connection.completeSupportedProtocolsQuery(
      protocols.id,
      const <String, Object?>{
        'type': 'ProtocolList',
        'protocols': <Object?>[
          <String, Object?>{
            'protocolName': 'VM Service',
            'major': 4,
            'minor': 21,
          },
        ],
      },
    );
    expect(connection.lifecycle, VmServiceConnectionLifecycle.ready);
    expect(connection.capabilities.wireVersion.toString(), '4.21');
  });

  test('close completes pending work exactly once', () {
    final connection = _readyConnection();
    final pending = connection.beginRequest('getVM', params: const {});
    connection.close();

    expect(pending.done, isTrue);
    expect(pending.failure, isA<ToolingProtocolStateError>());
    expect(() => connection.close(), returnsNormally);
  });
}

VmServiceConnection _readyConnection() {
  final connection = VmServiceConnection();
  final version = connection.beginVersionQuery();
  connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'type': 'Version', 'major': 4, 'minor': 21},
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
