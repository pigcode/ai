import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';

/// Creates an adapter for a caller-configured endpoint.
///
/// The application remains responsible for binding, accepting, and closing
/// its [HttpServer].
McpIoHttpServerAdapter adaptCallerOwnedServer(McpHttpEndpoint endpoint) =>
    McpIoHttpServerAdapter(endpoint);

Future<void> forwardCallerOwnedRequest(
  McpIoHttpServerAdapter adapter,
  HttpRequest request,
) =>
    adapter.handle(request);

void main() {}
