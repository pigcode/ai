import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'connection.dart';
import 'models.dart';

enum DtdStreamSubscriptionState {
  listenPending,
  active,
  cancelPending,
}

final class DtdStreamEvent {
  const DtdStreamEvent({
    required this.sequence,
    required this.streamId,
    required this.eventKind,
    required this.eventData,
  });

  final int sequence;
  final String streamId;
  final String eventKind;
  final JsonObject eventData;
}

final class DtdStreams {
  DtdStreams({
    required this.connection,
    this.maxEvents = 1024,
  }) {
    if (maxEvents <= 0) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive.');
    }
  }

  final DtdConnection connection;
  final int maxEvents;
  final Map<String, DtdStreamSubscriptionState> _subscriptions =
      <String, DtdStreamSubscriptionState>{};
  final Map<String, ({String streamId, bool listen})> _operations =
      <String, ({String streamId, bool listen})>{};
  final List<DtdStreamEvent> _events = <DtdStreamEvent>[];
  int _nextSequence = 1;

  List<DtdStreamEvent> get events => List<DtdStreamEvent>.unmodifiable(_events);

  bool isListening(String streamId) =>
      _subscriptions[streamId] == DtdStreamSubscriptionState.active ||
      _subscriptions[streamId] == DtdStreamSubscriptionState.cancelPending;

  DtdPendingRequest listen(String streamId) {
    if (_subscriptions.containsKey(streamId)) {
      throw const ToolingProtocolStateError(
        'dtd_stream_subscription_duplicate',
        'DTD stream already has a subscription or pending operation.',
      );
    }
    final request = connection.beginRequest(
      'streamListen',
      params: <String, Object?>{'streamId': streamId},
    );
    _subscriptions[streamId] = DtdStreamSubscriptionState.listenPending;
    _operations[request.id] = (streamId: streamId, listen: true);
    return request;
  }

  DtdPendingRequest cancel(String streamId) {
    if (_subscriptions[streamId] != DtdStreamSubscriptionState.active) {
      throw const ToolingProtocolStateError(
        'dtd_stream_not_subscribed',
        'DTD stream cancellation requires an active subscription.',
      );
    }
    final request = connection.beginRequest(
      'streamCancel',
      params: <String, Object?>{'streamId': streamId},
    );
    _subscriptions[streamId] = DtdStreamSubscriptionState.cancelPending;
    _operations[request.id] = (streamId: streamId, listen: false);
    return request;
  }

  DtdPendingRequest post({
    required String streamId,
    required String eventKind,
    required Map<String, Object?> eventData,
  }) =>
      connection.beginRequest(
        'postEvent',
        params: <String, Object?>{
          'streamId': streamId,
          'eventKind': eventKind,
          'eventData': eventData,
        },
      );

  DtdStreamEvent acceptNotification(Map<String, Object?> params) {
    final validated =
        DtdModelRegistry.instance.validateParams('streamNotify', params);
    final streamId = validated['streamId']! as String;
    if (!isListening(streamId)) {
      throw const ToolingProtocolStateError(
        'dtd_stream_notification_unsubscribed',
        'DTD stream notification requires an active subscription.',
      );
    }
    if (_events.length >= maxEvents) {
      throw const ToolingResourceLimitError(
        'dtd_stream_event_queue_full',
        'DTD stream event queue reached its configured limit.',
      );
    }
    final event = DtdStreamEvent(
      sequence: _nextSequence++,
      streamId: streamId,
      eventKind: validated['eventKind']! as String,
      eventData: validated['eventData']! as JsonObject,
    );
    _events.add(event);
    return event;
  }

  void complete(String requestId, {Object? failure}) {
    final operation = _operations.remove(requestId);
    if (operation == null) {
      return;
    }
    if (operation.listen) {
      if (failure == null) {
        _subscriptions[operation.streamId] = DtdStreamSubscriptionState.active;
      } else {
        _subscriptions.remove(operation.streamId);
      }
    } else if (failure == null) {
      _subscriptions.remove(operation.streamId);
    } else {
      _subscriptions[operation.streamId] = DtdStreamSubscriptionState.active;
    }
  }

  void disconnect() {
    _subscriptions.clear();
    _operations.clear();
  }
}
