import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/in_memory_agent_store.dart';
import '../support/kernel_fixture.dart';

void main() {
  test('createSession persists only Session genesis', () async {
    final fixture = KernelFixture();
    final (receipt, _) = await fixture.createSession();

    expect(receipt.type, AgentCommandType.createSession);
    expect(receipt.eventIds, hasLength(1));
    expect(receipt.acceptedThroughSequence, 1);
    expect(receipt.sessionHandle!.head.sequence, 1);

    final projection = await fixture.kernel.loadProjection(receipt.sessionId);
    expect(projection.definitionRef!.value, 'agent:test');
    expect(projection.capabilitySnapshot.value['run'], isTrue);
    expect(projection.runs, isEmpty);
    expect(projection.currentRunId, isNull);
  });

  test('receipt loss retry returns original Session without reallocating',
      () async {
    final store = InMemoryAgentStore(loseNextCreateReceipt: true);
    final fixture = KernelFixture(store: store);
    final root = await store.loadRoot();
    final command = CreateSessionCommand(
      commandId: createCommandId,
      expectedRootHead: root.head,
      definitionRef: const AgentDefinitionRef('agent:test'),
      capabilitySnapshot: CapabilitySnapshot.empty(),
    );

    await expectLater(
      fixture.kernel.createSession(command),
      throwsA(_commandError(AgentErrorCode.unavailable)),
    );
    final persistedSession = (await store.loadRoot()).sessionIds.single;

    final retry = await fixture.kernel.createSession(command);
    expect(retry.sessionId, persistedSession);
    expect((await store.loadRoot()).sessionIds, hasLength(1));
  });

  test('same create CommandId with different content is rejected', () async {
    final fixture = KernelFixture();
    final (receipt, original) = await fixture.createSession();

    await expectLater(
      fixture.kernel.createSession(
        CreateSessionCommand(
          commandId: original.commandId,
          expectedRootHead: original.expectedRootHead,
          definitionRef: const AgentDefinitionRef('agent:different'),
          capabilitySnapshot: original.capabilitySnapshot,
        ),
      ),
      throwsA(_commandError(AgentErrorCode.contentModified)),
    );
    expect((await fixture.store.loadRoot()).sessionIds, <SessionId>{
      receipt.sessionId,
    });
  });

  test('two create commands with one expected root produce one allocation',
      () async {
    final fixture = KernelFixture();
    final root = await fixture.store.loadRoot();
    final commands = <CreateSessionCommand>[
      CreateSessionCommand(
        commandId: createCommandId,
        expectedRootHead: root.head,
        definitionRef: const AgentDefinitionRef('agent:first'),
        capabilitySnapshot: CapabilitySnapshot.empty(),
      ),
      CreateSessionCommand(
        commandId: startCommandId,
        expectedRootHead: root.head,
        definitionRef: const AgentDefinitionRef('agent:second'),
        capabilitySnapshot: CapabilitySnapshot.empty(),
      ),
    ];
    final outcomes = await Future.wait<Object>(
      commands.map((command) async {
        try {
          return await fixture.kernel.createSession(command);
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
    expect((await fixture.store.loadRoot()).sessionIds, hasLength(1));
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
