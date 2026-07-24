import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';

void main() {
  test('same startRun command content reconstructs the persisted receipt',
      () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final command = StartRunCommand(
      commandId: startCommandId,
      handle: created.sessionHandle!,
      input: const <String, Object?>{'prompt': 'same'},
    );
    final first = await fixture.kernel.startRun(command);
    final retry = await fixture.kernel.startRun(command);

    expect(retry.toJson(), first.toJson());
    expect(
      (await fixture.store.loadSession(created.sessionId)).head.sequence,
      3,
    );
  });

  test('same startRun CommandId with different content is rejected', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final handle = created.sessionHandle!;
    await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: handle,
        input: const <String, Object?>{'prompt': 'first'},
      ),
    );

    await expectLater(
      fixture.kernel.startRun(
        StartRunCommand(
          commandId: startCommandId,
          handle: handle,
          input: const <String, Object?>{'prompt': 'different'},
        ),
      ),
      throwsA(_commandError(AgentErrorCode.contentModified)),
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
