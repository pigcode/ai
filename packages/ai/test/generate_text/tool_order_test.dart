import 'package:pigcode_ai/src/generate_text/tool_order.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('orderTools', () {
    final tools = <String, Tool>{
      'zebra': const Tool(
        inputSchema: provider.JsonSchema({'type': 'object'}),
      ),
      'alpha': const Tool(
        inputSchema: provider.JsonSchema({'type': 'object'}),
      ),
      'middle': const Tool(
        inputSchema: provider.JsonSchema({'type': 'object'}),
      ),
    };

    test('keeps insertion order when no toolOrder is provided', () {
      expect(orderTools(tools, null, null).keys, ['zebra', 'alpha', 'middle']);
    });

    test('orders listed tools first and appends omitted tools by name', () {
      expect(orderTools(tools, const ['middle'], null).keys,
          ['middle', 'alpha', 'zebra']);
    });

    test('does not duplicate tools when toolOrder repeats a name', () {
      expect(orderTools(tools, const ['middle', 'middle'], null).keys,
          ['middle', 'alpha', 'zebra']);
    });

    test('ignores globally known tools that are not active in this step', () {
      final activeTools = <String, Tool>{
        'alpha': tools['alpha']!,
        'middle': tools['middle']!,
      };

      expect(
        orderTools(activeTools, const ['zebra', 'middle'], tools).keys,
        ['middle', 'alpha'],
      );
    });

    test('rejects unknown tool names', () {
      expect(
        () => orderTools(tools, const ['missing'], null),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
