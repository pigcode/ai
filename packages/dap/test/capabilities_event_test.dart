import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('capabilities event creates a new immutable generation', () {
    final connection = _activeConnection();
    final initial = connection.capabilities;
    expect(initial.supportsCommand('readMemory'), isFalse);
    expect(
      () => connection.beginRequest('readMemory'),
      throwsA(isA<DapCapabilityException>()),
    );
    final seqBefore = connection.nextSequence;

    connection.receiveEvent(
      seq: 2,
      event: 'capabilities',
      body: const <String, Object?>{
        'capabilities': <String, Object?>{
          'supportsReadMemoryRequest': true,
        },
      },
    );

    expect(connection.capabilities.generation, initial.generation + 1);
    expect(connection.capabilities.supportsCommand('readMemory'), isTrue);
    expect(initial.supportsCommand('readMemory'), isFalse);
    expect(connection.nextSequence, seqBefore);
    expect(connection.beginRequest('readMemory'), isA<DapPendingRequest>());
  });
}

DapConnection _activeConnection() {
  final connection = DapConnection();
  final initialize = connection.beginInitialize();
  connection.completeInitialize(
    initialize.seq,
    const <String, Object?>{'supportsConfigurationDoneRequest': true},
  );
  final launch = connection.beginLaunch(const {});
  connection
    ..completeStart(launch.seq)
    ..receiveEvent(seq: 1, event: 'initialized', body: const {});
  final configuration = connection.beginConfigurationDone();
  connection.completeConfiguration(configuration.seq);
  return connection;
}
