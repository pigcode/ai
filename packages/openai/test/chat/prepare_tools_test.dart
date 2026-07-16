import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('prepareOpenAiChatTools', () {
    test('null tools 归一化为 tools:null,toolChoice:null', () {
      final result = prepareOpenAiChatTools(tools: null, toolChoice: null);

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isEmpty);
    });

    test('空数组 tools 归一化为 tools:null', () {
      final result = prepareOpenAiChatTools(tools: const [], toolChoice: null);

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
    });

    test('function 工具映射,strict 缺省时不出现该键', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            description: 'fetch weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'description': 'fetch weather',
            'parameters': {'type': 'object'},
          },
        },
      ]);
    });

    test('function 工具无 description 时,嵌套 function 对象不含该键', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: null,
      );

      final function =
          (result.tools!.single['function']! as Map<String, Object?>);
      expect(function.containsKey('description'), isFalse);
    });

    test('function 工具 strict 非 null 时带上该键', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            strict: true,
          ),
        ],
        toolChoice: null,
      );

      final function =
          (result.tools!.single['function']! as Map<String, Object?>);
      expect(function['strict'], true);
    });

    test('provider 内置工具推 unsupported warning 并被跳过', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
          const ProviderTool(
              id: 'openai.web_search', name: 'web_search', args: {}),
        ],
        toolChoice: null,
      );

      expect(result.tools, hasLength(1));
      expect(
        (result.tools!.single['function']! as Map<String, Object?>)['name'],
        'get_weather',
      );
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
    });

    test('toolChoice auto/none/required 直接透传字符串', () {
      for (final entry in {
        const ToolChoiceAuto(): 'auto',
        const ToolChoiceNone(): 'none',
        const ToolChoiceRequired(): 'required',
      }.entries) {
        final result = prepareOpenAiChatTools(
          tools: [
            const FunctionTool(
              name: 'f',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
          ],
          toolChoice: entry.key,
        );
        expect(result.toolChoice, entry.value);
      }
    });

    test('toolChoice tool 转为 function 形状', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const FunctionTool(
            name: 'f',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: const ToolChoiceTool('f'),
      );

      expect(result.toolChoice, {
        'type': 'function',
        'function': {'name': 'f'},
      });
    });

    test('tools 为空但 toolChoice 非空时仍映射 toolChoice(tools 为 undefined)', () {
      final result = prepareOpenAiChatTools(
        tools: null,
        toolChoice: const ToolChoiceAuto(),
      );

      // 对齐上游:tools==null 时提前返回,toolChoice 恒为 undefined,
      // 不进入 toolChoice 映射分支。
      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
    });

    test('全部工具均为不支持的 ProviderTool 时,tools/toolChoice 都省略', () {
      final result = prepareOpenAiChatTools(
        tools: [
          const ProviderTool(
              id: 'openai.web_search', name: 'web_search', args: {}),
        ],
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
    });
  });
}
