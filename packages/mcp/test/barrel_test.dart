import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('portable barrel exposes the fixed MCP identity', () {
    expect(mcpProtocolVersion, '2025-11-25');
    expect(mcpSchemaSha256, hasLength(64));
    expect(mcpConformanceVersion, '0.1.16');
  });
}
