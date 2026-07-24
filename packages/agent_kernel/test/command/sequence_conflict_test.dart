import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/in_memory_agent_store.dart';
import '../support/kernel_fixture.dart';

void main() {
  test('two concurrent starts from one handle accept exactly one', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final commands = <StartRunCommand>[
      StartRunCommand(
        commandId: startCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{'prompt': 'first'},
      ),
      StartRunCommand(
        commandId: secondStartCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{'prompt': 'second'},
      ),
    ];
    final outcomes = await Future.wait<Object>(
      commands.map((command) async {
        try {
          return await fixture.kernel.startRun(command);
        } on Object catch (error) {
          return error;
        }
      }),
    );

    expect(outcomes.whereType<AgentCommandReceipt>(), hasLength(1));
    expect(
      outcomes.whereType<AgentCommandError>().single.code,
      AgentErrorCode.staleHandle,
    );
    expect(
      (await fixture.store.loadSession(created.sessionId)).head.sequence,
      3,
    );
  });

  test('store failure before commit never fabricates success', () async {
    final store = InMemoryAgentStore();
    final fixture = KernelFixture(store: store);
    final (created, _) = await fixture.createSession();
    store.failNextAppendBeforeCommit = true;

    await expectLater(
      fixture.kernel.startRun(
        StartRunCommand(
          commandId: startCommandId,
          handle: created.sessionHandle!,
          input: const <String, Object?>{},
        ),
      ),
      throwsA(_commandError(AgentErrorCode.unavailable)),
    );
    expect(
      (await store.loadSession(created.sessionId)).head.sequence,
      1,
    );
    expect(
      await store.lookupAcceptedCommand(created.sessionId, startCommandId),
      isNull,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
