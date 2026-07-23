import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:test/test.dart';

void main() {
  test('HTTP barrel remains pinned to the MCP specification', () {
    expect(mcpHttpTransportSpecificationVersion, '2025-11-25');
  });
}
