import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/in_memory_agent_store.dart';
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

  test('concurrent same run command returns and publishes stored events',
      () async {
    final store = InMemoryAgentStore(
      synchronizeNextCommandLookups: true,
    );
    final fixture = KernelFixture(store: store);
    final (created, _) = await fixture.createSession();
    final command = StartRunCommand(
      commandId: startCommandId,
      handle: created.sessionHandle!,
      input: const <String, Object?>{'prompt': 'race'},
    );
    final subscription = fixture.kernel.subscribeEvents(
      sessionId: created.sessionId,
    );
    final received = <AgentEvent>[];
    Object? streamError;
    final receivedThroughRun = Completer<void>();
    final listener = subscription.stream.listen(
      (event) {
        received.add(event);
        if (received.length == 3 && !receivedThroughRun.isCompleted) {
          receivedThroughRun.complete();
        }
      },
      onError: (Object error) {
        streamError = error;
        if (!receivedThroughRun.isCompleted) {
          receivedThroughRun.complete();
        }
      },
    );

    final receipts = await Future.wait(<Future<AgentCommandReceipt>>[
      fixture.kernel.startRun(command),
      fixture.kernel.startRun(command),
    ]);
    await receivedThroughRun.future.timeout(const Duration(seconds: 1));

    expect(receipts[1].toJson(), receipts[0].toJson());
    expect(streamError, isNull);
    expect(subscription.isClosed, isFalse);
    final persisted = await store.readEvents(created.sessionId);
    expect(
      received.map((event) => event.eventId),
      persisted.events.map((event) => event.eventId),
    );

    await listener.cancel();
  });
}

Matcher _commandError(AgentErrorCode code) =>
    isA<AgentCommandError>().having((error) => error.code, 'code', code);
