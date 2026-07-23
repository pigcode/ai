import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';

extension McpClientCompletion on McpClient {
  Future<McpCompleteResult> complete(
    McpCompleteRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCompleteResult.fromJson(
        await requestServer(
          'completion/complete',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );
}
