import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';

void main() {
  if (mcpHttpTransportSpecificationVersion != '2025-11-25') {
    throw StateError('Unexpected MCP HTTP transport version.');
  }
}
