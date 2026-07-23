import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'connection.dart';
import 'handlers.dart';

final class McpClient {
  McpClient({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required McpClientCapabilities capabilities,
    required McpHandlerSet handlers,
    required JsonObject clientInfo,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  })  : _capabilities = capabilities,
        _handlers = handlers,
        _clientInfo = freezeJsonObject(clientInfo),
        _limits = limits,
        connection = McpConnection.client(
          transport: transport,
          capabilities: capabilities,
          handlers: handlers,
          clientInfo: clientInfo,
          limits: limits,
          diagnostics: diagnostics,
        );

  final McpConnection connection;
  final McpClientCapabilities _capabilities;
  final McpHandlerSet _handlers;
  final JsonObject _clientInfo;
  final ProtocolLimits? _limits;

  McpConnectionState get state => connection.state;
  McpNegotiatedCapabilities? get negotiatedCapabilities =>
      connection.negotiatedCapabilities;

  Future<McpNegotiatedCapabilities> initialize() =>
      connection.initializeClient();

  Future<JsonValue> requestServer(
    String method,
    JsonValue params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) =>
      connection.requestRemote(
        method,
        params,
        cancellation: cancellation,
        timeout: timeout,
      );

  Future<void> notifyServer(String method, JsonValue params) =>
      connection.notifyRemote(method, params);

  Future<McpClient> reconnect({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    ProtocolDiagnosticSink? diagnostics,
  }) async {
    await close();
    return McpClient(
      transport: transport,
      capabilities: _capabilities,
      handlers: _handlers,
      clientInfo: _clientInfo,
      limits: _limits,
      diagnostics: diagnostics,
    );
  }

  Future<void> close() => connection.close();
}
