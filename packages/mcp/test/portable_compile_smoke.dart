import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';

void main() {
  if (mcpProtocolVersion != '2025-11-25' || mcpSchemaSha256.length != 64) {
    throw StateError('Unexpected MCP source identity.');
  }
}
