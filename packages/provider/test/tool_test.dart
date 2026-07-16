import 'dart:typed_data';

import 'package:pigcode_ai_provider/src/json_value/json.dart';
import 'package:pigcode_ai_provider/src/shared/shared.dart';
import 'package:pigcode_ai_provider/src/language_model/tool.dart';
import 'package:test/test.dart';

void main() {
  group('LanguageModelTool', () {
    test('FunctionTool equality includes all fields', () {
      const schema = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'city': <String, Object?>{'type': 'string'},
        },
      });
      final a = FunctionTool(
        name: 'get_weather',
        description: 'Get the weather.',
        inputSchema: schema,
        inputExamples: const <JsonObject>[
          <String, Object?>{'city': 'Paris'},
        ],
        strict: true,
        providerOptions: const <String, JsonObject>{
          'openai': <String, Object?>{'cacheKey': 'w1'},
        },
      );
      final b = FunctionTool(
        name: 'get_weather',
        description: 'Get the weather.',
        inputSchema: const JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'city': <String, Object?>{'type': 'string'},
          },
        }),
        inputExamples: const <JsonObject>[
          <String, Object?>{'city': 'Paris'},
        ],
        strict: true,
        providerOptions: const <String, JsonObject>{
          'openai': <String, Object?>{'cacheKey': 'w1'},
        },
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('FunctionTool differs when a field differs', () {
      const schema = JsonSchema(<String, Object?>{'type': 'object'});
      const base = FunctionTool(name: 'a', inputSchema: schema);
      const differentName = FunctionTool(name: 'b', inputSchema: schema);
      const withDescription =
          FunctionTool(name: 'a', description: 'x', inputSchema: schema);
      const withStrict =
          FunctionTool(name: 'a', inputSchema: schema, strict: true);
      expect(base, isNot(equals(differentName)));
      expect(base, isNot(equals(withDescription)));
      expect(base, isNot(equals(withStrict)));
    });

    test('FunctionTool minimal optionals default to null', () {
      const tool = FunctionTool(
        name: 'noop',
        inputSchema: JsonSchema(<String, Object?>{}),
      );
      expect(tool.description, isNull);
      expect(tool.inputExamples, isNull);
      expect(tool.strict, isNull);
      expect(tool.providerOptions, isNull);
    });

    test('ProviderTool equality deep-compares args', () {
      const a = ProviderTool(
        id: 'openai.web_search',
        name: 'web_search',
        args: <String, Object?>{'maxResults': 5},
      );
      const b = ProviderTool(
        id: 'openai.web_search',
        name: 'web_search',
        args: <String, Object?>{'maxResults': 5},
      );
      const c = ProviderTool(
        id: 'openai.web_search',
        name: 'web_search',
        args: <String, Object?>{'maxResults': 10},
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('ProviderTool supportsDeferredResults defaults to false', () {
      const tool = ProviderTool(
        id: 'ns.tool',
        name: 'tool',
        args: <String, Object?>{},
      );
      expect(tool.supportsDeferredResults, isFalse);
    });

    test('ProviderTool supportsDeferredResults can be set to true', () {
      const tool = ProviderTool(
        id: 'anthropic.code_execution_20250825',
        name: 'code_execution',
        args: <String, Object?>{},
        supportsDeferredResults: true,
      );
      expect(tool.supportsDeferredResults, isTrue);
    });

    test('ProviderTool equality includes supportsDeferredResults', () {
      const marked = ProviderTool(
        id: 'ns.tool',
        name: 'tool',
        args: <String, Object?>{},
        supportsDeferredResults: true,
      );
      const unmarked = ProviderTool(
        id: 'ns.tool',
        name: 'tool',
        args: <String, Object?>{},
      );
      const explicitFalse = ProviderTool(
        id: 'ns.tool',
        name: 'tool',
        args: <String, Object?>{},
        supportsDeferredResults: false,
      );
      // 值不同不相等;缺省与显式 false 等值(默认值语义)。
      expect(marked, isNot(equals(unmarked)));
      expect(unmarked, equals(explicitFalse));
      expect(unmarked.hashCode, equals(explicitFalse.hashCode));
    });

    test('sealed switch is exhaustive over LanguageModelTool', () {
      const LanguageModelTool tool = ProviderTool(
        id: 'ns.tool',
        name: 'tool',
        args: <String, Object?>{},
      );
      final label = switch (tool) {
        FunctionTool() => 'function',
        ProviderTool() => 'provider',
      };
      expect(label, equals('provider'));
    });
  });

  group('ToolChoice', () {
    test('each variant is equatable to its own kind', () {
      expect(const ToolChoiceAuto(), equals(const ToolChoiceAuto()));
      expect(const ToolChoiceNone(), equals(const ToolChoiceNone()));
      expect(const ToolChoiceRequired(), equals(const ToolChoiceRequired()));
      expect(const ToolChoiceTool('search'),
          equals(const ToolChoiceTool('search')));
    });

    test('distinct variants are not equal', () {
      expect(const ToolChoiceAuto(), isNot(equals(const ToolChoiceNone())));
      expect(const ToolChoiceRequired(), isNot(equals(const ToolChoiceAuto())));
      expect(
          const ToolChoiceTool('a'), isNot(equals(const ToolChoiceTool('b'))));
    });

    test('ToolChoiceTool carries the tool name', () {
      const choice = ToolChoiceTool('lookup');
      expect(choice.toolName, equals('lookup'));
    });

    test('sealed switch is exhaustive over ToolChoice', () {
      const ToolChoice choice = ToolChoiceRequired();
      final label = switch (choice) {
        ToolChoiceAuto() => 'auto',
        ToolChoiceNone() => 'none',
        ToolChoiceRequired() => 'required',
        ToolChoiceTool(:final toolName) => 'tool:$toolName',
      };
      expect(label, equals('required'));
    });
  });

  group('ToolResultOutput', () {
    test('Text variant equality', () {
      expect(const ToolResultText('ok'), equals(const ToolResultText('ok')));
      expect(const ToolResultText('ok'),
          isNot(equals(const ToolResultText('no'))));
    });

    test('Json variant deep-compares nested value', () {
      const a = ToolResultJson(<String, Object?>{
        'items': <Object?>[1, 2, 3],
      });
      const b = ToolResultJson(<String, Object?>{
        'items': <Object?>[1, 2, 3],
      });
      expect(a, equals(b));
    });

    test('ExecutionDenied optional reason', () {
      expect(const ToolResultExecutionDenied(),
          equals(const ToolResultExecutionDenied()));
      expect(const ToolResultExecutionDenied(reason: 'blocked'),
          equals(const ToolResultExecutionDenied(reason: 'blocked')));
      expect(const ToolResultExecutionDenied(),
          isNot(equals(const ToolResultExecutionDenied(reason: 'blocked'))));
      expect(const ToolResultExecutionDenied().reason, isNull);
    });

    test('ErrorText and ErrorJson variants', () {
      expect(const ToolResultErrorText('boom'),
          equals(const ToolResultErrorText('boom')));
      expect(const ToolResultErrorJson(<String, Object?>{'code': 500}),
          equals(const ToolResultErrorJson(<String, Object?>{'code': 500})));
    });

    test('ContentOutput deep-compares its item list', () {
      final a = ToolResultContentOutput(<ToolResultContentItem>[
        const ToolResultTextItem('hello'),
        ToolResultFileItem(
          data: FileDataBytes(Uint8List.fromList(<int>[1, 2, 3])),
          mediaType: 'image/png',
          filename: 'shot.png',
        ),
      ]);
      final b = ToolResultContentOutput(<ToolResultContentItem>[
        const ToolResultTextItem('hello'),
        ToolResultFileItem(
          data: FileDataBytes(Uint8List.fromList(<int>[1, 2, 3])),
          mediaType: 'image/png',
          filename: 'shot.png',
        ),
      ]);
      final different = ToolResultContentOutput(<ToolResultContentItem>[
        const ToolResultTextItem('world'),
      ]);
      expect(a, equals(b));
      expect(a, isNot(equals(different)));
    });

    test('ToolResultContentItem variants equatable', () {
      expect(
          const ToolResultTextItem('x'), equals(const ToolResultTextItem('x')));
      final f1 = ToolResultFileItem(
        data: const FileDataBase64('YWJj'),
        mediaType: 'text/plain',
      );
      final f2 = ToolResultFileItem(
        data: const FileDataBase64('YWJj'),
        mediaType: 'text/plain',
      );
      expect(f1, equals(f2));
      expect(f1.filename, isNull);
    });

    test('ToolResultCustomItem carries providerOptions (v7 escape hatch)', () {
      const opts = <String, JsonObject>{
        'openai': <String, Object?>{'kind': 'widget'},
      };
      const item = ToolResultCustomItem(providerOptions: opts);
      expect(item, isA<ToolResultContentItem>());
      expect(item.providerOptions, same(opts));
      expect(item, isNot(const ToolResultCustomItem()));
      expect(item, const ToolResultCustomItem(providerOptions: opts));
    });

    test('sealed switch is exhaustive over ToolResultOutput', () {
      const ToolResultOutput output = ToolResultText('done');
      final label = switch (output) {
        ToolResultText() => 'text',
        ToolResultJson() => 'json',
        ToolResultExecutionDenied() => 'denied',
        ToolResultErrorText() => 'error-text',
        ToolResultErrorJson() => 'error-json',
        ToolResultContentOutput() => 'content',
      };
      expect(label, equals('text'));
    });

    test('output variants carry providerOptions and factor into equality', () {
      const opts = <String, JsonObject>{
        'openai': <String, Object?>{'cacheControl': 'ephemeral'},
      };
      const withOpts = ToolResultText('done', providerOptions: opts);
      expect(withOpts.providerOptions, same(opts));
      // providerOptions 进入值相等:不同选项 → 不相等,相同 → 相等。
      expect(withOpts, isNot(const ToolResultText('done')));
      expect(withOpts, const ToolResultText('done', providerOptions: opts));

      const item = ToolResultFileItem(
        data: FileDataText('x'),
        mediaType: 'text/plain',
        providerOptions: opts,
      );
      expect(item.providerOptions, same(opts));
      expect(
        item,
        isNot(const ToolResultFileItem(
          data: FileDataText('x'),
          mediaType: 'text/plain',
        )),
      );
    });
  });
}
