import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('references expire on continue, restart, and disconnect generation', () {
    final state = DapDebugState(connectionId: 1);
    final pause = state.stop(threadId: 1, reason: 'entry');
    final references = DapReferenceRegistry()
      ..bind(
        reference: 20,
        kind: DapReferenceKind.variables,
        connectionId: state.connectionId,
        sessionGeneration: state.sessionGeneration,
        pauseGeneration: pause,
      );
    expect(references.resolve(20, state: state).reference, 20);

    state.continueThread(1);
    expect(
      () => references.resolve(20, state: state),
      throwsA(isA<DapDebugStateException>()),
    );

    final restartPause = state
      ..restart()
      ..stop(threadId: 1, reason: 'restart');
    references.bind(
      reference: 21,
      kind: DapReferenceKind.frame,
      connectionId: state.connectionId,
      sessionGeneration: state.sessionGeneration,
      pauseGeneration: restartPause.pauseGeneration,
    );
    state.disconnect();
    expect(
      () => references.resolve(21, state: state),
      throwsA(isA<DapDebugStateException>()),
    );
  });
}
