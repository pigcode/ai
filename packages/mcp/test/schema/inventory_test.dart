import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('classifies all definitions and six explicit role unions', () {
    expect(McpSchema.instance.definitionNames, hasLength(145));
    expect(
      mcpRoleDefinitions,
      <String>{
        'ClientRequest',
        'ServerRequest',
        'ClientNotification',
        'ServerNotification',
        'ClientResult',
        'ServerResult',
      },
    );
    expect(mcpMethodBindings, hasLength(39));
    expect(
      mcpMethodBindings.map((binding) => binding.method).toSet(),
      hasLength(31),
    );
    expect(
      mcpDefinitionClassifications.keys.toSet(),
      McpSchema.instance.definitionNames,
    );
    expect(
      mcpDefinitionClassifications.values,
      everyElement(anyOf('typed', 'validated-extension')),
    );
  });
}
