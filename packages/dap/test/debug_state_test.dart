import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('tracks threads, stop state, stack, scopes, and variables', () {
    final state = DapDebugState(connectionId: 4)
      ..updateThreads(const [
        <String, Object?>{'id': 1, 'name': 'main'},
      ]);
    final pause = state.stop(threadId: 1, reason: 'breakpoint');
    state
      ..setStackFrames(
        threadId: 1,
        pauseGeneration: pause,
        frames: const [
          <String, Object?>{
            'id': 10,
            'name': 'main',
            'line': 3,
            'column': 1,
          },
        ],
      )
      ..setScopes(
        frameId: 10,
        pauseGeneration: pause,
        scopes: const [
          <String, Object?>{
            'name': 'Locals',
            'variablesReference': 20,
            'expensive': false,
          },
        ],
      )
      ..setVariables(
        variablesReference: 20,
        pauseGeneration: pause,
        variables: const [
          <String, Object?>{
            'name': 'value',
            'value': '1',
            'variablesReference': 0,
          },
        ],
      );

    expect(state.threads.single.name, 'main');
    expect(state.stackFrames(1).single.id, 10);
    expect(state.scopes(10).single.variablesReference, 20);
    expect(state.variables(20).single.name, 'value');
    state.continueThread(1);
    expect(state.isPaused(1), isFalse);
  });
}
