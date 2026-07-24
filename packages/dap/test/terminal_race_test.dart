import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('terminated, exited, disconnect, and close have one terminal edge', () {
    final terminal = DapSessionTerminal();
    expect(terminal.recordTerminated(), isTrue);
    expect(terminal.recordExited(exitCode: 0), isFalse);
    expect(terminal.recordDisconnected(), isFalse);
    expect(terminal.recordTerminated(), isFalse);
    expect(terminal.terminalTransitionCount, 1);
    expect(terminal.terminated, isTrue);
    expect(terminal.exited, isTrue);
    expect(terminal.disconnected, isTrue);
  });

  test('event queue preserves order and rejects duplicate seq', () {
    final events = DapEventQueue(maxEvents: 2)
      ..add(seq: 1, event: 'initialized', body: const {})
      ..add(seq: 2, event: 'terminated', body: const {});
    expect(events.events.map((event) => event.event), [
      'initialized',
      'terminated',
    ]);
    expect(
      () => events.add(seq: 2, event: 'exited', body: const {'exitCode': 0}),
      throwsA(isA<DapCorrelationException>()),
    );
    expect(
      () => events.add(seq: 3, event: 'exited', body: const {'exitCode': 0}),
      throwsA(isA<DapResourceLimitException>()),
    );
  });
}
