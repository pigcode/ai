import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';

void main() {
  test('lifecycle mutation makes the previous Session handle stale', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final stale = created.sessionHandle!;
    await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: stale,
        input: const <String, Object?>{'prompt': 'first'},
      ),
    );

    await expectLater(
      fixture.kernel.startRun(
        StartRunCommand(
          commandId: secondStartCommandId,
          handle: stale,
          input: const <String, Object?>{'prompt': 'second'},
        ),
      ),
      throwsA(_commandError(AgentErrorCode.staleHandle)),
    );
  });

  test('same sequence with a different digest is stale', () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final original = created.sessionHandle!;
    final badHead = AgentStoreHead(
      sequence: original.head.sequence,
      stateDigest: canonicalJsonSha256('wrong'),
      journalHeadDigest: original.head.journalHeadDigest,
      identityRegistryRootDigest: original.head.identityRegistryRootDigest,
      commandRegistryRootDigest: original.head.commandRegistryRootDigest,
      generation: original.head.generation,
      historyFloorSequence: original.head.historyFloorSequence,
    );

    await expectLater(
      fixture.kernel.startRun(
        StartRunCommand(
          commandId: startCommandId,
          handle: AgentSessionHandle(
            sessionId: original.sessionId,
            projectionGeneration: original.projectionGeneration,
            head: badHead,
          ),
          input: const <String, Object?>{},
        ),
      ),
      throwsA(_commandError(AgentErrorCode.staleHandle)),
    );
    expect(
      (await fixture.store.loadSession(created.sessionId)).head.sequence,
      1,
    );
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
