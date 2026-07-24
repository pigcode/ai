import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('uses monotonic seq and matches request_seq plus command', () {
    final connection = _activeConnection();
    final threads = connection.beginRequest('threads');
    final stack = connection.beginRequest('stackTrace');
    expect(stack.seq, threads.seq + 1);

    expect(
      () => connection.completeResponse(
        requestSeq: threads.seq,
        command: 'stackTrace',
      ),
      throwsA(isA<DapCorrelationException>()),
    );
    expect(threads.done, isFalse);

    connection.completeResponse(
      requestSeq: threads.seq,
      command: 'threads',
    );
    expect(threads.done, isTrue);
    expect(
      () => connection.completeResponse(
        requestSeq: threads.seq,
        command: 'threads',
      ),
      throwsA(
        isA<DapCorrelationException>().having(
          (error) => error.code,
          'code',
          'dap_response_tombstoned',
        ),
      ),
    );
  });

  test('close completes pending requests exactly once', () {
    final connection = _activeConnection();
    final pending = connection.beginRequest('threads');
    connection.close();
    expect(pending.done, isTrue);
    expect(pending.failure, isA<DapStateException>());
    expect(() => connection.close(), returnsNormally);
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
