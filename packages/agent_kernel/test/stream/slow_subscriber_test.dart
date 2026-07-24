import 'dart:async';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('paused observer is detached when its bounded queue fills', () async {
    final subscription = AgentEventSubscription(
      cursor: AgentEventCursor(sessionId: _session, sequence: 0),
      queueLimit: 2,
    );
    final errors = <Object>[];
    final completed = Completer<void>();
    final listener = subscription.stream.listen(
      (_) {},
      onError: errors.add,
      onDone: completed.complete,
    );
    listener.pause();
    subscription.completeReplay();
    subscription.acceptLive(_event(1));
    subscription.acceptLive(_event(2));
    subscription.acceptLive(_event(3));
    listener.resume();
    await completed.future;

    expect(subscription.isClosed, isTrue);
    expect(
      errors.single,
      isA<SubscriptionError>().having(
        (error) => error.code,
        'code',
        SubscriptionErrorCode.queueOverflow,
      ),
    );
  });
}

AgentEvent _event(int sequence) => AgentEvent(
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
      payload: const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

final _session = SessionId.parse('ses_00000000000000000000000000000000');
final _command = CommandId.parse('cmd_00000000000000000000000000000000');
