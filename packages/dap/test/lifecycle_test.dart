import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('enforces initialize, launch, configuration, active, and disconnect',
      () {
    final connection = DapConnection();
    final initialize = connection.beginInitialize();
    connection.completeInitialize(
      initialize.seq,
      const <String, Object?>{'supportsConfigurationDoneRequest': true},
    );
    final launch = connection.beginLaunch(const {'program': 'main.dart'});
    connection.completeStart(launch.seq);
    connection.receiveEvent(
      seq: 1,
      event: 'initialized',
      body: const <String, Object?>{},
    );
    expect(connection.lifecycle, DapConnectionLifecycle.configuring);

    final breakpoints = connection.beginRequest(
      'setBreakpoints',
      arguments: const <String, Object?>{
        'source': <String, Object?>{'path': '/workspace/main.dart'},
        'breakpoints': <Object?>[],
      },
    );
    connection.completeResponse(
      requestSeq: breakpoints.seq,
      command: 'setBreakpoints',
    );
    expect(
      () => connection.beginRequest('threads'),
      throwsA(
        isA<DapStateException>().having(
          (error) => error.code,
          'code',
          'dap_request_out_of_state',
        ),
      ),
    );

    final configuration = connection.beginConfigurationDone();
    connection.completeConfiguration(configuration.seq);
    expect(connection.lifecycle, DapConnectionLifecycle.active);

    connection.receiveEvent(
      seq: 2,
      event: 'terminated',
      body: const <String, Object?>{},
    );
    expect(connection.lifecycle, DapConnectionLifecycle.terminated);
    final disconnect = connection.beginDisconnect();
    connection.completeDisconnect(disconnect.seq);
    expect(connection.lifecycle, DapConnectionLifecycle.disconnected);
  });

  test('launch and attach are mutually exclusive', () {
    final connection = _initializedConnection();
    connection.beginAttach(const {});
    expect(
      () => connection.beginLaunch(const {}),
      throwsA(isA<DapStateException>()),
    );
  });

  test('becomes active when configurationDone is not supported', () {
    for (final initializedEventFirst in <bool>[false, true]) {
      final connection = _initializedConnection();
      final launch = connection.beginLaunch(const {});
      if (initializedEventFirst) {
        connection.receiveEvent(
          seq: 1,
          event: 'initialized',
          body: const <String, Object?>{},
        );
        connection.completeStart(launch.seq);
      } else {
        connection.completeStart(launch.seq);
        connection.receiveEvent(
          seq: 1,
          event: 'initialized',
          body: const <String, Object?>{},
        );
      }

      expect(connection.lifecycle, DapConnectionLifecycle.active);
      expect(connection.beginRequest('threads'), isA<DapPendingRequest>());
      expect(
        connection.beginRequest(
          'setBreakpoints',
          arguments: const <String, Object?>{
            'source': <String, Object?>{'path': '/workspace/main.dart'},
            'breakpoints': <Object?>[],
          },
        ),
        isA<DapPendingRequest>(),
      );
      expect(
        connection.beginConfigurationDone,
        throwsA(isA<DapStateException>()),
      );
    }
  });
}

DapConnection _initializedConnection() {
  final connection = DapConnection();
  final initialize = connection.beginInitialize();
  connection.completeInitialize(initialize.seq, const <String, Object?>{});
  return connection;
}
