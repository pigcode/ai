import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 构造一个 JSON 响应(默认 200)。
http.StreamedResponse _jsonResponse(String body,
    {int statusCode = 200, Map<String, String> headers = const {}}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: {'content-type': 'application/json', ...headers},
  );
}

/// 记录最近一次请求体与请求头的测试客户端(照 openai 包模式)。
final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;
  http.BaseRequest? lastRequest;
  Map<String, Object?>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastBody = jsonDecode(request.body) as Map<String, Object?>;
    }
    return handler(request);
  }
}

AnthropicConfig _config(http.Client client,
    {Map<String, String> headers = const {'x-api-key': 'test-key'}}) {
  return AnthropicConfig(
    providerName: 'anthropic.messages',
    baseUrl: 'https://api.anthropic.com/v1',
    headers: () => headers,
    client: client,
  );
}

/// 最小成功响应体(Task 16 计划给定)。
String _minimalResponse() => jsonEncode({
      'type': 'message',
      'id': 'msg_1',
      'model': 'claude-sonnet-4-5',
      'content': [
        {'type': 'text', 'text': 'hi'},
      ],
      'stop_reason': 'end_turn',
      'stop_sequence': null,
      'usage': {'input_tokens': 5, 'output_tokens': 2},
    });

_RecordingClient _minimalClient(
    {Map<String, String> responseHeaders = const {}}) {
  return _RecordingClient(
    (request) async =>
        _jsonResponse(_minimalResponse(), headers: responseHeaders),
  );
}

const _prompt = <LanguageModelMessage>[
  UserMessage(<UserContentPart>[TextPart('hello')]),
];

void main() {
  group('AnthropicMessagesLanguageModel.doGenerate 基础请求体', () {
    test('身份、URL、model 透传与 stream 字段不出现(断言 1/8)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      expect(model.provider, 'anthropic.messages');
      expect(model.modelId, 'claude-sonnet-4-5');

      await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt),
      );

      expect(client.lastRequest!.url.toString(),
          'https://api.anthropic.com/v1/messages');
      expect(client.lastBody!['model'], 'claude-sonnet-4-5');
      expect(client.lastBody!.containsKey('stream'), isFalse);
      expect(client.lastBody!['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        },
      ]);
    });

    test('max_tokens 恒发:能力表默认 / 未知模型 4096 / 显式覆盖(断言 2)', () async {
      final client = _minimalClient();

      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));
      expect(client.lastBody!['max_tokens'], 64000);

      await AnthropicMessagesLanguageModel(
        'some-unknown-model',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));
      expect(client.lastBody!['max_tokens'], 4096);

      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(prompt: _prompt, maxOutputTokens: 1000),
      );
      expect(client.lastBody!['max_tokens'], 1000);
    });

    test('temperature clamp 到 [0, 1] 并产出 warning(断言 3)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final over = await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt, temperature: 1.5),
      );
      expect(client.lastBody!['temperature'], 1);
      expect(
        over.warnings,
        contains(const UnsupportedWarning(
          'temperature',
          details: '1.5 exceeds anthropic maximum of 1.0. clamped to 1.0',
        )),
      );

      final under = await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt, temperature: -0.5),
      );
      expect(client.lastBody!['temperature'], 0);
      expect(
        under.warnings.whereType<UnsupportedWarning>().map((w) => w.feature),
        contains('temperature'),
      );
    });

    test('frequencyPenalty/presencePenalty/seed 不支持:warning 且不发键(断言 4)',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          frequencyPenalty: 0.1,
          presencePenalty: 0.2,
          seed: 42,
        ),
      );

      expect(client.lastBody!.containsKey('frequency_penalty'), isFalse);
      expect(client.lastBody!.containsKey('presence_penalty'), isFalse);
      expect(client.lastBody!.containsKey('seed'), isFalse);
      expect(result.warnings,
          contains(const UnsupportedWarning('frequencyPenalty')));
      expect(result.warnings,
          contains(const UnsupportedWarning('presencePenalty')));
      expect(result.warnings, contains(const UnsupportedWarning('seed')));
    });

    test('rejectsSampling 模型裁剪 temperature/topK/topP(断言 5)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          temperature: 0.5,
          topK: 10,
          topP: 0.9,
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('top_k'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
          'temperature',
          details:
              'temperature is not supported by claude-fable-5 and will be ignored',
        )),
      );
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
          'topK',
          details:
              'topK is not supported by claude-fable-5 and will be ignored',
        )),
      );
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
          'topP',
          details:
              'topP is not supported by claude-fable-5 and will be ignored',
        )),
      );

      // 越界温度:先 clamp 后裁剪,temperature 产生两条 warning(spec 疑点 #10)。
      final doubled = await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt, temperature: 1.5),
      );
      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(
        doubled.warnings
            .whereType<UnsupportedWarning>()
            .where((w) => w.feature == 'temperature')
            .length,
        2,
      );
    });

    test('top_p 与 temperature 互斥,非 Anthropic 模型放行(断言 6)', () async {
      final client = _minimalClient();

      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          temperature: 0.5,
          topP: 0.9,
        ),
      );
      expect(client.lastBody!.containsKey('top_p'), isFalse);
      expect(client.lastBody!['temperature'], 0.5);
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
          'topP',
          details: 'topP is not supported when temperature is set. '
              'topP is ignored.',
        )),
      );

      await AnthropicMessagesLanguageModel(
        'minimax-m2',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          temperature: 0.5,
          topP: 0.9,
        ),
      );
      expect(client.lastBody!['temperature'], 0.5);
      expect(client.lastBody!['top_p'], 0.9);
    });

    test('stop_sequences/metadata/cache_control/inference_geo 透传(断言 7)',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          stopSequences: ['\n\n'],
          providerOptions: {
            'anthropic': {
              'metadata': {'userId': 'u1'},
              'cacheControl': {'type': 'ephemeral', 'ttl': '1h'},
              'inferenceGeo': 'us',
            },
          },
        ),
      );

      expect(client.lastBody!['stop_sequences'], ['\n\n']);
      expect(client.lastBody!['metadata'], {'user_id': 'u1'});
      expect(client.lastBody!['cache_control'],
          {'type': 'ephemeral', 'ttl': '1h'});
      expect(client.lastBody!['inference_geo'], 'us');

      // 未设置时对应键不出现。
      await model.doGenerate(const LanguageModelCallOptions(prompt: _prompt));
      expect(client.lastBody!.containsKey('stop_sequences'), isFalse);
      expect(client.lastBody!.containsKey('metadata'), isFalse);
      expect(client.lastBody!.containsKey('cache_control'), isFalse);
      expect(client.lastBody!.containsKey('inference_geo'), isFalse);
    });

    test('最小闭环出参:content/finishReason/usage/request/response(断言 9)', () async {
      final client = _minimalClient(responseHeaders: {'x-req-id': 'r-1'});
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt),
      );

      expect(result.content, [const TextContent('hi')]);
      expect(
        result.finishReason,
        const LanguageModelFinishReason(FinishReasonType.stop, raw: 'end_turn'),
      );
      expect(result.usage.inputTokens.total, 5);
      expect(result.usage.outputTokens.total, 2);
      expect(result.request!.body, client.lastBody);
      expect(result.response!.id, 'msg_1');
      expect(result.response!.modelId, 'claude-sonnet-4-5');
      expect(result.response!.headers!['x-req-id'], 'r-1');
    });

    test('config.headers 与 options.headers 合并进请求头(断言 10)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client, headers: {
          'x-api-key': 'test-key',
          'anthropic-version': '2023-06-01',
        }),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          headers: {'x-custom': 'yes'},
        ),
      );

      expect(client.lastRequest!.headers['x-api-key'], 'test-key');
      expect(client.lastRequest!.headers['anthropic-version'], '2023-06-01');
      expect(client.lastRequest!.headers['x-custom'], 'yes');
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate tools 接线', () {
    test('function tools + toolChoice 接线,prepare warnings 并入(断言 11)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
            ProviderTool(
              id: 'anthropic.web_search',
              name: 'web_search',
              args: {},
            ),
          ],
          toolChoice: ToolChoiceAuto(),
        ),
      );

      expect(client.lastBody!['tools'], [
        {
          'name': 'get_weather',
          'input_schema': {'type': 'object'},
        },
      ]);
      expect(client.lastBody!['tool_choice'], {'type': 'auto'});
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
            'provider-defined tool anthropic.web_search')),
      );
    });

    test('toolStreaming 非流式默认:无 eager_input_streaming,工具级可覆盖(断言 11b)',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      );
      const tool = FunctionTool(
        name: 'get_weather',
        inputSchema: JsonSchema({'type': 'object'}),
      );

      // 默认:doGenerate(stream=false)恒不发。
      await model.doGenerate(
        const LanguageModelCallOptions(prompt: _prompt, tools: [tool]),
      );
      var wireTool = (client.lastBody!['tools']! as List<Object?>).first!
          as Map<String, Object?>;
      expect(wireTool.containsKey('eager_input_streaming'), isFalse);

      // 显式 toolStreaming: true 亦然(非流式恒 false)。
      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [tool],
          providerOptions: {
            'anthropic': {'toolStreaming': true},
          },
        ),
      );
      wireTool = (client.lastBody!['tools']! as List<Object?>).first!
          as Map<String, Object?>;
      expect(wireTool.containsKey('eager_input_streaming'), isFalse);

      // 工具级 providerOptions.anthropic.eagerInputStreaming: true 覆盖默认。
      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
              providerOptions: {
                'anthropic': {'eagerInputStreaming': true},
              },
            ),
          ],
        ),
      );
      wireTool = (client.lastBody!['tools']! as List<Object?>).first!
          as Map<String, Object?>;
      expect(wireTool['eager_input_streaming'], true);
    });
  });

  group('AnthropicMessagesLanguageModel anthropic-beta 头合成', () {
    test('prompt PDF file part 触发 pdfs beta(断言 12a)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage(<UserContentPart>[
              FilePart(
                data: FileDataBase64('QUJD'),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
        ),
      );

      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('pdfs-2024-09-25'));
    });

    test('providerOptions.anthropicBeta 并入头(断言 12b)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'anthropicBeta': ['context-1m-2025-08-07'],
            },
          },
        ),
      );

      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('context-1m-2025-08-07'));
    });

    test('headers 自带 anthropic-beta:解析、小写、合并去重后重发(断言 12c)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client, headers: {
          'x-api-key': 'test-key',
          'anthropic-beta': 'Files-API-2025-04-14, foo',
        }),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              // 与 header 内的 beta 重复,验证 Set 去重。
              'anthropicBeta': ['foo', 'bar'],
            },
          },
        ),
      );

      final headerValue = client.lastRequest!.headers['anthropic-beta']!;
      final betas = anthropicBetasFromHeaderValue(headerValue);
      expect(betas, {'files-api-2025-04-14', 'foo', 'bar'});
      // 重发值本身已小写(合成前统一 toLowerCase)。
      expect(headerValue, equals(headerValue.toLowerCase()));
    });

    test('supportsStructuredOutput 模型 + function tool 触发结构化输出 beta(断言 12d)',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
          ],
        ),
      );

      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('structured-outputs-2025-11-13'));
    });

    test('无任何 beta 来源时不发 anthropic-beta 头(断言 12e)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate thinking', () {
    test('enabled 带 budget:thinking 体 + max_tokens 加成/裁剪(断言 1)', () async {
      final client = _minimalClient();

      // 未显式传 maxOutputTokens:64000+2048 超 cap 裁到 64000,不警告
      // (报告 03 §16 疑点 6 静默裁剪)。
      final silent = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'enabled', 'budgetTokens': 2048},
            },
          },
        ),
      );
      expect(client.lastBody!['thinking'],
          {'type': 'enabled', 'budget_tokens': 2048});
      expect(client.lastBody!['max_tokens'], 64000);
      expect(silent.warnings, isEmpty);

      // 显式 maxOutputTokens:裁剪且发 warning(details 字面量,§8.3)。
      final warned = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          maxOutputTokens: 60000,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'enabled', 'budgetTokens': 8000},
            },
          },
        ),
      );
      expect(client.lastBody!['max_tokens'], 64000);
      expect(
        warned.warnings,
        contains(const CompatibilityWarning(
          'maxOutputTokens',
          details: '68000 (maxOutputTokens + thinkingBudget) is greater than '
              'claude-sonnet-4-5 64000 max output tokens. '
              'The max output tokens have been limited to 64000.',
        )),
      );

      // 未知模型不裁剪。
      await AnthropicMessagesLanguageModel(
        'some-unknown-model',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          maxOutputTokens: 999999,
        ),
      );
      expect(client.lastBody!['max_tokens'], 999999);
    });

    test('enabled 缺 budget:补默认 1024 + CompatibilityWarning(断言 2)', () async {
      final client = _minimalClient();
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          maxOutputTokens: 1000,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'enabled'},
            },
          },
        ),
      );

      expect(
        result.warnings,
        contains(const CompatibilityWarning(
          'thinking',
          details: 'thinking budget is required when thinking is enabled. '
              'using default budget of 1024 tokens.',
        )),
      );
      expect(client.lastBody!['thinking'],
          {'type': 'enabled', 'budget_tokens': 1024});
      // max_tokens += 1024(1000 + 1024,未超 cap 不裁剪)。
      expect(client.lastBody!['max_tokens'], 2024);
    });

    test('thinking 下采样清除:temperature/topK/topP 各一条 warning(断言 3)', () async {
      final client = _minimalClient();
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          temperature: 0.5,
          topK: 10,
          topP: 0.9,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'enabled', 'budgetTokens': 2048},
            },
          },
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('top_k'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
      for (final feature in ['temperature', 'topK', 'topP']) {
        expect(
          result.warnings.whereType<UnsupportedWarning>().where((w) =>
              w.feature == feature &&
              (w.details ?? '')
                  .contains('is not supported when thinking is enabled')),
          hasLength(1),
          reason: 'expected one thinking-clearing warning for $feature',
        );
      }
    });

    test('adaptive:display 透传/缺省,max_tokens 不加成(断言 4)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'adaptive', 'display': 'summarized'},
            },
          },
        ),
      );
      expect(client.lastBody!['thinking'],
          {'type': 'adaptive', 'display': 'summarized'});
      // adaptive 无 budget,max_tokens 不加成(能力表 cap 128000 原值)。
      expect(client.lastBody!['max_tokens'], 128000);

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'adaptive'},
            },
          },
        ),
      );
      expect(client.lastBody!['thinking'], {'type': 'adaptive'});
    });

    test('disabled:转发 {type: disabled},采样参数不清除(断言 5)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          temperature: 0.5,
          topK: 10,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'disabled'},
            },
          },
        ),
      );

      // 必须转发 disabled(origin/main :425-428 sendThinking 增量),
      // 且无 budget_tokens/display 键。
      expect(client.lastBody!['thinking'], {'type': 'disabled'});
      // max_tokens 不加成。
      expect(client.lastBody!['max_tokens'], 64000);
      // 采样清除条件是 isThinking(enabled||adaptive),disabled 保留发送。
      expect(client.lastBody!['temperature'], 0.5);
      expect(client.lastBody!['top_k'], 10);
      expect(
        result.warnings.whereType<UnsupportedWarning>().where((w) =>
            (w.details ?? '')
                .contains('is not supported when thinking is enabled')),
        isEmpty,
      );

      // topP 单独设置时(不与 temperature 同设,避开 §7.2 互斥)同样保留。
      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          topP: 0.9,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'disabled'},
            },
          },
        ),
      );
      expect(client.lastBody!['top_p'], 0.9);
    });

    test('ReasoningEffort.none → 转发 disabled,无 effort(断言 6a)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.none,
        ),
      );

      expect(client.lastBody!['thinking'], {'type': 'disabled'});
      expect(client.lastBody!.containsKey('output_config'), isFalse);
    });

    test('adaptive 模型 reasoning 映射:thinking adaptive + effort(断言 6b)',
        () async {
      final client = _minimalClient();

      // medium → 'medium'(同名不警告)。
      final medium = await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.medium,
        ),
      );
      expect(client.lastBody!['thinking'], {'type': 'adaptive'});
      expect(client.lastBody!['output_config'], {'effort': 'medium'});
      expect(medium.warnings.whereType<CompatibilityWarning>(), isEmpty);

      // supportsXhighEffort 模型 xhigh → 'xhigh'。
      await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.xhigh,
        ),
      );
      expect(client.lastBody!['output_config'], {'effort': 'xhigh'});

      // 不支持 xhigh 的 adaptive 模型:xhigh → 'max' + CompatibilityWarning
      // (映射到不同名;文案不锁定只断言类型)。
      final maxed = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-6',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.xhigh,
        ),
      );
      expect(client.lastBody!['output_config'], {'effort': 'max'});
      expect(maxed.warnings.whereType<CompatibilityWarning>(), isNotEmpty);

      // minimal → 'low' 同为不同名映射,有 warning。
      final lowered = await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.minimal,
        ),
      );
      expect(client.lastBody!['output_config'], {'effort': 'low'});
      expect(lowered.warnings.whereType<CompatibilityWarning>(), isNotEmpty);
    });

    test('经典模型 reasoning 映射:enabled + clamp budget(断言 6c)', () async {
      final client = _minimalClient();

      // claude-haiku-4-5(cap 64000)+ medium:
      // budget = clamp(round(64000×0.3), 1024, 64000) = 19200;
      // max_tokens = 64000 + 19200 → 裁到 cap 64000。
      await AnthropicMessagesLanguageModel(
        'claude-haiku-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.medium,
        ),
      );
      expect(client.lastBody!['thinking'],
          {'type': 'enabled', 'budget_tokens': 19200});
      expect(client.lastBody!['max_tokens'], 64000);
      expect(client.lastBody!.containsKey('output_config'), isFalse);

      // claude-opus-4-1(cap 32000)+ minimal:round(32000×0.02)=640 →
      // clamp 下限 1024;max_tokens = 32000 + 1024 → 裁到 32000。
      await AnthropicMessagesLanguageModel(
        'claude-opus-4-1',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.minimal,
        ),
      );
      expect(client.lastBody!['thinking'],
          {'type': 'enabled', 'budget_tokens': 1024});
      expect(client.lastBody!['max_tokens'], 32000);
    });

    test('providerOptions 优先:显式 thinking/effort 阻断 reasoning 映射(断言 6d)',
        () async {
      final client = _minimalClient();

      // 显式 thinking disabled + reasoning high:disabled 照转发,
      // effort 不映射(:410-418,disabled 阻断 effort 填充)。
      await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.high,
          providerOptions: {
            'anthropic': {
              'thinking': {'type': 'disabled'},
            },
          },
        ),
      );
      expect(client.lastBody!['thinking'], {'type': 'disabled'});
      expect(client.lastBody!.containsKey('output_config'), isFalse);

      // 显式 effort + reasoning:effort 取显式值,整个映射不执行
      // (thinking 也不被填充)。
      await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.high,
          providerOptions: {
            'anthropic': {'effort': 'low'},
          },
        ),
      );
      expect(client.lastBody!['output_config'], {'effort': 'low'});
      expect(client.lastBody!.containsKey('thinking'), isFalse);
    });

    test('reasoning providerDefault 视为未设置(断言 6e)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-fable-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          reasoning: ReasoningEffort.providerDefault,
        ),
      );

      expect(client.lastBody!.containsKey('thinking'), isFalse);
      expect(client.lastBody!.containsKey('output_config'), isFalse);
    });

    test('effort 直设:仅发 output_config,不自动生成 thinking(断言 7)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'effort': 'high'},
          },
        ),
      );

      expect(client.lastBody!['output_config'], {'effort': 'high'});
      expect(client.lastBody!.containsKey('thinking'), isFalse);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate 结构化输出', () {
    // 契约 ResponseFormatJson.schema 是 JsonSchema 薄封装(response_format
    // .dart:19),测试统一用该封装传参。
    const schema = JsonSchema({
      'type': 'object',
      'properties': {
        'a': {'type': 'string'},
      },
      'required': ['a'],
    });

    /// body['tools'] 中是否含 name 为 'json' 的工具。
    bool hasJsonTool(Map<String, Object?> body) {
      final tools = body['tools'] as List<Object?>?;
      if (tools == null) {
        return false;
      }
      return tools
          .cast<Map<String, Object?>>()
          .any((tool) => tool['name'] == 'json');
    }

    test('原生模式:支持模型 + auto → output_config.format,无 json tool(断言 1)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
        ),
      );

      // 期望 schema 用 sanitizeJsonSchema 现算(清洗字面量归 Task 10 测试)。
      expect(client.lastBody!['output_config'], {
        'format': {
          'type': 'json_schema',
          'schema': sanitizeJsonSchema(schema.value),
        },
      });
      expect(hasJsonTool(client.lastBody!), isFalse);
      expect(client.lastBody!.containsKey('tool_choice'), isFalse);
    });

    test("mode 'outputFormat' 强制原生:不支持模型仍走 output_config(断言 2a)", () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
          providerOptions: {
            'anthropic': {'structuredOutputMode': 'outputFormat'},
          },
        ),
      );

      expect(client.lastBody!['output_config'], {
        'format': {
          'type': 'json_schema',
          'schema': sanitizeJsonSchema(schema.value),
        },
      });
      expect(hasJsonTool(client.lastBody!), isFalse);
    });

    test("mode 'jsonTool' 强制回退:支持模型也走 json tool(断言 2b)", () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
          providerOptions: {
            'anthropic': {'structuredOutputMode': 'jsonTool'},
          },
        ),
      );

      expect(hasJsonTool(client.lastBody!), isTrue);
      expect(client.lastBody!.containsKey('output_config'), isFalse);
    });

    test('schema 缺失 → OtherWarning,既无 format 也无 json tool(断言 3)', () async {
      final client = _minimalClient();
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(),
        ),
      );

      expect(
        result.warnings,
        contains(const OtherWarning(
          'JSON response format requires a schema. '
          'The response format is ignored.',
        )),
      );
      expect(client.lastBody!.containsKey('output_config'), isFalse);
      expect(client.lastBody!.containsKey('tools'), isFalse);
    });

    test('json tool 回退请求侧:tool 形态 + tool_choice any(断言 4)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
        ),
      );

      // json tool 路径不清洗 schema,照上游原样直传(origin/main :354)。
      expect(client.lastBody!['tools'], [
        {
          'name': 'json',
          'description': 'Respond with a JSON object.',
          'input_schema': schema.value,
        },
      ]);
      // ToolChoiceRequired + disableParallelToolUse: true 的映射产物
      // (:738-747 + Task 13 映射表)。
      expect(client.lastBody!['tool_choice'], {
        'type': 'any',
        'disable_parallel_tool_use': true,
      });
      expect(client.lastBody!.containsKey('output_config'), isFalse);
    });

    test('json tool 回退:用户自带 function tool 时追加在其后(断言 4c)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
          ],
        ),
      );

      final tools = (client.lastBody!['tools']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(tools, hasLength(2));
      expect(tools.first['name'], 'get_weather');
      expect(tools.last['name'], 'json');
    });

    test('回退模式响应:text 块忽略、json tool_use 转 text、tool_use→stop(断言 5)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'type': 'message',
          'content': [
            {'type': 'text', 'text': "I'll return JSON"},
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'json',
              'input': {'a': 'x'},
            },
          ],
          'stop_reason': 'tool_use',
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        })),
      );
      final result = await AnthropicMessagesLanguageModel(
        'claude-3-haiku-20240307',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
        ),
      );

      expect(result.content, [const TextContent('{"a":"x"}')]);
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.finishReason.raw, 'tool_use');
    });

    test('原生模式响应不受影响:text 正常输出、end_turn → stop(断言 6)', () async {
      final client = _minimalClient();
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          responseFormat: ResponseFormatJson(schema: schema),
        ),
      );

      expect(result.content, [const TextContent('hi')]);
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.finishReason.raw, 'end_turn');
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate 响应解析', () {
    /// 用给定 content 数组构造完整 wire 响应体。
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test('content 混排保序:thinking/redacted/text/tool_use(断言 1-4)', () async {
      final client = clientWith([
        {
          'type': 'thinking',
          'thinking': 'let me think',
          'signature': 'sig_abc',
        },
        {'type': 'redacted_thinking', 'data': 'blob=='},
        {'type': 'text', 'text': 'answer'},
        {
          'type': 'tool_use',
          'id': 'toolu_9',
          'name': 'get_weather',
          'input': {'city': 'sf'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ReasoningContent('let me think', providerMetadata: {
          'anthropic': {'signature': 'sig_abc'},
        }),
        ReasoningContent('', providerMetadata: {
          'anthropic': {'redactedData': 'blob=='},
        }),
        TextContent('answer'),
        ToolCall(
          toolCallId: 'toolu_9',
          toolName: 'get_weather',
          input: '{"city":"sf"}',
        ),
      ]);
    });

    test('tool_use caller → providerMetadata(direct / code_execution)',
        () async {
      final client = clientWith([
        {
          'type': 'tool_use',
          'id': 'toolu_1',
          'name': 'get_weather',
          'input': {'city': 'sf'},
          'caller': {'type': 'direct'},
        },
        {
          'type': 'tool_use',
          'id': 'toolu_2',
          'name': 'get_weather',
          'input': {'city': 'la'},
          'caller': {
            'type': 'code_execution_20250825',
            'tool_id': 'srvtoolu_1',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'toolu_1',
          toolName: 'get_weather',
          input: '{"city":"sf"}',
          providerMetadata: {
            'anthropic': {
              'caller': {'type': 'direct'},
            },
          },
        ),
        ToolCall(
          toolCallId: 'toolu_2',
          toolName: 'get_weather',
          input: '{"city":"la"}',
          providerMetadata: {
            'anthropic': {
              'caller': {
                'type': 'code_execution_20250825',
                'toolId': 'srvtoolu_1',
              },
            },
          },
        ),
      ]);
    });

    final pdfPrompt = <LanguageModelMessage>[
      UserMessage(<UserContentPart>[
        FilePart(
          data: FileDataUrl(Uri.parse('https://e.com/doc.pdf')),
          mediaType: 'application/pdf',
          filename: 'doc.pdf',
          providerOptions: const {
            'anthropic': {
              'citations': {'enabled': true},
            },
          },
        ),
        const TextPart('cite this'),
      ]),
    ];

    test('citations page_location → SourceContent.document(断言 5)', () async {
      final client = clientWith([
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'page_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': 'T',
              'start_page_number': 2,
              'end_page_number': 3,
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(prompt: pdfPrompt));

      expect(result.content, hasLength(2));
      expect(result.content[0], const TextContent('answer'));
      final source = result.content[1] as SourceContent;
      expect(source.sourceType, SourceType.document);
      expect(source.id, isNotEmpty);
      expect(source.mediaType, 'application/pdf');
      expect(source.title, 'T');
      expect(source.filename, 'doc.pdf');
      expect(source.providerMetadata, {
        'anthropic': {
          'citedText': 'quote',
          'startPageNumber': 2,
          'endPageNumber': 3,
        },
      });
    });

    test('citations char_location 映射;document_index 越界丢弃;title 回退 filename',
        () async {
      final client = clientWith([
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'char_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': null,
              'start_char_index': 10,
              'end_char_index': 20,
            },
            {
              'type': 'char_location',
              'cited_text': 'lost',
              'document_index': 5,
              'document_title': 'X',
              'start_char_index': 1,
              'end_char_index': 2,
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(prompt: pdfPrompt));

      // 越界 citation 丢弃不 throw,只留 text + 一条 source。
      expect(result.content, hasLength(2));
      final source = result.content[1] as SourceContent;
      expect(source.sourceType, SourceType.document);
      expect(source.mediaType, 'application/pdf');
      expect(source.title, 'doc.pdf');
      expect(source.filename, 'doc.pdf');
      expect(source.providerMetadata, {
        'anthropic': {
          'citedText': 'quote',
          'startCharIndex': 10,
          'endCharIndex': 20,
        },
      });
    });

    test('探测型 citation document:顶级-only mediaType + PDF 魔数字节', () async {
      final pdfBytes = Uint8List.fromList('%PDF-1.4'.codeUnits);
      final prompt = <LanguageModelMessage>[
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBytes(pdfBytes),
            mediaType: 'application',
            providerOptions: const {
              'anthropic': {
                'citations': {'enabled': true},
              },
            },
          ),
          const TextPart('cite this'),
        ]),
      ];
      final client = clientWith([
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'char_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': null,
              'start_char_index': 0,
              'end_char_index': 4,
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(prompt: prompt));

      expect(result.content, hasLength(2));
      final source = result.content[1] as SourceContent;
      expect(source.sourceType, SourceType.document);
      expect(source.mediaType, 'application/pdf');
      // 无 filename:title 回退 'Untitled Document'。
      expect(source.title, 'Untitled Document');
      expect(source.filename, isNull);
    });

    test('未识别块静默跳过:server_tool_use(未知 name)/ fallback(断言 6)', () async {
      final client = clientWith([
        {
          // web_search/web_fetch 已在 Task 4 接入白名单;code_execution 随
          // 白名单扩容(报告 09 §3.2)已不再是"未知 name",此处改用
          // future_server_tool 保持"未知 name 静默丢弃"断言有效。
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'future_server_tool',
          'input': {'query': 'x'},
        },
        {'type': 'fallback', 'model': 'x'},
        {'type': 'text', 'text': 'ok'},
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, [const TextContent('ok')]);
    });

    test('response 元数据:body 为完整 wire 响应;id/model nullish 不炸(断言 7)', () async {
      final wire = <String, Object?>{
        'type': 'message',
        'content': [
          {'type': 'text', 'text': 'hi'},
        ],
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 1, 'output_tokens': 1},
      };
      final client =
          _RecordingClient((request) async => _jsonResponse(jsonEncode(wire)));
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.response!.id, isNull);
      expect(result.response!.modelId, isNull);
      expect(result.response!.body, wire);
    });
  });

  group('client tool 普通 tool_use(Task 15)', () {
    // 报告 08 §4/§5:computer/text_editor/bash 等 client 工具走普通
    // tool_use 通道,provider 对其调用/回流无任何专用分支——因此响应解析
    // 结果与普通函数工具一致,`providerExecuted` 为 null（而非
    // server_tool_use 走的 `true`）。
    test(
        'doGenerate:tool_use(name=computer) → ToolCall,providerExecuted 为 null',
        () async {
      final wire = jsonEncode({
        'type': 'message',
        'id': 'msg_1',
        'model': 'claude-sonnet-4-5',
        'content': [
          {
            'type': 'tool_use',
            'id': 'tu_1',
            'name': 'computer',
            'input': {'action': 'screenshot'},
          },
        ],
        'stop_reason': 'tool_use',
        'stop_sequence': null,
        'usage': {'input_tokens': 5, 'output_tokens': 2},
      });
      final client = _RecordingClient((request) async => _jsonResponse(wire));
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'tu_1',
          toolName: 'computer',
          input: '{"action":"screenshot"}',
        ),
      ]);
      expect((result.content.single as ToolCall).providerExecuted, isNull);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate server_tool_use', () {
    /// 用给定 content 数组构造完整 wire 响应体(同"响应解析" group 模式)。
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test('web_search server_tool_use → ToolCall(providerExecuted: true)',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_1',
          toolName: 'web_search',
          input: '{"query":"dart"}',
          providerExecuted: true,
        ),
      ]);
    });

    test('web_fetch server_tool_use → ToolCall(providerExecuted: true)',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_2',
          'name': 'web_fetch',
          'input': {'url': 'https://e.com'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_2',
          toolName: 'web_fetch',
          input: '{"url":"https://e.com"}',
          providerExecuted: true,
        ),
      ]);
    });

    test('input 为空对象 {} → input 字符串化为 "{}"', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_3',
          'name': 'web_search',
          'input': <String, Object?>{},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_3',
          toolName: 'web_search',
          input: '{}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        '未知 name 静默丢弃:future_server_tool(白名单外,报告 09 §3.2 无'
        '兜底 else,与批次 1/2 的 default 静默丢弃语义一致)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_4',
          'name': 'future_server_tool',
          'input': {'x': 1},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test(
        'bash_code_execution 子工具 → toolName 归一 code_execution + type 键'
        '注入在最前(无空格,jsonEncode 字节形态,报告 09 §3.2a :1025-1046)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_20',
          'name': 'bash_code_execution',
          'input': {'command': 'ls'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_20',
          toolName: 'code_execution',
          input: '{"type":"bash_code_execution","command":"ls"}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        'text_editor_code_execution 子工具 → toolName 归一 code_execution + '
        'type 键注入', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_21',
          'name': 'text_editor_code_execution',
          'input': {'command': 'view', 'path': '/tmp/a.py'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_21',
          toolName: 'code_execution',
          input: '{"type":"text_editor_code_execution","command":"view",'
              '"path":"/tmp/a.py"}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        'code_execution 直接调用、input 含 code 无 type(20250522/'
        'programmatic 场景)→ 注入 programmatic-tool-call(无空格,报告 09 '
        '§3.2b :1052-1060,与 doStream 首 delta 注入的带空格形态是两种字节'
        '形态——09 §9.3)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_22',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_22',
          toolName: 'code_execution',
          input: '{"type":"programmatic-tool-call","code":"print(1)"}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        'code_execution 直接调用、input 已含 type(20260120 continuation 场'
        '景)→ 不重复注入,原样序列化', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_23',
          'name': 'code_execution',
          'input': {'type': 'programmatic-tool-call', 'code': 'print(2)'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_23',
          toolName: 'code_execution',
          input: '{"type":"programmatic-tool-call","code":"print(2)"}',
          providerExecuted: true,
        ),
      ]);
    });

    test('tool_search_tool_regex 直接调用 → 原样透传,无 dynamic', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_24',
          'name': 'tool_search_tool_regex',
          'input': {'pattern': 'weather', 'limit': 10},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_24',
          toolName: 'tool_search_tool_regex',
          input: '{"pattern":"weather","limit":10}',
          providerExecuted: true,
        ),
      ]);
    });

    test('tool_search_tool_bm25 直接调用 → 原样透传', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_25',
          'name': 'tool_search_tool_bm25',
          'input': {'query': 'weather forecast'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_25',
          toolName: 'tool_search_tool_bm25',
          input: '{"query":"weather forecast"}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        'advisor 直接调用 → input 原样序列化(wire 恒 {},报告 09 §3.2d '
        ':1088-1095,非硬置)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_26',
          'name': 'advisor',
          'input': <String, Object?>{},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_26',
          toolName: 'advisor',
          input: '{}',
          providerExecuted: true,
        ),
      ]);
    });

    test(
        'dynamic 标记在场:请求含 web_search_20260209 且无同名 code_execution '
        '工具 → code_execution ToolCall.isDynamic == true(报告 09 §3.1,D7)',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_27',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        tools: [
          const ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
        ],
      ));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_27',
          toolName: 'code_execution',
          input: '{"type":"programmatic-tool-call","code":"print(1)"}',
          providerExecuted: true,
          isDynamic: true,
        ),
      ]);
    });

    test('dynamic 标记缺席:请求未含 web 20260209 工具 → isDynamic 为 null', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_28',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_28',
          toolName: 'code_execution',
          input: '{"type":"programmatic-tool-call","code":"print(1)"}',
          providerExecuted: true,
        ),
      ]);
      expect((result.content.single as ToolCall).isDynamic, isNull);
    });

    test(
        'dynamic 标记抑制:同名 code_execution function tool 在场 → '
        'isDynamic 为 null(报告 09 §3.1 :2694,name 判定含 function tool 抑'
        '制,与 wire type 判定的 web 工具无关)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_29',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        tools: [
          const ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
          FunctionTool(
            name: 'code_execution',
            inputSchema: const JsonSchema({'type': 'object'}),
          ),
        ],
      ));

      expect((result.content.single as ToolCall).isDynamic, isNull);
    });

    test(
        'dynamic 标记对子工具同样恒真(defensive 写法,报告 09 §9.5/spec 疑'
        '点 11,照抄)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_30',
          'name': 'bash_code_execution',
          'input': {'command': 'ls'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        tools: [
          const ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
        ],
      ));

      expect((result.content.single as ToolCall).isDynamic, true);
    });

    test('caller 忽略:ToolCall 无 providerMetadata', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_5',
          'name': 'web_search',
          'input': {'query': 'dart'},
          'caller': {'type': 'direct'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolCall(
          toolCallId: 'srvtoolu_5',
          toolName: 'web_search',
          input: '{"query":"dart"}',
          providerExecuted: true,
        ),
      ]);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate web_search_tool_result', () {
    /// 用给定 content 数组构造完整 wire 响应体(同"响应解析" group 模式)。
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test('成功数组 → ToolResult(snake→camel) + 每条一个 SourceContent.url', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'encrypted_content': 'enc1',
              'page_age': '1d',
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, hasLength(3));
      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'web_search',
          result: [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'pageAge': '1d',
              'encryptedContent': 'enc1',
            },
          ],
        ),
      );
      expect((result.content[1] as ToolResult).isError, isNull);

      final source = result.content[2] as SourceContent;
      expect(source.sourceType, SourceType.url);
      expect(source.id, isNotEmpty);
      expect(source.url, 'https://r.com');
      expect(source.title, 'R');
      expect(source.providerMetadata, {
        'anthropic': {'pageAge': '1d'},
      });
    });

    test('两条结果 → 两个 source', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': [
            {
              'type': 'web_search_result',
              'url': 'https://r1.com',
              'title': 'R1',
              'encrypted_content': 'enc1',
              'page_age': '1d',
            },
            {
              'type': 'web_search_result',
              'url': 'https://r2.com',
              'title': 'R2',
              'encrypted_content': 'enc2',
              'page_age': '2d',
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, hasLength(4));
      expect(result.content.whereType<SourceContent>(), hasLength(2));
    });

    test('page_age 缺失 → pageAge null(result 与 source 均归一)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'encrypted_content': 'enc1',
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final toolResult = result.content[1] as ToolResult;
      expect(
        (toolResult.result! as List<Object?>)
            .cast<Map<String, Object?>>()
            .single['pageAge'],
        isNull,
      );
      final source = result.content[2] as SourceContent;
      expect(source.providerMetadata, {
        'anthropic': {'pageAge': null},
      });
    });

    test('错误(content 非数组) → ToolResult(isError: true) 无 source', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': {
            'type': 'web_search_tool_result_error',
            'error_code': 'max_uses_exceeded',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, hasLength(2));
      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'web_search',
          result: {
            'type': 'web_search_tool_result_error',
            'errorCode': 'max_uses_exceeded',
          },
          isError: true,
        ),
      );
      expect(result.content.whereType<SourceContent>(), isEmpty);
    });

    test('不追加 citationDocuments:page_location citation 无匹配文档时丢弃', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'encrypted_content': 'enc1',
              'page_age': '1d',
            },
          ],
        },
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'page_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': 'T',
              'start_page_number': 2,
              'end_page_number': 3,
            },
          ],
        },
      ]);
      // 无 citationDocuments 输入(prompt 不带带 citations 的 FilePart)。
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      // server_tool_use ToolCall + web_search ToolResult + source(url) +
      // text;document_index 0 在空 citationDocuments 中越界丢弃,无 document
      // source。
      expect(result.content.whereType<TextContent>(), hasLength(1));
      final sources = result.content.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      expect(sources.single.sourceType, SourceType.url);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate web_fetch_tool_result', () {
    /// 用给定 content 数组构造完整 wire 响应体(同"响应解析" group 模式)。
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test('wire 无 citations → result content 不含 citations 键(codex PR #61)',
        () async {
      // optional 字段缺席语义:写 null 键会让回传侧 validator 拒绝(往返自洽)。
      final client = clientWith([
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_9',
          'content': {
            'type': 'web_fetch_result',
            'url': 'https://d.com/p.txt',
            'retrieved_at': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'P',
              'source': {
                'type': 'text',
                'media_type': 'text/plain',
                'data': 'hello',
              },
            },
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final toolResult = result.content.single as ToolResult;
      final content = (toolResult.result! as Map<String, Object?>)['content']!
          as Map<String, Object?>;
      expect(content.containsKey('citations'), isFalse);
    });

    test('成功 → ToolResult(snake→camel:retrieved_at/media_type) 无 source',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_2',
          'name': 'web_fetch',
          'input': {'url': 'https://d.com/a.pdf'},
        },
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_2',
          'content': {
            'type': 'web_fetch_result',
            'url': 'https://d.com/a.pdf',
            'retrieved_at': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'Doc A',
              'citations': {'enabled': true},
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': 'JVBERi0=',
              },
            },
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, hasLength(2));
      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'web_fetch',
          result: {
            'type': 'web_fetch_result',
            'url': 'https://d.com/a.pdf',
            'retrievedAt': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'Doc A',
              'citations': {'enabled': true},
              'source': {
                'type': 'base64',
                'mediaType': 'application/pdf',
                'data': 'JVBERi0=',
              },
            },
          },
        ),
      );
      expect((result.content[1] as ToolResult).isError, isNull);
      expect(result.content.whereType<SourceContent>(), isEmpty);
    });

    test('citation 追加(E2E):char_location 命中响应内 fetched 文档', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_2',
          'name': 'web_fetch',
          'input': {'url': 'https://d.com/a.pdf'},
        },
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_2',
          'content': {
            'type': 'web_fetch_result',
            'url': 'https://d.com/a.pdf',
            'retrieved_at': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'Doc A',
              'citations': {'enabled': true},
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': 'JVBERi0=',
              },
            },
          },
        },
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'char_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': null,
              'start_char_index': 1,
              'end_char_index': 2,
            },
          ],
        },
      ]);
      // prompt 无 citation 文档:document_index 0 只能命中响应内 fetched 文档。
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final sources = result.content.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.document);
      expect(source.title, 'Doc A');
      expect(source.mediaType, 'application/pdf');
    });

    test('顺序:prompt 文档 index 0,响应内 fetched 文档 index 1', () async {
      final pdfPrompt = <LanguageModelMessage>[
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataUrl(Uri.parse('https://e.com/doc.pdf')),
            mediaType: 'application/pdf',
            filename: 'doc.pdf',
            providerOptions: const {
              'anthropic': {
                'citations': {'enabled': true},
              },
            },
          ),
          const TextPart('cite this'),
        ]),
      ];
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_2',
          'name': 'web_fetch',
          'input': {'url': 'https://d.com/a.pdf'},
        },
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_2',
          'content': {
            'type': 'web_fetch_result',
            'url': 'https://d.com/a.pdf',
            'retrieved_at': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'Doc A',
              'citations': {'enabled': true},
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': 'JVBERi0=',
              },
            },
          },
        },
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'char_location',
              'cited_text': 'prompt doc',
              'document_index': 0,
              'document_title': null,
              'start_char_index': 1,
              'end_char_index': 2,
            },
            {
              'type': 'char_location',
              'cited_text': 'fetched doc',
              'document_index': 1,
              'document_title': null,
              'start_char_index': 3,
              'end_char_index': 4,
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(prompt: pdfPrompt));

      final sources = result.content.whereType<SourceContent>().toList();
      expect(sources, hasLength(2));
      expect(sources[0].title, 'doc.pdf'); // prompt 文档,title 回退 filename
      expect(sources[0].filename, 'doc.pdf');
      expect(sources[1].title, 'Doc A'); // 响应内 fetched 文档
      expect(sources[1].filename, isNull);
    });

    test('错误 → ToolResult(isError: true) 不追加 citation 文档', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_2',
          'name': 'web_fetch',
          'input': {'url': 'https://d.com/a.pdf'},
        },
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': 'srvtoolu_2',
          'content': {
            'type': 'web_fetch_tool_result_error',
            'error_code': 'url_not_accessible',
          },
        },
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'char_location',
              'cited_text': 'quote',
              'document_index': 0,
              'document_title': null,
              'start_char_index': 1,
              'end_char_index': 2,
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, hasLength(3));
      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'web_fetch',
          result: {
            'type': 'web_fetch_tool_result_error',
            'errorCode': 'url_not_accessible',
          },
          isError: true,
        ),
      );
      // document_index 0 无匹配文档(未追加),citation 越界丢弃。
      expect(result.content.whereType<SourceContent>(), isEmpty);
    });

    test('web_search_result_location 非流式接通确认(共用 _createCitationSource)',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': {'query': 'dart'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'encrypted_content': 'enc1',
              'page_age': '1d',
            },
          ],
        },
        {
          'type': 'text',
          'text': 'answer',
          'citations': [
            {
              'type': 'web_search_result_location',
              'cited_text': 'quote',
              'url': 'https://r.com',
              'title': 'R',
              'encrypted_index': 'idx1',
            },
          ],
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      // ToolResult 自带的 source + citation 产出的 source,均为 url 类型。
      final sources = result.content.whereType<SourceContent>().toList();
      expect(sources, hasLength(2));
      for (final source in sources) {
        expect(source.sourceType, SourceType.url);
      }
      expect(sources.last.providerMetadata, {
        'anthropic': {'citedText': 'quote', 'encryptedIndex': 'idx1'},
      });
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate code_execution_tool_result',
      () {
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test(
        'code_execution_result 成功 → return_code 保留 snake_case'
        '(D5②,报告 09 §3.3 :1216-1228)', () async {
      final client = clientWith([
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_1',
          'content': {
            'type': 'code_execution_result',
            'stdout': 'hi\n',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'code_execution',
          result: {
            'type': 'code_execution_result',
            'stdout': 'hi\n',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        ),
      ]);
      expect((result.content.single as ToolResult).isError, isNull);
    });

    test(
        'code_execution_result 缺省 content 键 → 默认 []('
        '报告 09 §1.1 optional().default([]))', () async {
      final client = clientWith([
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_1b',
          'content': {
            'type': 'code_execution_result',
            'stdout': '',
            'stderr': '',
            'return_code': 0,
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        (result.content.single as ToolResult).result,
        const {
          'type': 'code_execution_result',
          'stdout': '',
          'stderr': '',
          'return_code': 0,
          'content': <Object?>[],
        },
      );
    });

    test(
        'encrypted_code_execution_result(20260120)→ encrypted_stdout 保留 '
        'snake_case(报告 09 §1.3 :108-119)', () async {
      final client = clientWith([
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_2',
          'content': {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-abc',
            'stderr': '',
            'return_code': 0,
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'code_execution',
          result: {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-abc',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        ),
      ]);
    });

    test(
        'code_execution_tool_result_error → isError:true + errorCode(camel'
        ',与 return_code 的 snake 处理不对称,报告 09 §9.2)', () async {
      final client = clientWith([
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_3',
          'content': {
            'type': 'code_execution_tool_result_error',
            'error_code': 'unavailable',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_3',
          toolName: 'code_execution',
          result: {
            'type': 'code_execution_tool_result_error',
            'errorCode': 'unavailable',
          },
          isError: true,
        ),
      ]);
    });

    test(
        'bash_code_execution_tool_result 成功 → content 原样透传、toolName '
        '归一 code_execution(报告 09 §3.4 :1258-1267)', () async {
      final client = clientWith([
        {
          'type': 'bash_code_execution_tool_result',
          'tool_use_id': 'srvtoolu_4',
          'content': {
            'type': 'bash_code_execution_result',
            'stdout': '1 1 2 3 5\n',
            'stderr': '',
            'return_code': 0,
            'content': [
              {'type': 'bash_code_execution_output', 'file_id': 'file_1'},
            ],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_4',
          toolName: 'code_execution',
          result: {
            'type': 'bash_code_execution_result',
            'stdout': '1 1 2 3 5\n',
            'stderr': '',
            'return_code': 0,
            'content': [
              {'type': 'bash_code_execution_output', 'file_id': 'file_1'},
            ],
          },
        ),
      ]);
      expect((result.content.single as ToolResult).isError, isNull);
    });

    test(
        'bash_code_execution_tool_result 错误变体 → 原样透传、**不标 '
        'isError**(与 code_execution_tool_result_error 不一致,上游刻意'
        '如此,报告 09 §9.1,D5 verbatim 照抄——spec §3.4 初稿在此处写反已'
        '修订)', () async {
      final client = clientWith([
        {
          'type': 'bash_code_execution_tool_result',
          'tool_use_id': 'srvtoolu_5',
          'content': {
            'type': 'bash_code_execution_tool_result_error',
            'error_code': 'unavailable',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_5',
          toolName: 'code_execution',
          result: {
            'type': 'bash_code_execution_tool_result_error',
            'error_code': 'unavailable',
          },
        ),
      ]);
      expect((result.content.single as ToolResult).isError, isNull);
    });

    test(
        'text_editor_code_execution_tool_result 成功(view)→ content 原样'
        '透传', () async {
      final client = clientWith([
        {
          'type': 'text_editor_code_execution_tool_result',
          'tool_use_id': 'srvtoolu_6',
          'content': {
            'type': 'text_editor_code_execution_view_result',
            'content': 'print(1)\n',
            'file_type': 'text',
            'num_lines': 1,
            'start_line': 1,
            'total_lines': 1,
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_6',
          toolName: 'code_execution',
          result: {
            'type': 'text_editor_code_execution_view_result',
            'content': 'print(1)\n',
            'file_type': 'text',
            'num_lines': 1,
            'start_line': 1,
            'total_lines': 1,
          },
        ),
      ]);
    });

    test(
        'text_editor_code_execution_tool_result 错误变体 → 原样透传、不标 '
        'isError', () async {
      final client = clientWith([
        {
          'type': 'text_editor_code_execution_tool_result',
          'tool_use_id': 'srvtoolu_7',
          'content': {
            'type': 'text_editor_code_execution_tool_result_error',
            'error_code': 'file_not_found',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_7',
          toolName: 'code_execution',
          result: {
            'type': 'text_editor_code_execution_tool_result_error',
            'error_code': 'file_not_found',
          },
        ),
      ]);
      expect((result.content.single as ToolResult).isError, isNull);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate tool_search_tool_result',
      () {
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test(
        '同响应内有配对 server_tool_use(regex)→ 定名取该名,tool_name 转 '
        'toolName(报告 09 §3.5 :1290-1299)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_8',
          'name': 'tool_search_tool_regex',
          'input': {'pattern': 'weather'},
        },
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_8',
          'content': {
            'type': 'tool_search_tool_search_result',
            'tool_references': [
              {'type': 'tool_reference', 'tool_name': 'get_temp_data'},
            ],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_8',
          toolName: 'tool_search_tool_regex',
          result: [
            {'type': 'tool_reference', 'toolName': 'get_temp_data'},
          ],
        ),
      );
    });

    test('同响应内有配对 server_tool_use(bm25)→ 定名取 bm25', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_9',
          'name': 'tool_search_tool_bm25',
          'input': {'query': 'weather forecast'},
        },
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_9',
          'content': {
            'type': 'tool_search_tool_search_result',
            'tool_references': [
              {'type': 'tool_reference', 'tool_name': 'get_weather'},
            ],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        (result.content[1] as ToolResult).toolName,
        'tool_search_tool_bm25',
      );
    });

    test(
        'deferred 定名 fallback:结果块无配对调用(跨响应到达)→ 恒落 '
        'tool_search_tool_regex,即便原调用是 bm25(报告 09 §9.9,pigcode '
        '「key=wire name」前提下上游别名判据恒失败)', () async {
      final client = clientWith([
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_deferred',
          'content': {
            'type': 'tool_search_tool_search_result',
            'tool_references': [
              {'type': 'tool_reference', 'tool_name': 'get_weather'},
            ],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        (result.content.single as ToolResult).toolName,
        'tool_search_tool_regex',
      );
    });

    test('tool_search_tool_result_error → isError:true + errorCode', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_10',
          'name': 'tool_search_tool_regex',
          'input': {'pattern': 'x'},
        },
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_10',
          'content': {
            'type': 'tool_search_tool_result_error',
            'error_code': 'unavailable',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'srvtoolu_10',
          toolName: 'tool_search_tool_regex',
          result: {
            'type': 'tool_search_tool_result_error',
            'errorCode': 'unavailable',
          },
          isError: true,
        ),
      );
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate advisor_tool_result', () {
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test('advisor_result → text 透传', () async {
      final client = clientWith([
        {
          'type': 'advisor_tool_result',
          'tool_use_id': 'srvtoolu_11',
          'content': {
            'type': 'advisor_result',
            'text': 'Based on the data, revenue grew 12%.',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_11',
          toolName: 'advisor',
          result: {
            'type': 'advisor_result',
            'text': 'Based on the data, revenue grew 12%.',
          },
        ),
      ]);
    });

    test(
        'advisor_redacted_result → encrypted_content 转 encryptedContent'
        '(须原样回传供服务端解密,报告 09 §3.6 :1328-1337)', () async {
      final client = clientWith([
        {
          'type': 'advisor_tool_result',
          'tool_use_id': 'srvtoolu_12',
          'content': {
            'type': 'advisor_redacted_result',
            'encrypted_content': 'opaque-encrypted-blob-xyz',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_12',
          toolName: 'advisor',
          result: {
            'type': 'advisor_redacted_result',
            'encryptedContent': 'opaque-encrypted-blob-xyz',
          },
        ),
      ]);
    });

    test('advisor_tool_result_error → isError:true + errorCode', () async {
      final client = clientWith([
        {
          'type': 'advisor_tool_result',
          'tool_use_id': 'srvtoolu_13',
          'content': {
            'type': 'advisor_tool_result_error',
            'error_code': 'max_uses_exceeded',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(result.content, const [
        ToolResult(
          toolCallId: 'srvtoolu_13',
          toolName: 'advisor',
          result: {
            'type': 'advisor_tool_result_error',
            'errorCode': 'max_uses_exceeded',
          },
          isError: true,
        ),
      ]);
    });
  });

  group('AnthropicMessagesLanguageModel.doGenerate providerMetadata', () {
    /// 以给定 wire 响应跑一次 doGenerate,返回 providerMetadata 全量 map。
    Future<Map<String, Map<String, Object?>>> run(
      Map<String, Object?> wire, {
      String providerName = 'anthropic.messages',
      Map<String, Map<String, Object?>>? providerOptions,
    }) async {
      final client =
          _RecordingClient((request) async => _jsonResponse(jsonEncode(wire)));
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: AnthropicConfig(
          providerName: providerName,
          baseUrl: 'https://api.anthropic.com/v1',
          headers: () => const {'x-api-key': 'test-key'},
          client: client,
        ),
      ).doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        providerOptions: providerOptions,
      ));
      return result.providerMetadata!;
    }

    /// 最小 wire 响应模板,按需覆盖 usage 与追加顶层字段。
    Map<String, Object?> wire({
      Map<String, Object?> usage = const {
        'input_tokens': 5,
        'output_tokens': 2,
      },
      Map<String, Object?> extra = const {},
    }) {
      return {
        'type': 'message',
        'id': 'msg_1',
        'model': 'claude-sonnet-4-5',
        'content': [
          {'type': 'text', 'text': 'hi'},
        ],
        'stop_reason': 'end_turn',
        'usage': usage,
        ...extra,
      };
    }

    test('usage 原样透传(snake_case 含 cache_* 键,断言 1)', () async {
      const usage = <String, Object?>{
        'input_tokens': 5,
        'output_tokens': 2,
        'cache_creation_input_tokens': 3,
        'cache_read_input_tokens': 7,
      };
      final metadata = (await run(wire(usage: usage)))['anthropic']!;
      expect(metadata['usage'], usage);
    });

    test('stopSequence:非 null 透传 / null 与缺失均为存在的 null 键(断言 2)', () async {
      final withValue = (await run(
        wire(extra: {'stop_sequence': 'END'}),
      ))['anthropic']!;
      expect(withValue['stopSequence'], 'END');

      final withNull = (await run(
        wire(extra: {'stop_sequence': null}),
      ))['anthropic']!;
      expect(withNull.containsKey('stopSequence'), isTrue);
      expect(withNull['stopSequence'], isNull);

      final missing = (await run(wire()))['anthropic']!;
      expect(missing.containsKey('stopSequence'), isTrue);
      expect(missing['stopSequence'], isNull);
    });

    test('stopDetails:缺失无键 / 非 null 字段才携带 + recommendedModel 改名(断言 3)',
        () async {
      final missing = (await run(wire()))['anthropic']!;
      expect(missing.containsKey('stopDetails'), isFalse);

      final present = (await run(wire(extra: {
        'stop_details': {
          'type': 'refusal',
          'category': 'safety',
          'explanation': null,
          'recommended_model': 'claude-x',
        },
      })))['anthropic']!;
      expect(present['stopDetails'], {
        'type': 'refusal',
        'category': 'safety',
        'recommendedModel': 'claude-x',
      });
    });

    test('iterations camelCase:cache 0 省略、model null 省略、无则显式 null(断言 4)',
        () async {
      final metadata = (await run(wire(usage: {
        'input_tokens': 5,
        'output_tokens': 2,
        'iterations': [
          {
            'type': 'message',
            'model': 'claude-sonnet-4-5',
            'input_tokens': 4,
            'output_tokens': 6,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 8,
          },
          {
            'type': 'advisor_message',
            'model': null,
            'input_tokens': 1,
            'output_tokens': 1,
          },
        ],
      })))['anthropic']!;
      expect(metadata['iterations'], [
        {
          'type': 'message',
          'model': 'claude-sonnet-4-5',
          'inputTokens': 4,
          'outputTokens': 6,
          'cacheReadInputTokens': 8,
        },
        {
          'type': 'advisor_message',
          'inputTokens': 1,
          'outputTokens': 1,
        },
      ]);

      final none = (await run(wire()))['anthropic']!;
      expect(none.containsKey('iterations'), isTrue);
      expect(none['iterations'], isNull);
    });

    test('container 透传:skills camelCase / skills null 保留 / 无则 null(断言 5)',
        () async {
      final present = (await run(wire(extra: {
        'container': {
          'expires_at': '2026-07-08T00:00:00Z',
          'id': 'cont_1',
          'skills': [
            {'type': 'anthropic', 'skill_id': 'sk_1', 'version': '1'},
          ],
        },
      })))['anthropic']!;
      expect(present['container'], {
        'expiresAt': '2026-07-08T00:00:00Z',
        'id': 'cont_1',
        'skills': [
          {'type': 'anthropic', 'skillId': 'sk_1', 'version': '1'},
        ],
      });

      final nullSkills = (await run(wire(extra: {
        'container': {
          'expires_at': '2026-07-08T00:00:00Z',
          'id': 'cont_2',
          'skills': null,
        },
      })))['anthropic']!;
      expect(nullSkills['container'], {
        'expiresAt': '2026-07-08T00:00:00Z',
        'id': 'cont_2',
        'skills': null,
      });

      final none = (await run(wire()))['anthropic']!;
      expect(none.containsKey('container'), isTrue);
      expect(none['container'], isNull);
    });

    test('contextManagement 透传:三种 edit 各自 camelCase / 无则 null(断言 6)', () async {
      final present = (await run(wire(extra: {
        'context_management': {
          'applied_edits': [
            {
              'type': 'clear_tool_uses_20250919',
              'cleared_tool_uses': 3,
              'cleared_input_tokens': 100,
            },
            {
              'type': 'clear_thinking_20251015',
              'cleared_thinking_turns': 2,
              'cleared_input_tokens': 50,
            },
            {'type': 'compact_20260112'},
          ],
        },
      })))['anthropic']!;
      expect(present['contextManagement'], {
        'appliedEdits': [
          {
            'type': 'clear_tool_uses_20250919',
            'clearedToolUses': 3,
            'clearedInputTokens': 100,
          },
          {
            'type': 'clear_thinking_20251015',
            'clearedThinkingTurns': 2,
            'clearedInputTokens': 50,
          },
          {'type': 'compact_20260112'},
        ],
      });

      final none = (await run(wire()))['anthropic']!;
      expect(none.containsKey('contextManagement'), isTrue);
      expect(none['contextManagement'], isNull);
    });

    test('双 key 同挂:自定义 provider key 有值时 anthropic 与自定义 key 值相等(断言 7)',
        () async {
      final metadata = await run(
        wire(extra: {'stop_sequence': 'END'}),
        providerName: 'my-anthropic',
        providerOptions: {
          'my-anthropic': {'sendReasoning': true},
        },
      );
      expect(metadata.keys, containsAll(['anthropic', 'my-anthropic']));
      expect(metadata['my-anthropic'], metadata['anthropic']);
      expect(metadata['anthropic']!['stopSequence'], 'END');
    });

    test('usedCustomProviderKey=false 时仅挂 anthropic 单 key(断言 7)', () async {
      // 自定义 providerName 但 providerOptions 未走自定义 key。
      final custom = await run(
        wire(),
        providerName: 'my-anthropic',
        providerOptions: {
          'anthropic': {'sendReasoning': true},
        },
      );
      expect(custom.keys.toList(), ['anthropic']);

      // 缺省 providerName(派生 key == 'anthropic')。
      final canonical = await run(wire());
      expect(canonical.keys.toList(), ['anthropic']);
    });
  });

  group('批次三工具全链路 — doGenerate(报告 09 §7.1)', () {
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    test(
        'code_execution(programmatic)全链:server_tool_use + '
        'code_execution_tool_result(encrypted)', () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_ce1',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_ce1',
          'content': {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-blob',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final call = result.content.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_ce1');
      expect(call.toolName, 'code_execution');
      expect(call.providerExecuted, isTrue);
      expect(
        jsonDecode(call.input),
        {'type': 'programmatic-tool-call', 'code': 'print(1)'},
      );

      final toolResult = result.content.whereType<ToolResult>().single;
      expect(
        toolResult,
        const ToolResult(
          toolCallId: 'srvtoolu_ce1',
          toolName: 'code_execution',
          result: {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-blob',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        ),
      );
    });

    test('tool_search(bm25)全链:server_tool_use + tool_search_tool_result',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_ts1',
          'name': 'tool_search_tool_bm25',
          'input': {'query': 'weather forecast', 'limit': 5},
        },
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_ts1',
          'content': {
            'type': 'tool_search_tool_search_result',
            'tool_references': [
              {'type': 'tool_reference', 'tool_name': 'get_weather'},
            ],
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final call = result.content.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_ts1');
      expect(call.toolName, 'tool_search_tool_bm25');
      expect(call.providerExecuted, isTrue);
      expect(
        jsonDecode(call.input),
        {'query': 'weather forecast', 'limit': 5},
      );

      final toolResult = result.content.whereType<ToolResult>().single;
      expect(toolResult.toolCallId, 'srvtoolu_ts1');
      expect(toolResult.toolName, 'tool_search_tool_bm25');
      expect(toolResult.isError, isNull);
      expect(
        toolResult.result,
        [
          {'type': 'tool_reference', 'toolName': 'get_weather'},
        ],
      );
    });

    test('advisor 全链:server_tool_use(input {}) + advisor_tool_result',
        () async {
      final client = clientWith([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_adv1',
          'name': 'advisor',
          'input': <String, Object?>{},
        },
        {
          'type': 'advisor_tool_result',
          'tool_use_id': 'srvtoolu_adv1',
          'content': {
            'type': 'advisor_result',
            'text': 'Recommend using a HashMap for O(1) lookups.',
          },
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final call = result.content.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_adv1');
      expect(call.toolName, 'advisor');
      expect(call.providerExecuted, isTrue);
      expect(jsonDecode(call.input), <String, Object?>{});

      final toolResult = result.content.whereType<ToolResult>().single;
      expect(
        toolResult,
        const ToolResult(
          toolCallId: 'srvtoolu_adv1',
          toolName: 'advisor',
          result: {
            'type': 'advisor_result',
            'text': 'Recommend using a HashMap for O(1) lookups.',
          },
        ),
      );
    });

    test(
        'memory 全链:普通 tool_use,无 providerExecuted(报告 09 §7.1 仅 '
        'json fixture)', () async {
      final client = clientWith([
        {
          'type': 'tool_use',
          'id': 'tu_mem1',
          'name': 'memory',
          'input': {'command': 'view', 'path': '/memories'},
        },
      ]);
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      final call = result.content.whereType<ToolCall>().single;
      expect(call.toolCallId, 'tu_mem1');
      expect(call.toolName, 'memory');
      // 普通 tool_use 无 providerExecuted(报告 08 §4.2,批次 2 已验证结论
      // 对 memory 同样成立)。
      expect(call.providerExecuted, isNull);
      expect(
        jsonDecode(call.input),
        {'command': 'view', 'path': '/memories'},
      );
    });
  });

  group('批次三工具全链路 — convert 往返(doGenerate 解析产物直接回放)', () {
    Future<LanguageModelGenerateResult> generateResult(
      List<Map<String, Object?>> content,
    ) {
      final body = jsonEncode({
        'type': 'message',
        'id': 'msg_1',
        'model': 'claude-sonnet-4-5',
        'content': content,
        'stop_reason': 'end_turn',
        'stop_sequence': null,
        'usage': {'input_tokens': 5, 'output_tokens': 2},
      });
      final client = _RecordingClient(
        (request) async => _jsonResponse(body),
      );
      return AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));
    }

    test(
        'code_execution:解码产物回放还原 server_tool_use(剥离虚构 type)+ '
        'code_execution_tool_result', () async {
      final generated = await generateResult([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_ce3',
          'name': 'code_execution',
          'input': {'code': 'print(1)'},
        },
        {
          'type': 'code_execution_tool_result',
          'tool_use_id': 'srvtoolu_ce3',
          'content': {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-blob',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        },
      ]);
      final call = generated.content.whereType<ToolCall>().single;
      final toolResult = generated.content.whereType<ToolResult>().single;

      final replayed = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              input: jsonDecode(call.input) as Map<String, Object?>,
              providerExecuted: call.providerExecuted,
            ),
            ToolResultPart(
              toolCallId: toolResult.toolCallId,
              toolName: toolResult.toolName,
              output: ToolResultJson(toolResult.result),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (replayed.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();

      final callBlock =
          content.singleWhere((b) => b['type'] == 'server_tool_use');
      // programmatic-tool-call 的虚构 type 已剥离,还原为原始 wire 调用形态。
      expect(callBlock, {
        'type': 'server_tool_use',
        'id': 'srvtoolu_ce3',
        'name': 'code_execution',
        'input': {'code': 'print(1)'},
      });

      final resultBlock =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(resultBlock, {
        'type': 'code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce3',
        'content': {
          'type': 'encrypted_code_execution_result',
          'encrypted_stdout': 'enc-blob',
          'stderr': '',
          'return_code': 0,
          'content': <Object?>[],
        },
      });
    });

    test('tool_search:解码产物回放还原(裸数组重新套壳)', () async {
      final generated = await generateResult([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_ts3',
          'name': 'tool_search_tool_bm25',
          'input': {'query': 'weather forecast', 'limit': 5},
        },
        {
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_ts3',
          'content': {
            'type': 'tool_search_tool_search_result',
            'tool_references': [
              {'type': 'tool_reference', 'tool_name': 'get_weather'},
            ],
          },
        },
      ]);
      final call = generated.content.whereType<ToolCall>().single;
      final toolResult = generated.content.whereType<ToolResult>().single;

      final replayed = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              input: jsonDecode(call.input) as Map<String, Object?>,
              providerExecuted: call.providerExecuted,
            ),
            ToolResultPart(
              toolCallId: toolResult.toolCallId,
              toolName: toolResult.toolName,
              output: ToolResultJson(toolResult.result),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (replayed.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();

      final callBlock =
          content.singleWhere((b) => b['type'] == 'server_tool_use');
      expect(callBlock, {
        'type': 'server_tool_use',
        'id': 'srvtoolu_ts3',
        'name': 'tool_search_tool_bm25',
        'input': {'query': 'weather forecast', 'limit': 5},
      });

      final resultBlock =
          content.singleWhere((b) => b['type'] == 'tool_search_tool_result');
      expect(resultBlock, {
        'type': 'tool_search_tool_result',
        'tool_use_id': 'srvtoolu_ts3',
        'content': {
          'type': 'tool_search_tool_search_result',
          'tool_references': [
            {'type': 'tool_reference', 'tool_name': 'get_weather'},
          ],
        },
      });
    });

    test(
        'advisor:解码产物回放,input 恒 {}(即使原始调用 input 也是 {}, '
        '无额外信息损失可观测)', () async {
      final generated = await generateResult([
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_adv3',
          'name': 'advisor',
          'input': <String, Object?>{},
        },
        {
          'type': 'advisor_tool_result',
          'tool_use_id': 'srvtoolu_adv3',
          'content': {
            'type': 'advisor_redacted_result',
            'encrypted_content': 'opaque-encrypted-blob-xyz',
          },
        },
      ]);
      final call = generated.content.whereType<ToolCall>().single;
      final toolResult = generated.content.whereType<ToolResult>().single;

      final replayed = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              input: jsonDecode(call.input) as Map<String, Object?>,
              providerExecuted: call.providerExecuted,
            ),
            ToolResultPart(
              toolCallId: toolResult.toolCallId,
              toolName: toolResult.toolName,
              output: ToolResultJson(toolResult.result),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (replayed.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();

      final callBlock =
          content.singleWhere((b) => b['type'] == 'server_tool_use');
      expect(callBlock, {
        'type': 'server_tool_use',
        'id': 'srvtoolu_adv3',
        'name': 'advisor',
        'input': <String, Object?>{},
      });

      final resultBlock =
          content.singleWhere((b) => b['type'] == 'advisor_tool_result');
      // encrypted_content 原样 verbatim 往返(报告 09 §7.4 :2610-2658)。
      expect(resultBlock, {
        'type': 'advisor_tool_result',
        'tool_use_id': 'srvtoolu_adv3',
        'content': {
          'type': 'advisor_redacted_result',
          'encrypted_content': 'opaque-encrypted-blob-xyz',
        },
      });
    });

    test('memory:普通 tool_use/tool_result 通道回放不受批次三改动影响(回归)', () async {
      // memory 零解析改动(spec §3.3);本用例确认 Task 11/12 的重构没有
      // 意外影响既有普通通道。
      final generated = await generateResult([
        {
          'type': 'tool_use',
          'id': 'tu_mem3',
          'name': 'memory',
          'input': {'command': 'view', 'path': '/memories'},
        },
      ]);
      final call = generated.content.whereType<ToolCall>().single;
      expect(call.providerExecuted, isNull);

      final replayed = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              input: jsonDecode(call.input) as Map<String, Object?>,
              providerExecuted: call.providerExecuted,
            ),
          ]),
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'tu_mem3',
              toolName: 'memory',
              output: ToolResultText('Directory listing: memories.md, notes/'),
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final assistantContent =
          (replayed.messages.first['content'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(assistantContent.single, {
        'type': 'tool_use',
        'id': 'tu_mem3',
        'name': 'memory',
        'input': {'command': 'view', 'path': '/memories'},
      });

      final userContent = (replayed.messages.last['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(userContent.single, {
        'type': 'tool_result',
        'tool_use_id': 'tu_mem3',
        'content': 'Directory listing: memories.md, notes/',
      });
    });
  });

  group('beta 选项族请求侧 ①:taskBudget/speed/fallbacks(T9)', () {
    test('taskBudget 全字段:output_config.task_budget 与 effort 并列 + beta',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'effort': 'high',
              'taskBudget': {
                'type': 'tokens',
                'total': 30000,
                'remaining': 5000,
              },
            },
          },
        ),
      );

      expect(client.lastBody!['output_config'], {
        'effort': 'high',
        'task_budget': {'type': 'tokens', 'total': 30000, 'remaining': 5000},
      });
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('task-budgets-2026-03-13'));
    });

    test('taskBudget 单独存在:output_config 仍发送且 remaining 缺席不写键', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'taskBudget': {'type': 'tokens', 'total': 20000},
            },
          },
        ),
      );

      expect(client.lastBody!['output_config'], {
        'task_budget': {'type': 'tokens', 'total': 20000},
      });
    });

    test("speed 'fast':发顶层键 + fast-mode beta", () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'speed': 'fast'},
          },
        ),
      );

      expect(client.lastBody!['speed'], 'fast');
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('fast-mode-2026-02-01'));
    });

    test("speed 'standard':发顶层键、不加任何 beta", () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'speed': 'standard'},
          },
        ),
      );

      expect(client.lastBody!['speed'], 'standard');
      // 无其他 beta 来源时整个 anthropic-beta 头都不发。
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });

    test('fallbacks 非空:顶层原样透传 + server-side-fallback beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'fallbacks': [
                {
                  'model': 'claude-opus-4-6',
                  'max_tokens': 2048,
                  'thinking': {'type': 'disabled'},
                  'output_config': {'effort': 'low'},
                  'speed': 'fast',
                },
              ],
            },
          },
        ),
      );

      expect(client.lastBody!['fallbacks'], [
        {
          'model': 'claude-opus-4-6',
          'max_tokens': 2048,
          'thinking': {'type': 'disabled'},
          'output_config': {'effort': 'low'},
          'speed': 'fast',
        },
      ]);
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('server-side-fallback-2026-06-01'));
      expect(betas, contains('fast-mode-2026-02-01'));
    });

    test("fallback speed 'standard':只加 server-side-fallback beta", () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'fallbacks': [
                {'model': 'claude-opus-4-6', 'speed': 'standard'},
              ],
            },
          },
        ),
      );

      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('server-side-fallback-2026-06-01'));
      expect(betas, isNot(contains('fast-mode-2026-02-01')));
    });

    test('fallbacks 空数组:不发键、不加 beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'fallbacks': <Object?>[]},
          },
        ),
      );

      expect(client.lastBody!.containsKey('fallbacks'), isFalse);
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });

    test('未设置选项族字段:speed/fallbacks/output_config 键均缺席(回归)', () async {
      final client = _minimalClient();
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

      expect(client.lastBody!.containsKey('speed'), isFalse);
      expect(client.lastBody!.containsKey('fallbacks'), isFalse);
      expect(client.lastBody!.containsKey('output_config'), isFalse);
    });
  });

  group('beta 选项族请求侧 ②:mcpServers/container/contextManagement(T10)', () {
    test('mcp_servers 全键 snake 化 + mcp-client beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'mcpServers': [
                {
                  'type': 'url',
                  'name': 'echo',
                  'url': 'https://mcp.example.com',
                  'authorizationToken': 'token-1',
                  'toolConfiguration': {
                    'enabled': false,
                    'allowedTools': ['echo_tool'],
                  },
                },
              ],
            },
          },
        ),
      );

      expect(client.lastBody!['mcp_servers'], [
        {
          'type': 'url',
          'name': 'echo',
          'url': 'https://mcp.example.com',
          'authorization_token': 'token-1',
          'tool_configuration': {
            'allowed_tools': ['echo_tool'],
            'enabled': false,
          },
        },
      ]);
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('mcp-client-2025-04-04'));
    });

    test('mcp_servers 可选键缺席不写(缺席键统一,含显式 null 不写)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'mcpServers': [
                {
                  'type': 'url',
                  'name': 'minimal',
                  'url': 'https://mcp2.example.com',
                  'authorizationToken': null,
                },
              ],
            },
          },
        ),
      );

      expect(client.lastBody!['mcp_servers'], [
        {'type': 'url', 'name': 'minimal', 'url': 'https://mcp2.example.com'},
      ]);
    });

    test('mcpServers 空数组:不发键、不加 beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'mcpServers': <Object?>[]},
          },
        ),
      );

      expect(client.lastBody!.containsKey('mcp_servers'), isFalse);
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });

    test('container 空对象:不写 container 键(空边界)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {'container': <String, Object?>{}},
          },
        ),
      );

      expect(client.lastBody!.containsKey('container'), isFalse);
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });

    test('container 仅空 skills:同样不写 container 键', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {'skills': <Object?>[]},
            },
          },
        ),
      );

      expect(client.lastBody!.containsKey('container'), isFalse);
    });

    test('container 纯 id:字符串形态、无 skills beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {'id': 'container_abc'},
            },
          },
        ),
      );

      expect(client.lastBody!['container'], 'container_abc');
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });

    test('container skills adds current skills and files betas', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx'},
                ],
              },
            },
          },
        ),
      );

      expect(client.lastBody!['container'], {
        'skills': [
          {'type': 'anthropic', 'skill_id': 'pptx'},
        ],
      });
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, {'skills-2025-10-02', 'files-api-2025-04-14'});
    });

    test('container id + skills:对象形态含 id 与 version', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {
                'id': 'container_abc',
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx', 'version': 'latest'},
                ],
              },
            },
          },
        ),
      );

      expect(client.lastBody!['container'], {
        'id': 'container_abc',
        'skills': [
          {'type': 'anthropic', 'skill_id': 'pptx', 'version': 'latest'},
        ],
      });
    });

    test('custom skill:providerReference 解析进 skill_id(正向)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {
                'skills': [
                  {
                    'type': 'custom',
                    'providerReference': {'anthropic': 'skill_01X'},
                  },
                ],
              },
            },
          },
        ),
      );

      expect(client.lastBody!['container'], {
        'skills': [
          {'type': 'custom', 'skill_id': 'skill_01X'},
        ],
      });
    });

    test('custom skill 缺 anthropic 键:抛 NoSuchProviderReferenceError', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await expectLater(
        model.doGenerate(
          const LanguageModelCallOptions(
            prompt: _prompt,
            providerOptions: {
              'anthropic': {
                'container': {
                  'skills': [
                    {
                      'type': 'custom',
                      'providerReference': {'openai': 'skill_abc'},
                    },
                  ],
                },
              },
            },
          ),
        ),
        throwsA(isA<NoSuchProviderReferenceError>()),
      );
    });

    test('skills warning:无 code_execution 工具时发 warning', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'container': {
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx'},
                ],
              },
            },
          },
        ),
      );

      expect(
        result.warnings,
        contains(const OtherWarning(
          'code execution tool is required when using skills',
        )),
      );
    });

    test('skills warning:带 codeExecution_20250825 时无 warning', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: _prompt,
          tools: [codeExecution_20250825()],
          providerOptions: const {
            'anthropic': {
              'container': {
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx'},
                ],
              },
            },
          },
        ),
      );

      expect(
        result.warnings,
        isNot(contains(const OtherWarning(
          'code execution tool is required when using skills',
        ))),
      );
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('code-execution-2025-08-25'));
    });

    test('skills with codeExecution_20260120 adds no legacy beta or warning',
        () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: _prompt,
          tools: [codeExecution_20260120()],
          providerOptions: const {
            'anthropic': {
              'container': {
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx'},
                ],
              },
            },
          },
        ),
      );

      expect(
        result.warnings,
        isNot(contains(const OtherWarning(
          'code execution tool is required when using skills',
        ))),
      );
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, {'skills-2025-10-02', 'files-api-2025-04-14'});
    });

    test('skills warning:仅带 20250522 时仍发 warning(白名单只认两高版)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: _prompt,
          tools: [codeExecution_20250522()],
          providerOptions: const {
            'anthropic': {
              'container': {
                'skills': [
                  {'type': 'anthropic', 'skillId': 'pptx'},
                ],
              },
            },
          },
        ),
      );

      expect(
        result.warnings,
        contains(const OtherWarning(
          'code execution tool is required when using skills',
        )),
      );
    });

    test('contextManagement 三 edit 型 camel→snake 编码 + 双 beta', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'contextManagement': {
                'edits': [
                  {
                    'type': 'clear_tool_uses_20250919',
                    'trigger': {'type': 'input_tokens', 'value': 30000},
                    'keep': {'type': 'tool_uses', 'value': 3},
                    'clearAtLeast': {'type': 'input_tokens', 'value': 5000},
                    'clearToolInputs': true,
                    'excludeTools': ['web_search'],
                  },
                  {'type': 'clear_thinking_20251015', 'keep': 'all'},
                  {
                    'type': 'compact_20260112',
                    'trigger': {'type': 'input_tokens', 'value': 100000},
                    'pauseAfterCompaction': true,
                    'instructions': 'keep the summary short',
                  },
                ],
              },
            },
          },
        ),
      );

      expect(client.lastBody!['context_management'], {
        'edits': [
          {
            'type': 'clear_tool_uses_20250919',
            'trigger': {'type': 'input_tokens', 'value': 30000},
            'keep': {'type': 'tool_uses', 'value': 3},
            'clear_at_least': {'type': 'input_tokens', 'value': 5000},
            'clear_tool_inputs': true,
            'exclude_tools': ['web_search'],
          },
          {'type': 'clear_thinking_20251015', 'keep': 'all'},
          {
            'type': 'compact_20260112',
            'trigger': {'type': 'input_tokens', 'value': 100000},
            'pause_after_compaction': true,
            'instructions': 'keep the summary short',
          },
        ],
      });
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('context-management-2025-06-27'));
      expect(betas, contains('compact-2026-01-12'));
    });

    test('contextManagement 最小 edit:可选键全部缺席不写', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'contextManagement': {
                'edits': [
                  {'type': 'clear_tool_uses_20250919'},
                ],
              },
            },
          },
        ),
      );

      expect(client.lastBody!['context_management'], {
        'edits': [
          {'type': 'clear_tool_uses_20250919'},
        ],
      });
    });

    test('contextManagement 空 edits:照发 + beta(无 compact 不叠加)', () async {
      final client = _minimalClient();
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: _prompt,
          providerOptions: {
            'anthropic': {
              'contextManagement': {'edits': <Object?>[]},
            },
          },
        ),
      );

      expect(client.lastBody!['context_management'], {'edits': <Object?>[]});
      final betas = anthropicBetasFromHeaderValue(
        client.lastRequest!.headers['anthropic-beta'],
      );
      expect(betas, contains('context-management-2025-06-27'));
      expect(betas, isNot(contains('compact-2026-01-12')));
    });
  });

  group(
      'AnthropicMessagesLanguageModel.doGenerate 三族新块(mcp/compaction/fallback)',
      () {
    /// 用给定 content 数组构造完整 wire 响应体(同 server_tool_use group 模式)。
    String responseWith(List<Map<String, Object?>> content) => jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': content,
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        });

    _RecordingClient clientWith(List<Map<String, Object?>> content) =>
        _RecordingClient(
            (request) async => _jsonResponse(responseWith(content)));

    Future<LanguageModelGenerateResult> generateWith(
      List<Map<String, Object?>> content,
    ) =>
        AnthropicMessagesLanguageModel(
          'claude-sonnet-4-5',
          config: _config(clientWith(content)),
        ).doGenerate(const LanguageModelCallOptions(prompt: _prompt));

    test('mcp_tool_use → 契约 ToolCall(providerExecuted/isDynamic/metadata)',
        () async {
      final result = await generateWith([
        {
          'type': 'mcp_tool_use',
          'id': 'mcptoolu_1',
          'name': 'echo',
          'server_name': 'echo-server',
          'input': {'message': 'hello world'},
        },
      ]);

      expect(result.content, const [
        ToolCall(
          toolCallId: 'mcptoolu_1',
          toolName: 'echo',
          input: '{"message":"hello world"}',
          providerExecuted: true,
          isDynamic: true,
          providerMetadata: {
            'anthropic': {
              'type': 'mcp-tool-use',
              'serverName': 'echo-server',
            },
          },
        ),
      ]);
    });

    test('mcp_tool_result 配对:toolName/providerMetadata 取自同响应 mcp_tool_use',
        () async {
      final result = await generateWith([
        {
          'type': 'mcp_tool_use',
          'id': 'mcptoolu_1',
          'name': 'echo',
          'server_name': 'echo-server',
          'input': {'message': 'hello world'},
        },
        {
          'type': 'mcp_tool_result',
          'tool_use_id': 'mcptoolu_1',
          'is_error': true,
          'content': [
            {'type': 'text', 'text': 'Tool echo failed'},
          ],
        },
      ]);

      expect(result.content, hasLength(2));
      expect(
        result.content[1],
        const ToolResult(
          toolCallId: 'mcptoolu_1',
          toolName: 'echo',
          result: [
            {'type': 'text', 'text': 'Tool echo failed'},
          ],
          isError: true,
          isDynamic: true,
          providerMetadata: {
            'anthropic': {
              'type': 'mcp-tool-use',
              'serverName': 'echo-server',
            },
          },
        ),
      );
    });

    test('mcp_tool_result 无配对 → FormatException 受控错误(文案锁定)', () async {
      await expectLater(
        generateWith([
          {
            'type': 'mcp_tool_result',
            'tool_use_id': 'mcptoolu_9',
            'is_error': false,
            'content': <Object?>[],
          },
        ]),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          'mcp_tool_result block without matching mcp_tool_use: mcptoolu_9',
        )),
      );
    });

    test('compaction → TextContent(content 直取)+ compaction metadata', () async {
      final result = await generateWith([
        {'type': 'compaction', 'content': 'summary of earlier turns'},
        {'type': 'text', 'text': 'continuing'},
      ]);

      expect(result.content, const [
        TextContent(
          'summary of earlier turns',
          providerMetadata: {
            'anthropic': {'type': 'compaction'},
          },
        ),
        TextContent('continuing'),
      ]);
    });

    test('fallback 无产出,其余内容正常解析', () async {
      final result = await generateWith([
        {'type': 'fallback'},
        {'type': 'text', 'text': 'ok'},
      ]);

      expect(result.content, const [TextContent('ok')]);
    });
  });
}
