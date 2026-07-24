import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'errors.dart';
import 'events.dart';
import 'method.dart';
import 'session.dart';

enum DapConnectionLifecycle {
  created,
  initializePending,
  initialized,
  startPending,
  configuring,
  active,
  terminated,
  disconnectPending,
  disconnected,
  closed,
}

final class DapPendingRequest {
  DapPendingRequest._({
    required this.seq,
    required this.command,
    required this.arguments,
    required this.connectionId,
  });

  final int seq;
  final String command;
  final JsonValue arguments;
  final int connectionId;
  bool _done = false;
  Object? _failure;

  bool get done => _done;
  Object? get failure => _failure;

  void _complete([Object? failure]) {
    if (_done) {
      throw const DapCorrelationException(
        'dap_request_completed_twice',
        'DAP request completed more than once.',
      );
    }
    _done = true;
    _failure = failure;
  }
}

final class DapConnection {
  DapConnection({int maxEvents = 1024})
      : connectionId = _nextConnectionId++,
        events = DapEventQueue(maxEvents: maxEvents);

  static int _nextConnectionId = 1;

  final int connectionId;
  final DapEventQueue events;
  final DapSessionTerminal terminal = DapSessionTerminal();
  DapConnectionLifecycle _lifecycle = DapConnectionLifecycle.created;
  int _nextSequence = 1;
  final Map<int, DapPendingRequest> _pending = <int, DapPendingRequest>{};
  final Map<int, String> _tombstones = <int, String>{};
  DapCapabilitySnapshot? _capabilities;
  String? _startCommand;
  bool _startCompleted = false;
  bool _initializedEventReceived = false;

  DapConnectionLifecycle get lifecycle => _lifecycle;
  int get nextSequence => _nextSequence;

  DapCapabilitySnapshot get capabilities {
    final snapshot = _capabilities;
    if (snapshot == null) {
      throw const DapStateException(
        'dap_capabilities_unavailable',
        'DAP capabilities are unavailable before initialize completes.',
      );
    }
    return snapshot;
  }

  DapPendingRequest beginInitialize() {
    if (_lifecycle != DapConnectionLifecycle.created) {
      throw const DapStateException(
        'dap_initialize_already_started',
        'DAP initialize is allowed exactly once.',
      );
    }
    _lifecycle = DapConnectionLifecycle.initializePending;
    return _allocate(
      'initialize',
      const <String, Object?>{
        'adapterID': 'pigcode',
        'linesStartAt1': true,
        'columnsStartAt1': true,
      },
    );
  }

  void completeInitialize(
    int requestSeq,
    Map<String, Object?> capabilityValues,
  ) {
    if (_lifecycle != DapConnectionLifecycle.initializePending) {
      throw const DapStateException(
        'dap_initialize_response_unexpected',
        'DAP initialize response is not expected in the current state.',
      );
    }
    _completeExpected(requestSeq, 'initialize');
    _capabilities = DapCapabilitySnapshot.fromInitialize(
      connectionId: connectionId,
      capabilities: capabilityValues,
    );
    _lifecycle = DapConnectionLifecycle.initialized;
  }

  DapPendingRequest beginLaunch(JsonValue arguments) =>
      _beginStart('launch', arguments);

  DapPendingRequest beginAttach(JsonValue arguments) =>
      _beginStart('attach', arguments);

  DapPendingRequest _beginStart(String command, JsonValue arguments) {
    if (_lifecycle != DapConnectionLifecycle.initialized ||
        _startCommand != null) {
      throw const DapStateException(
        'dap_start_out_of_order',
        'DAP launch or attach is allowed exactly once after initialize.',
      );
    }
    _startCommand = command;
    _lifecycle = DapConnectionLifecycle.startPending;
    return _allocate(command, arguments);
  }

  void completeStart(int requestSeq) {
    final command = _startCommand;
    if (_lifecycle != DapConnectionLifecycle.startPending || command == null) {
      throw const DapStateException(
        'dap_start_response_unexpected',
        'DAP launch or attach response is not expected.',
      );
    }
    _completeExpected(requestSeq, command);
    _startCompleted = true;
    if (_initializedEventReceived) {
      _lifecycle = DapConnectionLifecycle.configuring;
    }
  }

  DapPendingRequest beginConfigurationDone() {
    if (_lifecycle != DapConnectionLifecycle.configuring) {
      throw const DapStateException(
        'dap_configuration_out_of_order',
        'DAP configurationDone requires the initialized event.',
      );
    }
    return _allocateChecked('configurationDone', const <String, Object?>{});
  }

  void completeConfiguration(int requestSeq) {
    if (_lifecycle != DapConnectionLifecycle.configuring) {
      throw const DapStateException(
        'dap_configuration_response_unexpected',
        'DAP configurationDone response is not expected.',
      );
    }
    _completeExpected(requestSeq, 'configurationDone');
    _lifecycle = DapConnectionLifecycle.active;
  }

  DapPendingRequest beginRequest(
    String command, {
    JsonValue arguments = const <String, Object?>{},
  }) {
    if (_lifecycle != DapConnectionLifecycle.active) {
      throw const DapStateException(
        'dap_request_out_of_state',
        'Ordinary DAP requests require an active debug session.',
      );
    }
    return _allocateChecked(command, arguments);
  }

  void completeResponse({
    required int requestSeq,
    required String command,
    Object? failure,
  }) {
    _completeExpected(requestSeq, command, failure: failure);
  }

  DapPendingRequest beginDisconnect() {
    if (_lifecycle != DapConnectionLifecycle.active &&
        _lifecycle != DapConnectionLifecycle.terminated) {
      throw const DapStateException(
        'dap_disconnect_out_of_order',
        'DAP disconnect requires an active or terminated session.',
      );
    }
    _lifecycle = DapConnectionLifecycle.disconnectPending;
    return _allocate('disconnect', const <String, Object?>{});
  }

  void completeDisconnect(int requestSeq) {
    if (_lifecycle != DapConnectionLifecycle.disconnectPending) {
      throw const DapStateException(
        'dap_disconnect_response_unexpected',
        'DAP disconnect response is not expected.',
      );
    }
    _completeExpected(requestSeq, 'disconnect');
    terminal.recordDisconnected();
    _lifecycle = DapConnectionLifecycle.disconnected;
  }

  void receiveEvent({
    required int seq,
    required String event,
    required Map<String, Object?> body,
  }) {
    events.add(seq: seq, event: event, body: body);
    switch (event) {
      case 'initialized':
        if (_startCommand == null) {
          throw const DapStateException(
            'dap_initialized_event_out_of_order',
            'DAP initialized event requires launch or attach.',
          );
        }
        _initializedEventReceived = true;
        if (_startCompleted) {
          _lifecycle = DapConnectionLifecycle.configuring;
        }
      case 'capabilities':
        final changes = body['capabilities'];
        if (changes is! Map<String, Object?>) {
          throw const DapStateException(
            'dap_capabilities_event_invalid',
            'DAP capabilities event requires a capabilities object.',
          );
        }
        _capabilities = capabilities.update(changes);
      case 'terminated':
        terminal.recordTerminated();
        if (_lifecycle != DapConnectionLifecycle.disconnectPending &&
            _lifecycle != DapConnectionLifecycle.disconnected) {
          _lifecycle = DapConnectionLifecycle.terminated;
        }
      case 'exited':
        terminal.recordExited(exitCode: body['exitCode'] as int? ?? 0);
      default:
        break;
    }
  }

  void close() {
    if (_lifecycle == DapConnectionLifecycle.closed) {
      return;
    }
    const failure = DapStateException(
      'dap_connection_closed',
      'DAP connection closed before the request completed.',
    );
    for (final pending in _pending.values) {
      pending._complete(failure);
      _tombstones[pending.seq] = pending.command;
    }
    _pending.clear();
    terminal.recordDisconnected();
    _capabilities = null;
    _lifecycle = DapConnectionLifecycle.closed;
  }

  DapPendingRequest _allocateChecked(String command, JsonValue arguments) {
    if (_reverseCommands.contains(command) ||
        !dapRequestsByCommand.containsKey(command)) {
      throw DapStateException(
        'dap_outbound_command_invalid',
        'Command is not a client-originated DAP request: $command.',
      );
    }
    if (!capabilities.supportsCommand(command)) {
      throw DapCapabilityException(
        'dap_capability_unavailable',
        'Adapter did not advertise this optional DAP request.',
        command: command,
      );
    }
    return _allocate(command, arguments);
  }

  DapPendingRequest _allocate(String command, JsonValue arguments) {
    final pending = DapPendingRequest._(
      seq: _nextSequence++,
      command: command,
      arguments: freezeJsonValue(arguments),
      connectionId: connectionId,
    );
    _pending[pending.seq] = pending;
    return pending;
  }

  void _completeExpected(
    int requestSeq,
    String command, {
    Object? failure,
  }) {
    if (_tombstones.containsKey(requestSeq)) {
      throw const DapCorrelationException(
        'dap_response_tombstoned',
        'DAP response matches an already completed request.',
      );
    }
    final pending = _pending[requestSeq];
    if (pending == null) {
      throw const DapCorrelationException(
        'dap_response_unknown',
        'DAP response does not match a pending request.',
      );
    }
    if (pending.command != command) {
      throw const DapCorrelationException(
        'dap_response_command_mismatch',
        'DAP response command does not match its request_seq.',
      );
    }
    _pending.remove(requestSeq);
    pending._complete(failure);
    _tombstones[requestSeq] = command;
  }
}

const _reverseCommands = <String>{
  'runInTerminal',
  'startDebugging',
};
