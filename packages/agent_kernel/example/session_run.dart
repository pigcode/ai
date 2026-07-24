import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import '../test/support/kernel_fixture.dart';
import '../test/support/running_kernel_fixture.dart';

Future<void> main() async {
  // This injected test Store is intentionally in-memory and not durable.
  final fixture = KernelFixture();
  final running = await prepareRunningRun(fixture);

  await fixture.kernel.commitTerminal(
    handle: running.handle,
    proposal: TerminalProposal(
      runId: running.runId,
      attemptId: running.attemptId,
      executionEpoch: 1,
      outcome: TerminalOutcome.completed,
      sourceId: 'driver-output',
      sourceWatermark: 1,
      causationId: running.driverCommandId,
      payload: const <String, Object?>{'result': 'done'},
    ),
    drainedSourceWatermarks: const <String, int>{'driver-output': 1},
  );

  final replayed = await fixture.kernel.loadProjection(running.sessionId);
  print(
    'session=${running.sessionId.value} '
    'run=${running.runId.value} '
    'state=${replayed.runs[running.runId]!.state.name}',
  );
}
