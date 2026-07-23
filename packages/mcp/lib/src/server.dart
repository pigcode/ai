import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'capabilities.dart';
import 'connection.dart';
import 'handlers.dart';

final class McpServer {
  McpServer({
    required ProtocolMessageTransport<JsonRpcMessage> transport,
    required McpServerCapabilities capabilities,
    required McpHandlerSet handlers,
    required JsonObject serverInfo,
    String? instructions,
    ProtocolLimits? limits,
    ProtocolDiagnosticSink? diagnostics,
  }) : connection = McpConnection.server(
          transport: transport,
          capabilities: capabilities,
          handlers: handlers,
          serverInfo: serverInfo,
          instructions: instructions,
          limits: limits,
          diagnostics: diagnostics,
        );

  final McpConnection connection;

  McpConnectionState get state => connection.state;
  McpNegotiatedCapabilities? get negotiatedCapabilities =>
      connection.negotiatedCapabilities;

  Future<JsonValue> requestClient(
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

  Future<void> notifyClient(String method, JsonValue params) =>
      connection.notifyRemote(method, params);

  Future<void> close() => connection.close();
}
