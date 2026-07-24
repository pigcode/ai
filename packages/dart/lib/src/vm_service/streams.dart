import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'connection.dart';
import 'models.dart';

enum VmServiceStreamState {
  listenPending,
  active,
  cancelPending,
}

final class VmServiceStreamEvent {
  const VmServiceStreamEvent({
    required this.sequence,
    required this.streamId,
    required this.kind,
    required this.value,
  });

  final int sequence;
  final String streamId;
  final VmServiceEventKind kind;
  final JsonObject value;
}

final class VmServiceStreams {
  VmServiceStreams({
    required this.connection,
    this.maxEvents = 1024,
  }) {
    if (maxEvents <= 0) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive.');
    }
  }

  final VmServiceConnection connection;
  final int maxEvents;
  final Map<String, VmServiceStreamState> _states =
      <String, VmServiceStreamState>{};
  final Map<String, ({String streamId, bool listen})> _operations =
      <String, ({String streamId, bool listen})>{};
  final List<VmServiceStreamEvent> _events = <VmServiceStreamEvent>[];
  int _nextSequence = 1;

  List<VmServiceStreamEvent> get events =>
      List<VmServiceStreamEvent>.unmodifiable(_events);

  bool isListening(String streamId) =>
      _states[streamId] == VmServiceStreamState.active ||
      _states[streamId] == VmServiceStreamState.cancelPending;

  VmServicePendingRequest listen(String streamId) {
    if (_states.containsKey(streamId)) {
      throw const ToolingProtocolStateError(
        'vm_service_stream_duplicate',
        'VM Service stream already has a subscription or pending operation.',
      );
    }
    final request = connection.beginRequest(
      'streamListen',
      params: <String, Object?>{'streamId': streamId},
    );
    _states[streamId] = VmServiceStreamState.listenPending;
    _operations[request.id] = (streamId: streamId, listen: true);
    return request;
  }

  VmServicePendingRequest cancel(String streamId) {
    if (_states[streamId] != VmServiceStreamState.active) {
      throw const ToolingProtocolStateError(
        'vm_service_stream_not_subscribed',
        'VM Service stream cancellation requires an active subscription.',
      );
    }
    final request = connection.beginRequest(
      'streamCancel',
      params: <String, Object?>{'streamId': streamId},
    );
    _states[streamId] = VmServiceStreamState.cancelPending;
    _operations[request.id] = (streamId: streamId, listen: false);
    return request;
  }

  VmServiceStreamEvent accept({
    required String streamId,
    required Map<String, Object?> event,
  }) {
    if (!isListening(streamId)) {
      throw const ToolingProtocolStateError(
        'vm_service_stream_event_late',
        'VM Service event belongs to an inactive stream.',
      );
    }
    if (_events.length >= maxEvents) {
      throw const ToolingResourceLimitError(
        'vm_service_stream_queue_full',
        'VM Service event queue reached its configured limit.',
      );
    }
    if (event['type'] != 'Event' ||
        event['kind'] is! String ||
        event['timestamp'] is! int) {
      throw const ToolingSchemaError(
        'vm_service_event_invalid',
        'VM Service stream event is malformed.',
      );
    }
    final record = VmServiceStreamEvent(
      sequence: _nextSequence++,
      streamId: streamId,
      kind: VmServiceModelRegistry.instance.validateEventKind(
        event['kind']! as String,
        version: connection.capabilities.wireVersion,
      ),
      value: freezeJsonObject(event),
    );
    _events.add(record);
    return record;
  }

  void complete(String requestId, {Object? failure}) {
    final operation = _operations.remove(requestId);
    if (operation == null) {
      return;
    }
    if (operation.listen) {
      if (failure == null) {
        _states[operation.streamId] = VmServiceStreamState.active;
      } else {
        _states.remove(operation.streamId);
      }
    } else if (failure == null) {
      _states.remove(operation.streamId);
    } else {
      _states[operation.streamId] = VmServiceStreamState.active;
    }
  }

  void disconnect() {
    _states.clear();
    _operations.clear();
  }
}
