import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(String body, {int statusCode = 200}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

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

OpenAiCompatibleChatConfig _config(
  http.Client client, {
  bool supportsStructuredOutputs = false,
  ProviderErrorStructure? errorStructure,
  MetadataExtractor? metadataExtractor,
  JsonObject Function(JsonObject args)? transformRequestBody,
  LanguageModelUsage Function(JsonObject usage)? convertUsage,
}) {
  return OpenAiCompatibleChatConfig(
    providerName: 'mycustom',
    url: (path) => Uri.parse('https://api.mycustom.dev/v1$path'),
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
    supportsStructuredOutputs: supportsStructuredOutputs,
    errorStructure: errorStructure,
    metadataExtractor: metadataExtractor,
    transformRequestBody: transformRequestBody,
    convertUsage: convertUsage,
  );
}

/// 最简成功响应体(单 choice 文本消息)。
String _basicResponse({String content = 'ok'}) {
  return jsonEncode({
    'id': 'chatcmpl-1',
    'created': 1700000000,
    'model': 'my-model',
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
        'index': 0,
        'finish_reason': 'stop',
      },
    ],
  });
}

void main() {
  // Compatibility fixture (unit): P1-COMPAT-02
  group('OpenAiCompatibleChatLanguageModel.doGenerate', () {
    test('provider/modelId/请求 URL 与基础字段', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-1',
          'created': 1700000000,
          'model': 'my-model',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'hi there'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 5,
            'completion_tokens': 2,
            'total_tokens': 7,
          },
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      expect(model.provider, 'mycustom.chat');
      expect(model.modelId, 'my-model');
      expect(await model.supportedUrls, isEmpty);

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hello')]),
          ],
        ),
      );

      expect(client.lastRequest!.url.toString(),
          'https://api.mycustom.dev/v1/chat/completions');
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      expect(client.lastBody!['model'], 'my-model');
      expect(client.lastBody!['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(client.lastBody!.containsKey('stream'), isFalse);
      expect(client.lastBody!.containsKey('stream_options'), isFalse);

      expect(result.content, [const TextContent('hi there')]);
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.usage.inputTokens.total, 5);
      expect(result.usage.outputTokens.total, 2);
      expect(result.response?.id, 'chatcmpl-1');
      expect(result.response?.modelId, 'my-model');
    });

    test('tool_calls 响应映射,id 缺失时用 generateId 兜底', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2',
          'created': 1700000000,
          'model': 'my-model',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': null,
                    'type': 'function',
                    'function': {
                      'name': 'get_weather',
                      'arguments': '{"city":"sf"}',
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'tool_calls',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')]),
          ],
        ),
      );

      expect(result.content, hasLength(1));
      final toolCall = result.content.single as ToolCall;
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test(
        'tool_calls 带 extra_content.google.thought_signature 时回读进 '
        'ToolCall.providerMetadata', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2b',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'get_weather',
                      'arguments': '{"city":"sf"}',
                    },
                    'extra_content': {
                      'google': {'thought_signature': 'sig-abc'},
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'tool_calls',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')]),
          ],
        ),
      );

      final toolCall = result.content.single as ToolCall;
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-abc'},
      );
    });

    test('tool_calls 无 extra_content 时 ToolCall.providerMetadata 为 null',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2c',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'get_weather',
                      'arguments': '{"city":"sf"}',
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'tool_calls',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')]),
          ],
        ),
      );

      final toolCall = result.content.single as ToolCall;
      expect(toolCall.providerMetadata, isNull);
    });

    test(
        'message 只有 refusal 无 content 时读 refusal 字段并标记 '
        'providerMetadata(超上游 refusal 支持,移植自 pigcode_ai_openai chat)',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-refusal',
          'created': 1700000000,
          'model': 'my-model',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'refusal': 'I cannot help with that request.',
              },
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')]),
          ],
        ),
      );

      expect(result.content, hasLength(1));
      final text = result.content.single as TextContent;
      expect(text.text, 'I cannot help with that request.');
      expect(text.providerMetadata?['mycustom']?['refusal'], isTrue);
    });

    test('普通 content 响应不带 refusal 标记(不回归)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse(content: 'hi there')),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hello')]),
          ],
        ),
      );

      final text = result.content.single as TextContent;
      expect(text.providerMetadata, isNull);
    });

    test(
        'thoughtSignature 跨轮往返:doGenerate 产出的 ToolCall.providerMetadata '
        '原样作为下一轮 tool-call part 的 providerOptions 时,请求体带 '
        'extra_content(Fix 1 端到端)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2e',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'get_weather',
                      'arguments': '{"city":"sf"}',
                    },
                    'extra_content': {
                      'google': {'thought_signature': 'sig-roundtrip'},
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'tool_calls',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final firstTurn = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')]),
          ],
        ),
      );
      final toolCall = firstTurn.content.single as ToolCall;

      // 模拟核心工具循环:把上一轮 ToolCall.providerMetadata 整 map 原样透传
      // 为下一轮 assistant tool-call part 的 providerOptions。
      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: [
            const UserMessage([TextPart('call a tool')]),
            AssistantMessage([
              ToolCallPart(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: const {'city': 'sf'},
                providerOptions: toolCall.providerMetadata,
              ),
            ]),
            const ToolMessage([
              ToolResultPart(
                toolCallId: 'call_1',
                toolName: 'get_weather',
                output: ToolResultText('sunny'),
              ),
            ]),
          ],
        ),
      );

      final replayedMessages = client.lastBody!['messages']! as List<Object?>;
      final assistantMessage = replayedMessages[1]! as Map<String, Object?>;
      final replayedToolCalls =
          assistantMessage['tool_calls']! as List<Object?>;
      final replayedCall = replayedToolCalls.single! as Map<String, Object?>;
      expect(replayedCall['extra_content'], {
        'google': {'thought_signature': 'sig-roundtrip'},
      });
    });

    test('tool_calls 的 thought_signature 为空串时视同未提供(Fix 4)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2d',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'get_weather',
                      'arguments': '{"city":"sf"}',
                    },
                    'extra_content': {
                      'google': {'thought_signature': ''},
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'tool_calls',
            },
          ],
        })),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')]),
          ],
        ),
      );

      final toolCall = result.content.single as ToolCall;
      expect(toolCall.providerMetadata, isNull);
    });

    group('response_format 三态', () {
      test(
          'supportsStructuredOutputs=false + schema 非空:退化 json_object 且产出 warning',
          () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
            topK: 5,
            responseFormat: ResponseFormatJson(
              schema: JsonSchema({'type': 'object'}),
              name: 'my_schema',
            ),
          ),
        );

        expect(client.lastBody!['response_format'], {'type': 'json_object'});
        // topK 与 responseFormat 各恰好一条 warning(回归:warnings 不因
        // 返回值二次拼接而重复)。
        expect(
          result.warnings
              .where((w) => w is UnsupportedWarning && w.feature == 'topK'),
          hasLength(1),
        );
        expect(
          result.warnings.where((w) =>
              w is UnsupportedWarning &&
              w.feature == 'responseFormat' &&
              w.details ==
                  'JSON response format schema is only supported with structuredOutputs'),
          hasLength(1),
        );
      });

      test(
          'supportsStructuredOutputs=true + schema 非空:下发 json_schema,无 warning',
          () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client, supportsStructuredOutputs: true),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
            responseFormat: ResponseFormatJson(
              schema: JsonSchema({'type': 'object'}),
              name: 'my_schema',
              description: 'a schema',
            ),
          ),
        );

        expect(client.lastBody!['response_format'], {
          'type': 'json_schema',
          'json_schema': {
            'schema': {'type': 'object'},
            'strict': true,
            'name': 'my_schema',
            'description': 'a schema',
          },
        });
        expect(
          result.warnings.any(
              (w) => w is UnsupportedWarning && w.feature == 'responseFormat'),
          isFalse,
        );
      });

      test('schema 为空:无论 supportsStructuredOutputs 取值恒 json_object 且无 warning',
          () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client, supportsStructuredOutputs: true),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
            responseFormat: ResponseFormatJson(),
          ),
        );

        expect(client.lastBody!['response_format'], {'type': 'json_object'});
        expect(
          result.warnings.any(
              (w) => w is UnsupportedWarning && w.feature == 'responseFormat'),
          isFalse,
        );
      });
    });

    test('工具 warning 不因返回值拼接而重复(ProviderTool 恰好一条)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse()),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          tools: [
            ProviderTool(id: 'ns.search', name: 'search', args: {}),
          ],
        ),
      );

      expect(
        result.warnings.where((w) =>
            w is UnsupportedWarning &&
            w.feature == 'provider-defined tool ns.search'),
        hasLength(1),
      );
    });

    test('透传键覆盖标准字段,但被 reasoning_effort 等后写字段覆盖回去', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse()),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          temperature: 0.7,
          reasoning: ReasoningEffort.medium,
          providerOptions: {
            'mycustom': {
              'reasoning_effort': 'should-be-overridden',
              'custom_field': 'x',
              'temperature': 0.1,
            },
          },
        ),
      );

      // 标准 reasoning 覆盖了透传里同名的 wire 键。
      expect(client.lastBody!['reasoning_effort'], 'medium');
      // 未知键透传成功。
      expect(client.lastBody!['custom_field'], 'x');
      // 透传键覆盖了 call 级 options.temperature(透传展开晚于标准字段写入)。
      expect(client.lastBody!['temperature'], 0.1);
    });

    test('透传键显式 null 被保留:请求体含该键且值为 null(Fix 3)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse()),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          providerOptions: {
            'mycustom': {'logit_bias': null},
          },
        ),
      );

      expect(client.lastBody!.containsKey('logit_bias'), isTrue);
      expect(client.lastBody!['logit_bias'], isNull);
    });

    test('标准字段未设置(如 temperature)时请求体不含该键(不回归既有行为)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse()),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('max_tokens'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
      expect(client.lastBody!.containsKey('tools'), isFalse);
      expect(client.lastBody!.containsKey('tool_choice'), isFalse);
    });

    group('reasoning_effort 解析', () {
      Future<Map<String, Object?>> bodyFor(
        LanguageModelCallOptions options,
      ) async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );
        await model.doGenerate(options);
        return client.lastBody!;
      }

      test('reasoning 为 null/providerDefault/none 时均不发 reasoning_effort',
          () async {
        for (final reasoning in [
          null,
          ReasoningEffort.providerDefault,
          ReasoningEffort.none,
        ]) {
          final body = await bodyFor(LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')]),
            ],
            reasoning: reasoning,
          ));
          expect(body.containsKey('reasoning_effort'), isFalse,
              reason: 'reasoning=$reasoning');
        }
      });

      test('reasoning=high 时下发 high', () async {
        final body = await bodyFor(const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          reasoning: ReasoningEffort.high,
        ));
        expect(body['reasoning_effort'], 'high');
      });

      test('providerOptions.reasoningEffort 优先于 call 级 reasoning', () async {
        final body = await bodyFor(const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          reasoning: ReasoningEffort.high,
          providerOptions: {
            'mycustom': {'reasoningEffort': 'custom-tier'},
          },
        ));
        expect(body['reasoning_effort'], 'custom-tier');
      });
    });

    group('reasoning 内容双读', () {
      Future<LanguageModelGenerateResult> resultFor(
        Map<String, Object?> message,
      ) async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-3',
            'choices': [
              {'message': message, 'index': 0, 'finish_reason': 'stop'},
            ],
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );
        return model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );
      }

      test('reasoning_content 非空时映射为 ReasoningContent', () async {
        final result = await resultFor({
          'role': 'assistant',
          'content': 'answer',
          'reasoning_content': 'thinking...',
        });
        expect(result.content, [
          const TextContent('answer'),
          const ReasoningContent('thinking...'),
        ]);
      });

      test('reasoning_content 缺失但 reasoning 非空时同样映射', () async {
        final result = await resultFor({
          'role': 'assistant',
          'content': 'answer',
          'reasoning': 'alt thinking',
        });
        expect(result.content, [
          const TextContent('answer'),
          const ReasoningContent('alt thinking'),
        ]);
      });

      test('两者都缺失时不含 ReasoningContent', () async {
        final result = await resultFor({
          'role': 'assistant',
          'content': 'answer',
        });
        expect(result.content.whereType<ReasoningContent>(), isEmpty);
      });
    });

    group('providerMetadata 与 metadataExtractor', () {
      test('extractor 结果整体覆盖空壳', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            metadataExtractor: MetadataExtractor(
              extractMetadata: (body) async => {
                'mycustom': {'extra': 1},
              },
              createStreamExtractor: () => StreamMetadataExtractor(
                processChunk: (_) {},
                buildMetadata: () => null,
              ),
            ),
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], {'extra': 1});
      });

      test('extractor 返回 null 时空壳兜底生效', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            metadataExtractor: MetadataExtractor(
              extractMetadata: (body) async => null,
              createStreamExtractor: () => StreamMetadataExtractor(
                processChunk: (_) {},
                buildMetadata: () => null,
              ),
            ),
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], const <String, Object?>{});
      });

      test('未配置 extractor 时同样带空壳', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], const <String, Object?>{});
      });

      test(
          'usage.completion_tokens_details 带 accepted/rejected prediction '
          'tokens 时回读进 providerMetadata', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-6',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'index': 0,
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'completion_tokens_details': {
                'accepted_prediction_tokens': 3,
                'rejected_prediction_tokens': 1,
              },
            },
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], {
          'acceptedPredictionTokens': 3,
          'rejectedPredictionTokens': 1,
        });
      });

      test(
          '无 completion_tokens_details 时 providerMetadata 不含 prediction '
          'token 键', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-7',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'index': 0,
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 5, 'completion_tokens': 2},
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], const <String, Object?>{});
      });

      test(
          'prediction tokens 与 metadataExtractor 结果合并:extractor 的其他键保留,'
          '两字段追加在其上', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-8',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'index': 0,
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'completion_tokens_details': {
                'accepted_prediction_tokens': 3,
                'rejected_prediction_tokens': 1,
              },
            },
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            metadataExtractor: MetadataExtractor(
              extractMetadata: (body) async => {
                'mycustom': {'extra': 1},
              },
              createStreamExtractor: () => StreamMetadataExtractor(
                processChunk: (_) {},
                buildMetadata: () => null,
              ),
            ),
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.providerMetadata?['mycustom'], {
          'extra': 1,
          'acceptedPredictionTokens': 3,
          'rejectedPredictionTokens': 1,
        });
      });

      test('prediction tokens 与 metadataExtractor 键冲突时:回读字段覆盖 extractor 的同名值',
          () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-9',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'index': 0,
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'completion_tokens_details': {
                'accepted_prediction_tokens': 3,
              },
            },
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            metadataExtractor: MetadataExtractor(
              extractMetadata: (body) async => {
                'mycustom': {'acceptedPredictionTokens': 999},
              },
              createStreamExtractor: () => StreamMetadataExtractor(
                processChunk: (_) {},
                buildMetadata: () => null,
              ),
            ),
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(
          result.providerMetadata?['mycustom']?['acceptedPredictionTokens'],
          3,
        );
      });
    });

    group('convertUsage 覆盖', () {
      test('usage 非空时完全绕过默认转换', () async {
        final client = _RecordingClient(
          (request) async => _jsonResponse(jsonEncode({
            'id': 'chatcmpl-4',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'index': 0,
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 5, 'completion_tokens': 2},
          })),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            convertUsage: (usage) => const LanguageModelUsage(
              inputTokens: InputTokens(total: 999),
              outputTokens: OutputTokens(),
            ),
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(result.usage.inputTokens.total, 999);
      });

      test('usage 缺失时不调用自定义转换,落到默认 null 空壳', () async {
        var customCalled = false;
        final client = _RecordingClient(
          (request) async => _jsonResponse(_basicResponse()),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(
            client,
            convertUsage: (usage) {
              customCalled = true;
              return const LanguageModelUsage(
                inputTokens: InputTokens(total: 999),
                outputTokens: OutputTokens(),
              );
            },
          ),
        );

        final result = await model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        );

        expect(customCalled, isFalse);
        expect(result.usage.inputTokens.total, isNull);
        expect(result.usage.outputTokens.total, isNull);
      });
    });

    test('transformRequestBody 在最终请求体与 request.body 上均生效', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(_basicResponse()),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          transformRequestBody: (args) => {...args, 'injected': true},
        ),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
        ),
      );

      expect(client.lastBody!['injected'], true);
      expect(client.lastBody!['model'], 'my-model');
      final requestBody = result.request?.body as Map<String, Object?>?;
      expect(requestBody?['injected'], true);
    });

    test('自定义 errorStructure 的失败响应解析', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          jsonEncode({'code': 'bad_request', 'detail': 'oops'}),
          statusCode: 400,
        ),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          errorStructure: ProviderErrorStructure(
            validator: JsonSchemaValidator.fromContract(
              const JsonSchema(<String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'code': <String, Object?>{'type': 'string'},
                  'detail': <String, Object?>{'type': 'string'},
                },
                'required': <Object?>['code', 'detail'],
              }),
            ),
            errorToMessage: (error) =>
                (error! as Map<String, Object?>)['detail']! as String,
          ),
        ),
      );

      await expectLater(
        model.doGenerate(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')]),
            ],
          ),
        ),
        throwsA(isA<ApiCallError>()
            .having((e) => e.message, 'message', 'oops')
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('choices 缺失或为空数组时抛 InvalidResponseDataError', () async {
      for (final body in [
        jsonEncode({'id': 'chatcmpl-5', 'choices': <Object?>[]}),
        jsonEncode({'id': 'chatcmpl-5'}),
      ]) {
        final client = _RecordingClient(
          (request) async => _jsonResponse(body),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        await expectLater(
          model.doGenerate(
            const LanguageModelCallOptions(
              prompt: [
                UserMessage([TextPart('hi')]),
              ],
            ),
          ),
          throwsA(isA<InvalidResponseDataError>()),
        );
      }
    });
  });
}
