import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('Tool', () {
    test('tool() 原样返回同一个 Tool 实例(身份函数)', () {
      const inputSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'city': <String, Object?>{'type': 'string'},
        },
        'required': <String>['city'],
      });
      const contextSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'tenant': <String, Object?>{'type': 'string'},
        },
      });
      const t = Tool(
        inputSchema: inputSchema,
        contextSchema: contextSchema,
        description: '查询城市天气',
        inputExamples: [
          {'city': '上海'},
        ],
      );

      final result = tool(t);

      expect(identical(result, t), isTrue);
      expect(result.inputExamples, [
        {'city': '上海'},
      ]);
      expect(result.contextSchema, contextSchema);
    });

    test('无 execute 的工具:execute 字段为 null', () {
      const inputSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
      });
      const t = Tool(inputSchema: inputSchema, description: '仅描述,无执行体');

      expect(t.execute, isNull);
    });

    test('有 execute 的工具:可正常调用并返回结果', () async {
      const inputSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'a': <String, Object?>{'type': 'number'},
          'b': <String, Object?>{'type': 'number'},
        },
      });
      final t = Tool(
        inputSchema: inputSchema,
        description: '两数相加',
        execute: (provider.JsonValue input, ToolExecuteOptions options) {
          final map = input as Map<String, Object?>;
          final a = map['a']! as num;
          final b = map['b']! as num;
          expect(options.context, {'requestId': 'call-context'});
          return a + b;
        },
      );

      final options = const ToolExecuteOptions(
        toolCallId: 'call_1',
        messages: <provider.LanguageModelMessage>[],
        context: {'requestId': 'call-context'},
      );
      final output =
          await t.execute!(<String, Object?>{'a': 1, 'b': 2}, options);

      expect(output, 3);
    });

    test('ToolExecuteOptions 值相等:相同字段判等', () {
      const a = ToolExecuteOptions(
        toolCallId: 'call_1',
        messages: <provider.LanguageModelMessage>[],
        context: {'requestId': 'same'},
      );
      const b = ToolExecuteOptions(
        toolCallId: 'call_1',
        messages: <provider.LanguageModelMessage>[],
        context: {'requestId': 'same'},
      );

      expect(a, equals(b));
    });

    test('Tool.provider 承载 ProviderTool 与 execute,inputSchema 为 null', () {
      const pt = provider.ProviderTool(
        id: 'x.foo',
        name: 'foo',
        args: <String, Object?>{},
      );
      final t = Tool.provider(
        pt,
        execute: (provider.JsonValue input, ToolExecuteOptions options) async =>
            'ok',
      );

      expect(t.providerTool, pt);
      expect(t.inputSchema, isNull);
      expect(t.execute, isNotNull);
    });

    test('普通 Tool 的 providerTool 为 null', () {
      const t = Tool(
        inputSchema: provider.JsonSchema(<String, Object?>{'type': 'object'}),
      );

      expect(t.providerTool, isNull);
      expect(t.inputSchema, isNotNull);
    });
  });

  group('buildLanguageModelTools', () {
    test(
        '函数工具→FunctionTool(name/description/inputSchema/examples 正确)、'
        'provider 工具→ProviderTool(key 作 name)', () {
      const weatherSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'city': <String, Object?>{'type': 'string'},
        },
        'required': <String>['city'],
      });
      const noopSchema = provider.JsonSchema(<String, Object?>{
        'type': 'object',
      });

      final tools = <String, Tool>{
        'get_weather': Tool(
          inputSchema: weatherSchema,
          description: '查询指定城市的天气',
          inputExamples: const [
            {'city': '上海'},
          ],
          execute: (provider.JsonValue input, ToolExecuteOptions options) =>
              'sunny',
        ),
        'noop': const Tool(inputSchema: noopSchema),
        'computer': Tool.provider(
          const provider.ProviderTool(
            id: 'anthropic.computer_20250124',
            name: 'computer',
            args: <String, Object?>{'displayWidthPx': 1024},
          ),
          execute:
              (provider.JsonValue input, ToolExecuteOptions options) async =>
                  null,
        ),
      };

      final out = buildLanguageModelTools(tools);

      expect(out, hasLength(3));
      final functionTools = out.whereType<provider.FunctionTool>().toList();
      expect(functionTools, hasLength(2));
      final weather = functionTools.firstWhere((f) => f.name == 'get_weather');
      expect(weather.description, '查询指定城市的天气');
      expect(weather.inputSchema, weatherSchema);
      expect(weather.inputExamples, [
        {'city': '上海'},
      ]);
      final noop = functionTools.firstWhere((f) => f.name == 'noop');
      expect(noop.description, isNull);
      expect(noop.inputSchema, noopSchema);
      expect(noop.inputExamples, isNull);

      final pt = out.whereType<provider.ProviderTool>().single;
      expect(pt.id, 'anthropic.computer_20250124');
      expect(pt.name, 'computer'); // = ToolSet key
      expect(pt.args, {'displayWidthPx': 1024});
    });

    test('provider 工具 key 与 wire name 不一致 → ArgumentError', () {
      final tools = <String, Tool>{
        'my_computer': Tool.provider(
          const provider.ProviderTool(
            id: 'anthropic.computer_20250124',
            name: 'computer',
            args: <String, Object?>{},
          ),
        ),
      };
      expect(() => buildLanguageModelTools(tools), throwsArgumentError);
    });

    test('空 ToolSet 产出空列表', () {
      expect(buildLanguageModelTools(<String, Tool>{}), isEmpty);
    });

    test('provider 工具的 supportsDeferredResults=true 经重建后保留', () {
      final tools = <String, Tool>{
        'code_execution': Tool.provider(
          const provider.ProviderTool(
            id: 'anthropic.code_execution_20250825',
            name: 'code_execution',
            args: <String, Object?>{},
            supportsDeferredResults: true,
          ),
        ),
      };

      final out = buildLanguageModelTools(tools);

      final pt = out.whereType<provider.ProviderTool>().single;
      expect(pt.supportsDeferredResults, isTrue);
      // 重建副本与原契约工具等值(props 含新字段,漏复制即不等)。
      expect(
        pt,
        equals(const provider.ProviderTool(
          id: 'anthropic.code_execution_20250825',
          name: 'code_execution',
          args: <String, Object?>{},
          supportsDeferredResults: true,
        )),
      );
    });

    test('未标记的 provider 工具经重建后 supportsDeferredResults 保持 false', () {
      final tools = <String, Tool>{
        'computer': Tool.provider(
          const provider.ProviderTool(
            id: 'anthropic.computer_20250124',
            name: 'computer',
            args: <String, Object?>{},
          ),
        ),
      };

      final out = buildLanguageModelTools(tools);

      final pt = out.whereType<provider.ProviderTool>().single;
      expect(pt.supportsDeferredResults, isFalse);
    });
  });
}
