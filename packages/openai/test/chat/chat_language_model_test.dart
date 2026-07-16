import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
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

OpenAiConfig _config(http.Client client) {
  return OpenAiConfig(
    providerName: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
  );
}

void main() {
  group('OpenAiChatLanguageModel.doGenerate', () {
    test('provider/modelId/请求 URL 与基础字段', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-1',
          'created': 1700000000,
          'model': 'gpt-4o',
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
            'total_tokens': 7
          },
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      expect(model.provider, 'openai.chat');
      expect(model.modelId, 'gpt-4o');

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hello')])
          ],
        ),
      );

      expect(client.lastRequest!.url.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(client.lastBody!['model'], 'gpt-4o');
      expect(client.lastBody!['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(client.lastBody!.containsKey('stream'), isFalse);

      expect(result.content, [const TextContent('hi there')]);
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.usage.inputTokens.total, 5);
      expect(result.usage.outputTokens.total, 2);
    });

    test('tool_calls 响应映射,id 缺失时用 generateId 兜底', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-2',
          'created': 1700000000,
          'model': 'gpt-4o',
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
                      'arguments': '{"city":"sf"}'
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
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')])
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

    test('推理模型裁剪 temperature/topP 并把 max_tokens 搬到 max_completion_tokens',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          maxOutputTokens: 500,
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
      expect(client.lastBody!.containsKey('max_tokens'), isFalse);
      expect(client.lastBody!['max_completion_tokens'], 500);
      expect(client.lastBody!['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('response_format json_schema 三态与 topK 产出 warning', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '{}'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          topK: 5,
          responseFormat: ResponseFormatJson(
            schema: JsonSchema({'type': 'object'}),
            name: 'my_schema',
          ),
        ),
      );

      expect(client.lastBody!['response_format'], {
        'type': 'json_schema',
        'json_schema': {
          'schema': {'type': 'object'},
          'strict': true,
          'name': 'my_schema',
        },
      });
      expect(
        result.warnings
            .any((w) => w is UnsupportedWarning && w.feature == 'topK'),
        isTrue,
      );
    });

    test(
        'gpt-5.1 系列在 reasoningEffort=none 时保留 '
        'temperature/topP/logprobs/top_logprobs', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-5.1', config: _config(client));

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{
              'reasoningEffort': 'none',
              'logprobs': 5,
            },
          },
        ),
      );

      expect(client.lastBody!['temperature'], 0.7);
      expect(client.lastBody!['top_p'], 0.9);
      expect(client.lastBody!['logprobs'], true);
      // top_logprobs 与 logprobs 同受 none 豁免(主动偏离上游疑似 bug,
      // 见 chat_language_model.dart 裁剪块注释):top-N 数量不被静默降级。
      expect(client.lastBody!['top_logprobs'], 5);
      expect(client.lastBody!['reasoning_effort'], 'none');
      expect(
        result.warnings.any((w) =>
            w is UnsupportedWarning &&
            (w.feature == 'temperature' || w.feature == 'topP')),
        isFalse,
      );
      expect(
        result.warnings
            .any((w) => w is OtherWarning && w.message.contains('topLogprobs')),
        isFalse,
      );
    });

    test('gpt-5.1 系列在 reasoningEffort 非 none 时仍裁剪 temperature/topP/logprobs',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-5.1', config: _config(client));

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'medium'},
          },
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
    });

    test(
        'provider 名含 azure 时,providerOptions 优先从 "azure" 键解析'
        '(与 responses wire 对称,逐字对齐 v7 providerOptionsName = '
        "provider.includes(\"azure\") ? 'azure' : 'openai')", () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'azure': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      expect(client.lastBody!['reasoning_effort'], 'high');
    });

    test(
        'provider 名含 azure 且 "azure" 键缺失时,回退读取 "openai" 键'
        '(对齐 v7 openaiOptions == null && providerOptionsName !== "openai" '
        '的二次解析)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      expect(client.lastBody!['reasoning_effort'], 'high');
    });

    test(
        'provider 名含 azure 时,文件引用按 "azure" 键解析为 file_id'
        '(与 call 级 options 派生及 responses 侧文件引用取齐)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([
              TextPart('summarize this'),
              FilePart(
                data: FileDataReference({'azure': 'file-az-9'}),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
        ),
      );

      final messages = client.lastBody!['messages']! as List<Object?>;
      final userMessage = messages.single! as Map<String, Object?>;
      final content = userMessage['content']! as List<Object?>;
      final filePart = content[1]! as Map<String, Object?>;
      final file = filePart['file']! as Map<String, Object?>;
      expect(file['file_id'], 'file-az-9');
    });

    test('默认(非 azure)provider 名 + "openai" 键:既有行为不回归', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-5.1', config: _config(client));

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      expect(client.lastBody!['reasoning_effort'], 'high');
    });

    test(
        'o3(不支持 non-reasoning 参数)在 reasoningEffort=none 时依旧裁剪 temperature/topP',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'none'},
          },
        ),
      );

      expect(client.lastBody!.containsKey('temperature'), isFalse);
      expect(client.lastBody!.containsKey('top_p'), isFalse);
    });

    test('非推理模型剔除 reasoning_effort 并产生 warning', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'medium'},
          },
        ),
      );

      expect(client.lastBody!.containsKey('reasoning_effort'), isFalse);
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isTrue,
      );
    });

    test('推理模型路径下 reasoning_effort 仍正常透传,不回归', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'medium'},
          },
        ),
      );

      expect(client.lastBody!['reasoning_effort'], 'medium');
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isFalse,
      );
    });

    test(
        'options.reasoning=providerDefault 视为未设置:请求体无 '
        'reasoning_effort 字段,且无 warning', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          reasoning: ReasoningEffort.providerDefault,
        ),
      );

      expect(client.lastBody!.containsKey('reasoning_effort'), isFalse);
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isFalse,
      );
    });

    test('options.reasoning=medium(标准字段)照常透传为 reasoning_effort', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          reasoning: ReasoningEffort.medium,
        ),
      );

      expect(client.lastBody!['reasoning_effort'], 'medium');
    });

    test('service_tier=flex 在不支持的模型上被剔除并产生 warning', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model =
          OpenAiChatLanguageModel('gpt-3.5-turbo', config: _config(client));

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'flex'},
          },
        ),
      );

      expect(client.lastBody!.containsKey('service_tier'), isFalse);
      expect(
        result.warnings
            .any((w) => w is UnsupportedWarning && w.feature == 'serviceTier'),
        isTrue,
      );
    });

    test('service_tier=flex 在支持的模型上原样透传', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('o3', config: _config(client));

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'flex'},
          },
        ),
      );

      expect(client.lastBody!['service_tier'], 'flex');
    });

    test('service_tier=priority 在不支持的模型上被剔除并产生 warning', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model =
          OpenAiChatLanguageModel('gpt-5-nano', config: _config(client));

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'priority'},
          },
        ),
      );

      expect(client.lastBody!.containsKey('service_tier'), isFalse);
      expect(
        result.warnings
            .any((w) => w is UnsupportedWarning && w.feature == 'serviceTier'),
        isTrue,
      );
    });

    test('message 只有 refusal 无 content 时读 refusal 字段并标记 providerMetadata',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-refusal',
          'created': 1700000000,
          'model': 'gpt-4o',
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
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')])
          ],
        ),
      );

      expect(result.content, hasLength(1));
      final text = result.content.single as TextContent;
      expect(text.text, 'I cannot help with that request.');
      expect(text.providerMetadata?['openai']?['refusal'], isTrue);
    });

    test(
        'choice.logprobs.content + usage.completion_tokens_details 非空时 '
        '结果 providerMetadata 含 logprobs/acceptedPredictionTokens/'
        'rejectedPredictionTokens', () async {
      final logprobsContent = [
        {
          'token': 'hi',
          'logprob': -0.1,
          'bytes': [104, 105],
          'top_logprobs': <Object?>[],
        },
      ];
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-logprobs',
          'created': 1700000000,
          'model': 'gpt-4o',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'hi'},
              'index': 0,
              'finish_reason': 'stop',
              'logprobs': {'content': logprobsContent},
            },
          ],
          'usage': {
            'prompt_tokens': 5,
            'completion_tokens': 2,
            'total_tokens': 7,
            'completion_tokens_details': {
              'accepted_prediction_tokens': 3,
              'rejected_prediction_tokens': 1,
            },
          },
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: <String, JsonObject>{
            'openai': <String, Object?>{'logprobs': true},
          },
        ),
      );

      expect(
        result.providerMetadata?['openai']?['logprobs'],
        logprobsContent,
      );
      expect(
        result.providerMetadata?['openai']?['acceptedPredictionTokens'],
        3,
      );
      expect(
        result.providerMetadata?['openai']?['rejectedPredictionTokens'],
        1,
      );
    });

    test('无 logprobs/prediction tokens 字段时 providerMetadata 不含对应键', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-nometa',
          'created': 1700000000,
          'model': 'gpt-4o',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'hi'},
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
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );

      final openaiMetadata = result.providerMetadata?['openai'];
      expect(openaiMetadata, isNotNull);
      expect(openaiMetadata!.containsKey('logprobs'), isFalse);
      expect(openaiMetadata.containsKey('acceptedPredictionTokens'), isFalse);
      expect(openaiMetadata.containsKey('rejectedPredictionTokens'), isFalse);
    });

    test(
        'azure provider 名下 doGenerate 的 providerMetadata/refusal 标记均用 '
        "'azure' 派生 key", () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-azure',
          'created': 1700000000,
          'model': 'gpt-4o',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'refusal': 'cannot help',
              },
              'index': 0,
              'finish_reason': 'stop',
              'logprobs': {
                'content': [
                  {
                    'token': 'x',
                    'logprob': -0.2,
                    'bytes': null,
                    'top_logprobs': <Object?>[],
                  },
                ],
              },
            },
          ],
          'usage': {
            'prompt_tokens': 5,
            'completion_tokens': 2,
            'total_tokens': 7,
            'completion_tokens_details': {
              'accepted_prediction_tokens': 2,
              'rejected_prediction_tokens': 0,
            },
          },
        })),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-4o',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')])
          ],
        ),
      );

      final text = result.content.single as TextContent;
      expect(text.providerMetadata?['azure']?['refusal'], isTrue);
      expect(result.providerMetadata?['azure']?['logprobs'], isNotNull);
      expect(
        result.providerMetadata?['azure']?['acceptedPredictionTokens'],
        2,
      );
      expect(result.providerMetadata?.containsKey('openai'), isFalse);
    });

    test('message.annotations 带 url_citation 时映射为 SourceContent.url', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-annotations',
          'created': 1700000000,
          'model': 'gpt-4o-search-preview',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'See the source below.',
                'annotations': [
                  {
                    'type': 'url_citation',
                    'url_citation': {
                      'url': 'https://example.com/a',
                      'title': 'Example A',
                    },
                  },
                ],
              },
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-4o-search-preview',
        config: _config(client),
      );

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('what is the source?')])
          ],
        ),
      );

      expect(result.content, hasLength(2));
      expect(result.content.first, isA<TextContent>());
      final source = result.content[1] as SourceContent;
      expect(source.sourceType, SourceType.url);
      expect(source.url, 'https://example.com/a');
      expect(source.title, 'Example A');
      expect(source.id, isNotEmpty);
    });

    test('message 无 annotations 字段时不产出 SourceContent', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'id': 'chatcmpl-no-annotations',
          'created': 1700000000,
          'model': 'gpt-4o',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'plain answer',
              },
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
        })),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );

      expect(result.content, hasLength(1));
      expect(result.content.whereType<SourceContent>(), isEmpty);
    });
  });
}
