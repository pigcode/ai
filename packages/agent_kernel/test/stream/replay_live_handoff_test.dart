import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/kernel_fixture.dart';

void main() {
  test('append at every replay/live boundary has no gap or duplicate',
      () async {
    final events = <AgentEvent>[
      for (var sequence = 1; sequence <= 8; sequence++) _event(sequence),
    ];

    for (var split = 0; split <= events.length; split++) {
      final subscription = AgentEventSubscription(
        cursor: AgentEventCursor(sessionId: _session, sequence: 0),
        queueLimit: 32,
      );
      final received = <AgentEvent>[];
      final done = subscription.stream.listen(received.add).asFuture<void>();
      for (final event in events.skip(split)) {
        subscription.acceptLive(event);
      }
      for (final event in events.take(split)) {
        subscription.acceptReplay(event);
      }
      subscription.completeReplay();
      subscription.closeForIdle();
      await done;

      expect(
        received.map((event) => event.sequence),
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
        reason: 'split=$split',
      );
    }
  });

  test('replay/live overlap deduplicates exact event only', () async {
    final events = <AgentEvent>[_event(1), _event(2), _event(3)];
    final subscription = AgentEventSubscription(
      cursor: AgentEventCursor(sessionId: _session, sequence: 0),
    );
    final received = <AgentEvent>[];
    final done = subscription.stream.listen(received.add).asFuture<void>();
    subscription.acceptLive(events[1]);
    for (final event in events) {
      subscription.acceptReplay(event);
    }
    subscription.completeReplay();
    subscription.closeForIdle();
    await done;

    expect(received.map((event) => event.sequence), <int>[1, 2, 3]);
  });

  test('same sequence with changed content fails closed', () async {
    final subscription = AgentEventSubscription(
      cursor: AgentEventCursor(sessionId: _session, sequence: 0),
    );
    final errors = <Object>[];
    final completed = Completer<void>();
    subscription.stream.listen(
      (_) {},
      onError: errors.add,
      onDone: completed.complete,
    );
    subscription.acceptLive(
      _event(
        1,
        payload: const <String, Object?>{'changed': true},
      ),
    );
    subscription.acceptReplay(_event(1));
    subscription.completeReplay();
    await completed.future;

    expect(
      errors.single,
      isA<SubscriptionError>().having(
        (error) => error.code,
        'code',
        SubscriptionErrorCode.sequenceConflict,
      ),
    );
  });

  test('Kernel attaches live before replay and emits persisted order',
      () async {
    final fixture = KernelFixture();
    final (created, _) = await fixture.createSession();
    final subscription = fixture.kernel.subscribeEvents(
      sessionId: created.sessionId,
    );
    final events = <AgentEvent>[];
    final done = subscription.stream.listen(events.add).asFuture<void>();
    await fixture.kernel.startRun(
      StartRunCommand(
        commandId: startCommandId,
        handle: created.sessionHandle!,
        input: const <String, Object?>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    subscription.closeForIdle();
    await done;

    expect(events.map((event) => event.sequence), <int>[1, 2, 3]);
  });
}

AgentEvent _event(
  int sequence, {
  Map<String, Object?> payload = const <String, Object?>{},
}) =>
    AgentEvent(
      eventId: EventId.parse(
        'evt_${sequence.toString().padLeft(32, '0')}',
      ),
      schemaVersion: 1,
      sessionId: _session,
      sequence: sequence,
      recordedAt: DateTime.utc(2026, 7, 24),
      type: sequence == 1
          ? AgentEventType.sessionCreated
          : AgentEventType.sessionCapabilitiesPinned,
      causationId: _command,
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _command = CommandId.parse('cmd_00000000000000000000000000000000');
