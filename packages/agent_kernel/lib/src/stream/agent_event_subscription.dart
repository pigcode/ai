import 'dart:async';

import '../event/agent_event.dart';
import '../id/opaque_id.dart';
import '../json/canonical_json.dart';
import 'agent_event_cursor.dart';
import 'subscription_error.dart';

final class AgentEventSubscription {
  AgentEventSubscription({
    required AgentEventCursor cursor,
    this.runId,
    this.queueLimit = 256,
    void Function()? onDetach,
  })  : _cursor = cursor,
        _onDetach = onDetach {
    if (queueLimit <= 0) {
      throw ArgumentError.value(queueLimit, 'queueLimit', 'Must be positive.');
    }
    _controller = StreamController<AgentEvent>(
      sync: true,
      onListen: _onListen,
      onPause: _onPause,
      onResume: _onResume,
      onCancel: _onCancel,
    );
  }

  final RunId? runId;
  final int queueLimit;
  final void Function()? _onDetach;
  late final StreamController<AgentEvent> _controller;
  final List<AgentEvent> _liveDuringReplay = <AgentEvent>[];
  final List<AgentEvent> _deliveryQueue = <AgentEvent>[];
  final Map<int, (EventId, String)> _recent = <int, (EventId, String)>{};
  AgentEventCursor _cursor;
  bool _replaying = true;
  bool _listening = false;
  bool _paused = false;
  bool _detached = false;
  bool _closeAfterDrain = false;

  Stream<AgentEvent> get stream => _controller.stream;

  AgentEventCursor get cursor => _cursor;

  bool get isClosed => _detached;

  void acceptReplay(AgentEvent event) {
    if (!_replaying || _detached) return;
    _acceptOrdered(event);
  }

  void acceptLive(AgentEvent event) {
    if (_detached) return;
    if (_replaying) {
      if (_liveDuringReplay.length >= queueLimit) {
        fail(
          const SubscriptionError(
            SubscriptionErrorCode.queueOverflow,
            'Live handoff queue reached its configured limit.',
          ),
        );
        return;
      }
      _liveDuringReplay.add(event);
      return;
    }
    _acceptOrdered(event);
  }

  void completeReplay() {
    if (!_replaying || _detached) return;
    _replaying = false;
    _liveDuringReplay.sort(
      (left, right) => left.sequence.compareTo(right.sequence),
    );
    final buffered = List<AgentEvent>.of(_liveDuringReplay);
    _liveDuringReplay.clear();
    for (final event in buffered) {
      if (_detached) return;
      _acceptOrdered(event);
    }
  }

  void closeForIdle() {
    if (_detached) return;
    _closeAfterDrain = true;
    _drain();
  }

  void fail(SubscriptionError error) {
    if (_detached) return;
    _detached = true;
    _liveDuringReplay.clear();
    _deliveryQueue.clear();
    _controller
      ..addError(error)
      ..close();
    _onDetach?.call();
  }

  void _acceptOrdered(AgentEvent event) {
    if (event.sessionId != _cursor.sessionId) {
      fail(
        const SubscriptionError(
          SubscriptionErrorCode.sessionMismatch,
          'Event does not belong to the subscribed Session.',
        ),
      );
      return;
    }
    final digest = canonicalJsonSha256(event.toJson());
    final known = _recent[event.sequence];
    if (event.sequence <= _cursor.sequence) {
      final cursorMatches = event.sequence == _cursor.sequence &&
          event.eventId == _cursor.eventId &&
          digest == _cursor.eventDigest;
      if ((known != null && known.$1 == event.eventId && known.$2 == digest) ||
          cursorMatches) {
        return;
      }
      fail(
        const SubscriptionError(
          SubscriptionErrorCode.sequenceConflict,
          'Sequence was reused with different event content.',
        ),
      );
      return;
    }
    if (event.sequence != _cursor.sequence + 1) {
      fail(
        const SubscriptionError(
          SubscriptionErrorCode.sequenceConflict,
          'Event stream contains a sequence gap.',
        ),
      );
      return;
    }
    _recent[event.sequence] = (event.eventId, digest);
    while (_recent.length > 256) {
      _recent.remove(_recent.keys.first);
    }
    _cursor = AgentEventCursor(
      sessionId: event.sessionId,
      sequence: event.sequence,
      eventId: event.eventId,
      eventDigest: digest,
    );
    if (runId == null || event.runId == runId) {
      _enqueue(event);
    }
    if (runId != null && event.runId == runId && event.type.terminal) {
      _closeAfterDrain = true;
      _drain();
    }
  }

  void _enqueue(AgentEvent event) {
    if (!_listening || _paused || _deliveryQueue.isNotEmpty) {
      if (_deliveryQueue.length >= queueLimit) {
        fail(
          const SubscriptionError(
            SubscriptionErrorCode.queueOverflow,
            'Observer delivery queue reached its configured limit.',
          ),
        );
        return;
      }
      _deliveryQueue.add(event);
      return;
    }
    _controller.add(event);
  }

  void _drain() {
    if (!_listening || _paused || _detached) return;
    while (_deliveryQueue.isNotEmpty && !_paused && !_detached) {
      _controller.add(_deliveryQueue.removeAt(0));
    }
    if (_closeAfterDrain && _deliveryQueue.isEmpty && !_detached) {
      _detached = true;
      _controller.close();
      _onDetach?.call();
    }
  }

  void _onListen() {
    _listening = true;
    _drain();
  }

  void _onPause() {
    _paused = true;
  }

  void _onResume() {
    _paused = false;
    _drain();
  }

  Future<void> _onCancel() async {
    if (_detached) return;
    _detached = true;
    _liveDuringReplay.clear();
    _deliveryQueue.clear();
    _onDetach?.call();
  }
}
