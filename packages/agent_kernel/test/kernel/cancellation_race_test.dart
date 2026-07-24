import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('authoritative completion committed before cancel wins the race',
      () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final terminalHandle = await fixture.kernel.commitTerminal(
      handle: running.handle,
      proposal: TerminalProposal(
        runId: running.runId,
        attemptId: running.attemptId,
        executionEpoch: 1,
        outcome: TerminalOutcome.completed,
        sourceId: 'source:test',
        sourceWatermark: 1,
        causationId: running.driverCommandId,
        payload: const <String, Object?>{},
      ),
      drainedSourceWatermarks: const <String, int>{'source:test': 1},
    );

    await expectLater(
      fixture.kernel.cancelRun(
        CancelRunCommand(
          commandId: cancelCommandId,
          handle: terminalHandle,
          runId: running.runId,
        ),
      ),
      throwsA(_commandError(AgentErrorCode.preconditionFailed)),
    );
    final projection = await fixture.kernel.loadProjection(running.sessionId);
    expect(
      projection.runs[running.runId]!.state,
      AgentRunState.completed,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
