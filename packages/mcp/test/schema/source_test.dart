import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('embeds only the exact MCP 2025-11-25 source', () {
    expect(mcpProtocolVersion, '2025-11-25');
    expect(
      mcpSchemaSha256,
      '1ffe4c5577974012f5fa02af14ea88df4b7146679df1abaaad497c8d9230ca8a',
    );
    expect(
      McpSchema.instance.document[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    expect(McpSchema.instance.definitionNames, hasLength(145));
    expect(
      McpSchema.instance.document.toString(),
      isNot(contains('2025-11-25-rc')),
    );
  });
}
