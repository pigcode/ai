import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('supported protocol snapshot is immutable and connection-scoped', () {
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
        'protocols': <Object?>[
          <String, Object?>{
            'protocolName': 'DDS',
            'major': 1,
            'minor': 8,
          },
        ],
      },
    );

    final snapshot = connection.capabilities;
    expect(snapshot.supportsProtocol('DDS', minimumMajor: 1), isTrue);
    expect(snapshot.supportsRpc('getVM'), isTrue);
    expect(
      () => snapshot.protocols.add(
        const VmServiceSupportedProtocol(
          name: 'mutated',
          major: 1,
          minor: 0,
        ),
      ),
      throwsUnsupportedError,
    );

    final replacement = connection.reconnect();
    expect(
      () => replacement.assertCurrentSnapshot(snapshot),
      throwsA(isA<ToolingProtocolStateError>()),
    );
  });
}
