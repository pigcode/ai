import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'cancellation_adapter.dart';
import 'capabilities.dart';
import 'errors.dart';
import 'handlers.dart';
import 'models.dart';
import 'schema.dart';
import 'version.dart';

enum McpConnectionState {
  disconnected,
  initializing,
  awaitingInitialized,
  initialized,
  closing,
  closed,
}

/// One outbound MCP request whose JSON-RPC identifier is available immediately.
final class McpPendingRequest {
  const McpPendingRequest({
    required this.id,
    required this.response,
  });

  final JsonRpcId id;
  final Future<JsonValue> response;
}

final class McpConnection {
  McpConnection.server({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required McpServerCapabilities capabilities,
    required McpHandlerSet handlers,
    required JsonObject serverInfo,
    String? instructions,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  })  : participant = McpParticipant.server,
        _clientCapabilities = null,
        _serverCapabilities = capabilities,
        _implementationInfo = _validateImplementation(serverInfo),
        _instructions = instructions,
        _handlers = handlers {
    _validateLocalHandlers();
    _createPeer(transport, limits: limits, diagnostics: diagnostics);
  }

  McpConnection.client({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required McpClientCapabilities capabilities,
    required McpHandlerSet handlers,
    required JsonObject clientInfo,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  })  : participant = McpParticipant.client,
        _clientCapabilities = capabilities,
        _serverCapabilities = null,
        _implementationInfo = _validateImplementation(clientInfo),
        _instructions = null,
        _handlers = handlers {
    _validateLocalHandlers();
    _createPeer(transport, limits: limits, diagnostics: diagnostics);
  }

  final McpParticipant participant;
  final McpClientCapabilities? _clientCapabilities;
  final McpServerCapabilities? _serverCapabilities;
  final JsonObject _implementationInfo;
  final String? _instructions;
  final McpHandlerSet _handlers;
  late final JsonRpcPeer _peer;
  McpConnectionState _state = McpConnectionState.disconnected;
  McpNegotiatedCapabilities? _negotiatedCapabilities;

  McpConnectionState get state => _state;
  McpNegotiatedCapabilities? get negotiatedCapabilities =>
      _negotiatedCapabilities;
  JsonRpcPeer get peer => _peer;

  Future<McpNegotiatedCapabilities> initializeClient() async {
    if (participant != McpParticipant.client) {
      throw const McpStateException(
        'mcp_initialize_wrong_side',
        'Only the MCP client initiates initialize.',
      );
    }
    if (_state != McpConnectionState.disconnected) {
      throw const McpStateException(
        'mcp_duplicate_initialize',
        'MCP initialize may be sent exactly once per connection.',
      );
    }
    _state = McpConnectionState.initializing;
    try {
      final result = await _requestUnchecked(
        'initialize',
        <String, Object?>{
          'protocolVersion': mcpProtocolVersion,
          'capabilities': _clientCapabilities!.toJson(),
          'clientInfo': _implementationInfo,
        },
      );
      final object = result! as JsonObject;
      final version = object['protocolVersion'];
      if (version != mcpProtocolVersion) {
        throw McpVersionException(
          receivedVersion: version is String ? version : null,
        );
      }
      final serverCapabilities = McpServerCapabilities.fromJson(
        object['capabilities'] ?? const <String, Object?>{},
      );
      _negotiatedCapabilities = McpNegotiatedCapabilities(
        protocolVersion: mcpProtocolVersion,
        client: _clientCapabilities,
        server: serverCapabilities,
      );
      _state = McpConnectionState.awaitingInitialized;
      await _notifyUnchecked(
        'notifications/initialized',
        const <String, Object?>{},
      );
      _state = McpConnectionState.initialized;
      return _negotiatedCapabilities!;
    } on Object {
      _state = McpConnectionState.closing;
      await _peer.close();
      _state = McpConnectionState.closed;
      rethrow;
    }
  }

  Future<JsonValue> requestRemote(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    cancellation?.throwIfCancelled();
    final pending = startRequestRemote(
      method,
      params,
      timeout: timeout,
    );
    return McpRequestCancellationAdapter.waitForResponse(
      pending: JsonRpcPendingRequest(
        id: pending.id,
        response: pending.response,
      ),
      sendCancellation: _sendCancellation,
      diagnostics: _peer.diagnostics,
      cancellation: cancellation,
    );
  }

  McpPendingRequest startRequestRemote(
    String method,
    JsonValue params, {
    Duration? timeout,
  }) {
    _requireInitialized();
    final binding = _outboundBinding(method, notification: false);
    _requireCapability(binding);
    final validatedParams = _validateOutboundParams(binding, params);
    final taskAugmented = _isTaskAugmented(validatedParams);
    if (taskAugmented) {
      _requireTaskAugmentation(binding);
    }
    final pending = _peer.startRequest(
      method,
      params: validatedParams,
      timeout: timeout,
    );
    return McpPendingRequest(
      id: pending.id,
      response: pending.response.then(
        (result) => _validateResult(
          binding,
          result,
          responder: _remoteParticipant,
          taskAugmented: taskAugmented,
        ),
      ),
    );
  }

  Future<void> notifyRemote(String method, JsonValue params) async {
    _requireInitialized();
    final binding = _outboundBinding(method, notification: true);
    _requireCapability(binding);
    await _notifyUnchecked(method, params);
  }

  Future<void> close() async {
    if (_state == McpConnectionState.closed) {
      return;
    }
    _state = McpConnectionState.closing;
    await _peer.close();
    _state = McpConnectionState.closed;
  }

  void _createPeer(
    ProtocolMessageTransport<JsonRpcMessage> transport, {
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) {
    final requestHandlers = <String, JsonRpcRequestHandler>{
      'ping': _handlePing,
    };
    if (participant == McpParticipant.server) {
      requestHandlers['initialize'] = _handleInitialize;
    }
    for (final entry in _handlers.requests.entries) {
      if (_reservedRequests.contains(entry.key)) {
        continue;
      }
      requestHandlers[entry.key] = (request, cancellation) =>
          _dispatchRequest(entry.value, request, cancellation);
    }
    final notificationHandlers = <String, JsonRpcNotificationHandler>{};
    if (participant == McpParticipant.server) {
      notificationHandlers['notifications/initialized'] = _handleInitialized;
    }
    notificationHandlers['notifications/cancelled'] = _handleCancelled;
    for (final entry in _handlers.notifications.entries) {
      if (_reservedNotifications.contains(entry.key)) {
        continue;
      }
      notificationHandlers[entry.key] =
          (notification) => _dispatchNotification(entry.value, notification);
    }
    _peer = JsonRpcPeer(
      transport: transport,
      limits: limits,
      diagnostics: diagnostics,
      requestHandlers: requestHandlers,
      notificationHandlers: notificationHandlers,
    );
    unawaited(
      _peer.done.then((_) {
        if (_state != McpConnectionState.closing) {
          _state = McpConnectionState.closed;
        }
      }),
    );
  }

  Future<JsonValue> _handleInitialize(
    JsonRpcRequest request,
    ProtocolCancellationSignal cancellation,
  ) async {
    if (_state != McpConnectionState.disconnected) {
      throw const JsonRpcHandlerException(
        code: -32600,
        message: 'Duplicate initialize request',
      );
    }
    _state = McpConnectionState.initializing;
    final binding = _binding(
      'initialize',
      sender: McpParticipant.client,
      notification: false,
    );
    final envelope = _validateCall(binding, request.toJson());
    final params = envelope['params']! as JsonObject;
    final version = params['protocolVersion'];
    if (version != mcpProtocolVersion) {
      _state = McpConnectionState.closing;
      throw JsonRpcHandlerException(
        code: -32602,
        message: 'Unsupported MCP protocol version',
        hasData: true,
        data: <String, Object?>{
          'supportedProtocolVersion': mcpProtocolVersion,
          if (version is String) 'receivedProtocolVersion': version,
        },
      );
    }
    final clientCapabilities = McpClientCapabilities.fromJson(
      params['capabilities'] ?? const <String, Object?>{},
    );
    _negotiatedCapabilities = McpNegotiatedCapabilities(
      protocolVersion: mcpProtocolVersion,
      client: clientCapabilities,
      server: _serverCapabilities!,
    );
    _state = McpConnectionState.awaitingInitialized;
    return _validateResult(
      binding,
      <String, Object?>{
        'protocolVersion': mcpProtocolVersion,
        'capabilities': _serverCapabilities.toJson(),
        'serverInfo': _implementationInfo,
        if (_instructions != null) 'instructions': _instructions,
      },
      responder: McpParticipant.server,
    );
  }

  JsonValue _handlePing(
    JsonRpcRequest request,
    ProtocolCancellationSignal cancellation,
  ) {
    if (_state != McpConnectionState.initialized) {
      throw const JsonRpcHandlerException(
        code: -32001,
        message: 'MCP connection is not initialized',
      );
    }
    final binding = _binding(
      'ping',
      sender: _remoteParticipant,
      notification: false,
    );
    _validateCall(binding, request.toJson());
    return _validateResult(
      binding,
      const <String, Object?>{},
      responder: participant,
    );
  }

  void _handleInitialized(JsonRpcNotification notification) {
    if (_state != McpConnectionState.awaitingInitialized) {
      throw const McpStateException(
        'mcp_initialized_out_of_order',
        'MCP initialized notification arrived before initialize response.',
      );
    }
    final binding = _binding(
      'notifications/initialized',
      sender: McpParticipant.client,
      notification: true,
    );
    _validateCall(binding, notification.toJson());
    _state = McpConnectionState.initialized;
  }

  Future<JsonValue> _dispatchRequest(
    McpRequestHandler handler,
    JsonRpcRequest request,
    ProtocolCancellationSignal cancellation,
  ) async {
    if (_state != McpConnectionState.initialized) {
      throw const JsonRpcHandlerException(
        code: -32001,
        message: 'MCP connection is not initialized',
      );
    }
    final remote = _remoteParticipant;
    final binding = _binding(
      request.method,
      sender: remote,
      notification: false,
    );
    try {
      _requireCapability(binding);
      final envelope = _validateCall(binding, request.toJson());
      final taskAugmented = _isTaskAugmented(envelope['params']);
      if (taskAugmented) {
        _requireTaskAugmentation(binding);
      }
      final result = await Future<JsonValue>.sync(
        () => handler(
          McpRequestInvocation(
            binding: binding,
            params: envelope['params'],
            cancellation: cancellation,
          ),
        ),
      );
      return _validateResult(
        binding,
        result,
        responder: participant,
        taskAugmented: taskAugmented,
      );
    } on McpCapabilityException {
      throw const JsonRpcHandlerException(
        code: -32601,
        message: 'Method not negotiated',
      );
    } on McpSchemaException {
      throw const JsonRpcHandlerException(
        code: -32602,
        message: 'Invalid MCP method parameters',
      );
    }
  }

  void _handleCancelled(JsonRpcNotification notification) {
    if (_state != McpConnectionState.initialized) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_cancel_before_initialized',
          message: 'Ignored MCP cancellation before initialization.',
          method: 'notifications/cancelled',
        ),
      );
      return;
    }
    final binding = _binding(
      'notifications/cancelled',
      sender: _remoteParticipant,
      notification: true,
    );
    final envelope = _validateCall(binding, notification.toJson());
    final params = envelope['params'];
    if (params is! Map<String, Object?> || !params.containsKey('requestId')) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_cancel_missing_request_id',
          message: 'Ignored MCP cancellation without a request identifier.',
          method: 'notifications/cancelled',
        ),
      );
      return;
    }
    final id = JsonRpcId.fromJson(params['requestId']);
    if (id is JsonRpcNullId ||
        !_peer.cancelInboundRequest(id, params['reason'])) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_cancel_unknown_or_duplicate_request',
          message:
              'Ignored MCP cancellation for an unknown or completed request.',
          requestId: id,
          method: 'notifications/cancelled',
        ),
      );
    }
  }

  Future<void> _dispatchNotification(
    McpNotificationHandler handler,
    JsonRpcNotification notification,
  ) async {
    if (_state != McpConnectionState.initialized) {
      throw const McpStateException(
        'mcp_not_initialized',
        'MCP operation requires the initialized notification barrier.',
      );
    }
    final binding = _binding(
      notification.method,
      sender: _remoteParticipant,
      notification: true,
    );
    _requireCapability(binding);
    final envelope = _validateCall(binding, notification.toJson());
    await Future<void>.sync(
      () => handler(
        McpNotificationInvocation(
          binding: binding,
          params: envelope['params'],
        ),
      ),
    );
  }

  Future<JsonValue> _requestUnchecked(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async {
    final binding = _outboundBinding(method, notification: false);
    final validatedParams = _validateOutboundParams(binding, params);
    final result = await _peer.request(
      method,
      params: validatedParams,
      cancellation: cancellation,
      timeout: timeout,
    );
    return _validateResult(
      binding,
      result,
      responder: _remoteParticipant,
    );
  }

  Future<void> _notifyUnchecked(String method, JsonValue params) async {
    final binding = _outboundBinding(method, notification: true);
    final validatedParams = _validateOutboundParams(binding, params);
    await _peer.notify(method, params: validatedParams);
  }

  JsonValue _validateOutboundParams(
    McpMethodBinding binding,
    JsonValue params,
  ) {
    final envelope = <String, Object?>{
      'jsonrpc': '2.0',
      if (binding.isRequest) 'id': 1,
      'method': binding.method,
      if (params != null) 'params': params,
    };
    final validated = _validateCall(binding, envelope);
    return validated['params'];
  }

  JsonObject _validateCall(
    McpMethodBinding binding,
    JsonObject envelope,
  ) =>
      McpSchema.instance.validateDefinition(
        binding.definition,
        envelope,
      )! as JsonObject;

  JsonValue _validateResult(
    McpMethodBinding binding,
    JsonValue result, {
    required McpParticipant responder,
    bool taskAugmented = false,
  }) {
    if (taskAugmented) {
      return McpSchema.instance.validateDefinition('CreateTaskResult', result);
    }
    final role =
        responder == McpParticipant.server ? 'ServerResult' : 'ClientResult';
    final frozen = McpSchema.instance.validateRole(role, result);
    return McpSchema.instance.validateDefinition(
      binding.resultDefinition!,
      frozen,
    );
  }

  McpMethodBinding _outboundBinding(
    String method, {
    required bool notification,
  }) =>
      _binding(method, sender: participant, notification: notification);

  McpMethodBinding _binding(
    String method, {
    required McpParticipant sender,
    required bool notification,
  }) {
    final candidates = mcpMethodBindingsByName[method];
    if (candidates == null) {
      throw McpCodecException(
        'mcp_unknown_stable_method',
        'Method is not part of MCP 2025-11-25.',
        method: method,
      );
    }
    for (final candidate in candidates) {
      if (candidate.sender == sender &&
          candidate.isNotification == notification) {
        return candidate;
      }
    }
    throw McpCodecException(
      'mcp_wrong_role',
      'MCP method is not valid for this participant.',
      method: method,
    );
  }

  void _requireCapability(McpMethodBinding binding) {
    if (!(_negotiatedCapabilities?.supports(binding) ?? false)) {
      throw McpCapabilityException(
        'mcp_capability_not_negotiated',
        'MCP optional method was not negotiated.',
        method: binding.method,
      );
    }
  }

  void _requireTaskAugmentation(McpMethodBinding binding) {
    final capabilities = _negotiatedCapabilities;
    final supported = switch (binding.method) {
      'tools/call' => capabilities?.server.taskToolCall ?? false,
      'sampling/createMessage' => capabilities?.client.taskSampling ?? false,
      'elicitation/create' => capabilities?.client.taskElicitation ?? false,
      _ => false,
    };
    if (!supported) {
      throw McpCapabilityException(
        'mcp_task_augmentation_not_negotiated',
        'Task augmentation was not negotiated for this MCP method.',
        method: binding.method,
      );
    }
  }

  void _requireInitialized() {
    if (_state != McpConnectionState.initialized) {
      throw const McpStateException(
        'mcp_not_initialized',
        'MCP operation requires initialize and initialized notification.',
      );
    }
  }

  void _validateLocalHandlers() {
    _handlers.validateFor(participant);
    final reserved = <String>{
      ..._handlers.requests.keys.where(_reservedRequests.contains),
      ..._handlers.notifications.keys.where(_reservedNotifications.contains),
    }.toList()
      ..sort();
    if (reserved.isNotEmpty) {
      throw McpHandlerException(
        'mcp_reserved_handler',
        'MCP lifecycle handlers are owned by McpConnection.',
        methods: reserved,
      );
    }
    if (participant == McpParticipant.server) {
      _handlers.requireHandlers(_serverCapabilities!.requiredHandlerMethods);
    } else {
      _handlers.requireHandlers(_clientCapabilities!.requiredHandlerMethods);
    }
  }

  Future<void> _sendCancellation(JsonRpcId id, String? reason) =>
      _notifyUnchecked(
        'notifications/cancelled',
        <String, Object?>{
          'requestId': id.toJson(),
          if (reason != null) 'reason': reason,
        },
      );

  void _diagnose(ProtocolDiagnostic diagnostic) {
    try {
      _peer.diagnostics.add(diagnostic);
    } on Object {
      // Caller diagnostics must not change connection state.
    }
  }

  McpParticipant get _remoteParticipant => participant == McpParticipant.client
      ? McpParticipant.server
      : McpParticipant.client;
}

JsonObject _validateImplementation(JsonObject value) =>
    McpSchema.instance.validateDefinition('Implementation', value)!
        as JsonObject;

const _reservedRequests = <String>{'initialize', 'ping'};
const _reservedNotifications = <String>{
  'notifications/initialized',
  'notifications/cancelled',
};

bool _isTaskAugmented(JsonValue params) =>
    params is Map<String, Object?> && params['task'] is Map<String, Object?>;
