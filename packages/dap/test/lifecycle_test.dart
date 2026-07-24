import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart'
    show JsonValue, JsonValueException;
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

  test('invalid start arguments do not change lifecycle state', () {
    final startCases = <(
      String,
      DapPendingRequest Function(DapConnection, JsonValue),
    )>[
      ('launch', (connection, arguments) => connection.beginLaunch(arguments)),
      ('attach', (connection, arguments) => connection.beginAttach(arguments)),
    ];

    for (final (name, beginStart) in startCases) {
      final connection = _initializedConnection();
      final nextSequence = connection.nextSequence;

      for (final invalidArguments in <Object?>[
        DateTime.utc(2026),
        <String, Object?>{
          'nested': <Object?>[double.infinity],
        },
      ]) {
        expect(
          () => beginStart(connection, invalidArguments),
          throwsA(isA<JsonValueException>()),
          reason: '$name must validate arguments before changing state',
        );
        expect(connection.lifecycle, DapConnectionLifecycle.initialized);
        expect(connection.nextSequence, nextSequence);
      }

      final pending = beginStart(connection, const <String, Object?>{});
      expect(pending.seq, nextSequence);
      expect(connection.lifecycle, DapConnectionLifecycle.startPending);
    }
  });

  test('configures after initialized before the start response', () {
    final connection = DapConnection();
    final initialize = connection.beginInitialize();
    connection.completeInitialize(
      initialize.seq,
      const <String, Object?>{'supportsConfigurationDoneRequest': true},
    );
    final launch = connection.beginLaunch(const <String, Object?>{});

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
    final configuration = connection.beginConfigurationDone();
    connection.completeConfiguration(configuration.seq);

    expect(connection.lifecycle, DapConnectionLifecycle.startPending);
    expect(
      () => connection.beginRequest('threads'),
      throwsA(isA<DapStateException>()),
    );

    connection.completeStart(launch.seq);
    expect(connection.lifecycle, DapConnectionLifecycle.active);
    expect(connection.beginRequest('threads'), isA<DapPendingRequest>());
  });

  test('failed start response enters an explicit failed lifecycle', () {
    for (final completeThroughGenericResponse in <bool>[false, true]) {
      final connection = DapConnection();
      final initialize = connection.beginInitialize();
      connection.completeInitialize(
        initialize.seq,
        const <String, Object?>{'supportsConfigurationDoneRequest': true},
      );
      final launch = connection.beginLaunch(const <String, Object?>{});
      connection.receiveEvent(
        seq: 1,
        event: 'initialized',
        body: const <String, Object?>{},
      );
      final failure = StateError('launch rejected');

      if (completeThroughGenericResponse) {
        connection.completeResponse(
          requestSeq: launch.seq,
          command: 'launch',
          failure: failure,
        );
      } else {
        connection.completeStart(launch.seq, failure: failure);
      }

      expect(launch.done, isTrue);
      expect(launch.failure, same(failure));
      expect(connection.lifecycle, DapConnectionLifecycle.startFailed);
      expect(
        connection.beginConfigurationDone,
        throwsA(isA<DapStateException>()),
      );
      expect(
        () => connection.beginRequest('setBreakpoints'),
        throwsA(isA<DapStateException>()),
      );
      expect(connection.beginDisconnect(), isA<DapPendingRequest>());
    }
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
          throwsA(isA<DapStateException>()),
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
