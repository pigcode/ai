import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('initialize is first, once, and publishes immutable capabilities', () {
    final connection = DapConnection();
    final initialize = connection.beginInitialize();
    expect(initialize.seq, 1);
    expect(connection.lifecycle, DapConnectionLifecycle.initializePending);
    expect(
      () => connection.beginRequest('threads'),
      throwsA(isA<DapStateException>()),
    );
    expect(
      () => connection.beginInitialize(),
      throwsA(isA<DapStateException>()),
    );

    final source = <String, Object?>{'supportsCompletionsRequest': true};
    connection.completeInitialize(initialize.seq, source);
    source['supportsCompletionsRequest'] = false;

    expect(connection.lifecycle, DapConnectionLifecycle.initialized);
    expect(connection.capabilities.supportsCommand('completions'), isTrue);
  });
}
