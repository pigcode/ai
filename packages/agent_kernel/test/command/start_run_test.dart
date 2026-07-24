import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';

void main() {
  test('startRun atomically persists created and input-recorded events',
      () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final receipt = await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{'prompt': 'hello'},
      ),
    );

    expect(receipt.eventIds, hasLength(2));
    expect(receipt.acceptedThroughSequence, 3);
    expect(receipt.sessionHandle!.head.sequence, 3);
    final projection = await fixture.kernel.loadProjection(receipt.sessionId);
    expect(projection.currentRunId, receipt.runId);
    expect(
      projection.runs[receipt.runId]!.state,
      AgentRunState.pending,
    );
    final events = await fixture.store.readEvents(receipt.sessionId);
    expect(
      events.events.map((event) => event.type),
      <AgentEventType>[
        AgentEventType.sessionCreated,
        AgentEventType.runCreated,
        AgentEventType.runInputRecorded,
      ],
    );
    expect(events.events.last.payload['prompt'], 'hello');
  });

  test('active Run precondition failure appends no event', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final first = await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{'prompt': 'first'},
      ),
    );

    await expectLater(
      fixture.kernel.startRun(
        StartRunCommand(
          commandId: secondStartCommandId,
          handle: first.sessionHandle!,
          input: const <String, Object?>{'prompt': 'second'},
        ),
      ),
      throwsA(_commandError(AgentErrorCode.preconditionFailed)),
    );
    expect(
      (await fixture.store.loadSession(created.sessionId)).head.sequence,
      3,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
