import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('prepareOpenAiCompatibleTools', () {
    test('null tools 归一化为 tools:null,toolChoice:null', () {
      final result = prepareOpenAiCompatibleTools(
        tools: null,
        toolChoice: null,
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isEmpty);
    });

    test('空数组 tools 归一化为 tools:null', () {
      final result = prepareOpenAiCompatibleTools(
        tools: const [],
        toolChoice: null,
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
    });

    test('function 工具映射,description 缺省时不出现该键', () {
      final result = prepareOpenAiCompatibleTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: null,
      );

      final function =
          result.tools!.single['function']! as Map<String, Object?>;
      expect(function['name'], 'get_weather');
      expect(function.containsKey('description'), isFalse);
    });

    test('function 工具 description 非空时携带该键', () {
      final result = prepareOpenAiCompatibleTools(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            description: 'fetch weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: null,
      );

      final function =
          result.tools!.single['function']! as Map<String, Object?>;
      expect(function['description'], 'fetch weather');
    });

    test('function 工具 strict 非 null 时带上该键,null 时不携带', () {
      final withStrict = prepareOpenAiCompatibleTools(
        tools: [
          const FunctionTool(
            name: 'f',
            inputSchema: JsonSchema({'type': 'object'}),
            strict: true,
          ),
        ],
        toolChoice: null,
      );
      final withoutStrict = prepareOpenAiCompatibleTools(
        tools: [
          const FunctionTool(
            name: 'f',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        toolChoice: null,
      );

      expect(
        (withStrict.tools!.single['function']!
            as Map<String, Object?>)['strict'],
        true,
      );
      expect(
        (withoutStrict.tools!.single['function']! as Map<String, Object?>)
            .containsKey('strict'),
        isFalse,
      );
    });

    test(
        'provider 内置工具推 warning 并被跳过,文案对齐 raw'
        '(与 openai 包措辞不同)', () {
      final result = prepareOpenAiCompatibleTools(
        tools: [
          const FunctionTool(
            name: 'f',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
          const ProviderTool(
            id: 'openai.web_search',
            name: 'web_search',
            args: {},
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, hasLength(1));
      expect(result.warnings, hasLength(1));
      final warning = result.warnings.single as UnsupportedWarning;
      expect(warning.feature, 'provider-defined tool openai.web_search');
    });

    test(
        '全部工具均为 ProviderTool 时 tools 为空数组'
        '(非 null,与 openai 包不同)', () {
      final result = prepareOpenAiCompatibleTools(
        tools: [
          const ProviderTool(
            id: 'openai.web_search',
            name: 'web_search',
            args: {},
          ),
        ],
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.tools, isNotNull);
      expect(result.tools, isEmpty);
      expect(result.toolChoice, 'auto');
      expect(result.warnings, hasLength(1));
    });

    test('toolChoice auto/none/required 直接透传字符串', () {
      for (final entry in {
        const ToolChoiceAuto(): 'auto',
        const ToolChoiceNone(): 'none',
        const ToolChoiceRequired(): 'required',
      }.entries) {
        final result = prepareOpenAiCompatibleTools(
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
      final result = prepareOpenAiCompatibleTools(
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

    test('tools 为 null 时提前返回,toolChoice 恒为 null(不进入映射分支)', () {
      final result = prepareOpenAiCompatibleTools(
        tools: null,
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
    });
  });
}
