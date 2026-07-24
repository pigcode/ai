import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';
import '../support/ownership_fixture.dart';
import '../support/running_kernel_fixture.dart';

void main() {
  test('RuntimeResource defaults to Run ownership and can transfer', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final registered = await fixture.kernel.registerRuntimeResource(
      RegisterRuntimeResourceCommand(
        commandId: registerResourceCommandId,
        handle: running.handle,
        runId: running.runId,
      ),
    );
    var resource = (await fixture.kernel.loadProjection(running.sessionId))
        .resources[registered.runtimeResourceId]!;
    expect(resource.owner, RuntimeResourceOwner.run);
    expect(resource.ownerRunId, running.runId);

    await fixture.kernel.transferRuntimeResource(
      TransferRuntimeResourceCommand(
        commandId: transferResourceCommandId,
        handle: registered.sessionHandle!,
        runId: running.runId,
        runtimeResourceId: registered.runtimeResourceId!,
      ),
    );
    resource = (await fixture.kernel.loadProjection(running.sessionId))
        .resources[registered.runtimeResourceId]!;
    expect(resource.owner, RuntimeResourceOwner.session);
    expect(resource.ownerRunId, isNull);
    expect(resource.originRunId, running.runId);
  });

  test('RuntimeResource terminal outcome is persisted', () async {
    final fixture = KernelFixture();
    final running = await prepareRunningRun(fixture);
    final registered = await fixture.kernel.registerRuntimeResource(
      RegisterRuntimeResourceCommand(
        commandId: registerResourceCommandId,
        handle: running.handle,
        runId: running.runId,
      ),
    );
    await fixture.kernel.recordRuntimeResourceOutcome(
      RecordRuntimeResourceOutcomeCommand(
        commandId: resourceOutcomeCommandId,
        handle: registered.sessionHandle!,
        runId: running.runId,
        runtimeResourceId: registered.runtimeResourceId!,
        outcome: RuntimeResourceOutcome.outcomeUnknown,
      ),
    );

    final resource = (await fixture.kernel.loadProjection(running.sessionId))
        .resources[registered.runtimeResourceId]!;
    expect(resource.state, RuntimeResourceState.outcomeUnknown);
    expect(resource.terminalDigest, isNotNull);
  });
}
