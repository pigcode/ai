import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpClientPrompts on McpClient {
  Future<McpListPromptsResult> listPrompts(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListPromptsResult.fromJson(
        await requestServer(
          'prompts/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpGetPromptResult> getPrompt(
    McpGetPromptRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpGetPromptResult.fromJson(
        await requestServer(
          'prompts/get',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
}

extension McpServerPromptNotifications on McpServer {
  Future<void> notifyPromptListChanged() =>
      notifyClient('notifications/prompts/list_changed', const {});
}
