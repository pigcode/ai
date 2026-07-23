import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpClientTools on McpClient {
  Future<McpListToolsResult> listTools(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListToolsResult.fromJson(
        await requestServer(
          'tools/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCallToolResult> callTool(
    McpCallToolRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCallToolResult.fromJson(
        await requestServer(
          'tools/call',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
}

extension McpServerToolNotifications on McpServer {
  Future<void> notifyToolListChanged() =>
      notifyClient('notifications/tools/list_changed', const {});
}
