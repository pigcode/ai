import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

import 'support/fake_http_client.dart';

/// 最简成功响应体(单 choice 文本消息)。
String _basicResponse() => jsonEncode({
      'id': 'chatcmpl-1',
      'created': 1700000000,
      'model': 'my-model',
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'ok'},
          'index': 0,
          'finish_reason': 'stop',
        },
      ],
    });

/// 恒返回 [_basicResponse](或给定 [body])的 JSON 成功响应 client。
FakeHttpClient _jsonClient({String? body, int statusCode = 200}) {
  return FakeHttpClient(
    responseBuilder: (request) async => fakeStreamedResponse(
      statusCode: statusCode,
      body: body ?? _basicResponse(),
      headers: {'content-type': 'application/json'},
    ),
  );
}

/// 最简 SSE 成功响应 client(单帧文本 delta + DONE 哨兵)。
FakeHttpClient _sseClient() {
  return FakeHttpClient(
    responseBuilder: (request) async => fakeStreamedResponse(
      statusCode: 200,
      body: 'data: {"id":"chatcmpl-1","created":1700000000,'
          '"model":"my-model","choices":[{"index":0,'
          '"delta":{"role":"assistant","content":"hi"},'
          '"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
      headers: {'content-type': 'text/event-stream'},
    ),
  );
}

const _prompt = LanguageModelCallOptions(
  prompt: [
    UserMessage([TextPart('hello')]),
  ],
);

void main() {
  group('createOpenAiCompatible 构造与模型分派', () {
    test(
        'chatModel/languageModel 的 provider 均为 <name>.chat,'
        'baseUrl 尾斜杠被去除', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1/',
        client: client,
      );

      expect(provider.chatModel('m1').provider, 'mycustom.chat');
      expect(provider.chatModel('m1').modelId, 'm1');
      expect(provider.languageModel('m1').provider, 'mycustom.chat');

      await provider.chatModel('m1').doGenerate(_prompt);

      // 尾斜杠已去除:URL 不是 …/v1//chat/completions。
      expect(
        client.recordedRequests.single.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('OpenAiCompatibleProvider 满足契约 Provider 类型', () {
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );
      expect(provider, isA<Provider>());
      expect(provider, isA<OpenAiCompatibleProvider>());
    });

    test('languageModel 与 chatModel 对同一 modelId 行为等价', () {
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );
      final viaLanguageModel = provider.languageModel('m1');
      final viaChatModel = provider.chatModel('m1');
      // 每次调用都 new 一个新实例是既定模式(同 pigcode_ai_openai),只要求
      // 可观察行为等价,不要求同一实例。
      expect(viaLanguageModel.provider, viaChatModel.provider);
      expect(viaLanguageModel.modelId, viaChatModel.modelId);
    });
  });

  group('headers 组装', () {
    test('apiKey 提供时带 Authorization: Bearer 头', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(
        client.recordedRequests.single.headers['Authorization'],
        'Bearer test-key',
      );
    });

    test('apiKey 为 null 时不带 Authorization 头', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(
        client.recordedRequests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('用户 headers 后合并,可覆盖 apiKey 头', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
        headers: {'Authorization': 'Bearer override', 'X-Custom': 'v'},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      final requestHeaders = client.recordedRequests.single.headers;
      expect(requestHeaders['Authorization'], 'Bearer override');
      expect(requestHeaders['X-Custom'], 'v');
    });
  });

  group('url 闭包与 queryParams', () {
    test('queryParams 非空时追加为请求 URL 的 query', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        queryParams: {'key': 'abc'},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(
        client.recordedRequests.single.url.toString(),
        'https://api.example.com/v1/chat/completions?key=abc',
      );
    });

    test('baseUrl 自带 query 且 queryParams 非空时,原 query 被整体覆盖', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1?foo=bar',
        queryParams: {'key': 'abc'},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      // 逐字对齐 raw `url.search = new URLSearchParams(...)`:整体替换,
      // foo=bar 被覆盖丢失(v7 原生行为,非 bug)。
      final url = client.recordedRequests.single.url;
      expect(url.toString().contains('foo=bar'), isFalse);
      expect(url.queryParameters, {'key': 'abc'});
    });

    test('queryParams 为 null 时 URL 无 query 部分', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(client.recordedRequests.single.url.hasQuery, isFalse);
    });

    test('queryParams 为空 map 时同样无 query 部分', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        queryParams: const {},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(client.recordedRequests.single.url.hasQuery, isFalse);
    });

    test('baseUrl 自带 query 而 queryParams 为 null 时,原 query 保留', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1?foo=bar',
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      // 注:path 直接拼接在 baseUrl 之后(对齐 raw `${baseURL}${path}`),
      // 带 query 的 baseUrl 会让 path 落进 query 串——此处只断言原 query
      // 内容未被丢弃(v7 同款拼接语义)。
      expect(
        client.recordedRequests.single.url.toString().contains('foo=bar'),
        isTrue,
      );
    });
  });

  group('User-Agent 追加', () {
    test('未提供自定义 UA 时为包名/版本后缀', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(
        client.recordedRequests.single.headers['User-Agent'],
        'pigcode_ai_openai_compatible/0.0.1',
      );
    });

    test('提供自定义 UA 时后缀追加而非覆盖', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        headers: {'user-agent': 'my-app/1.0'},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      expect(
        client.recordedRequests.single.headers['User-Agent'],
        'my-app/1.0 pigcode_ai_openai_compatible/0.0.1',
      );
    });
  });

  group('扩展点透传', () {
    test('includeUsage: true 时 doStream 请求体带 stream_options', () async {
      final client = _sseClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        includeUsage: true,
        client: client,
      );

      final result = await provider.chatModel('m1').doStream(_prompt);
      await result.stream.drain<void>();

      final body =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(body['stream'], true);
      expect(body['stream_options'], {'include_usage': true});
    });

    test('supportsStructuredOutputs: true 时 json_schema 响应格式可用', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        supportsStructuredOutputs: true,
        client: client,
      );

      await provider.chatModel('m1').doGenerate(
            LanguageModelCallOptions(
              prompt: const [
                UserMessage([TextPart('hello')]),
              ],
              responseFormat: ResponseFormatJson(
                schema: JsonSchema({'type': 'object'}),
              ),
            ),
          );

      final body =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final responseFormat = body['response_format'] as Map<String, Object?>?;
      expect(responseFormat?['type'], 'json_schema');
    });

    test('errorStructure 透传:自定义错误体形状被解析', () async {
      final client = _jsonClient(
        body: jsonEncode({'code': 'bad_request', 'detail': 'oops'}),
        statusCode: 400,
      );
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
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
        client: client,
      );

      await expectLater(
        provider.chatModel('m1').doGenerate(_prompt),
        throwsA(isA<ApiCallError>()
            .having((e) => e.message, 'message', 'oops')
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('metadataExtractor 透传:结果并入 providerMetadata', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        metadataExtractor: MetadataExtractor(
          extractMetadata: (body) async => {
            'mycustom': {'extra': 1},
          },
          createStreamExtractor: () => StreamMetadataExtractor(
            processChunk: (_) {},
            buildMetadata: () => null,
          ),
        ),
        client: client,
      );

      final result = await provider.chatModel('m1').doGenerate(_prompt);

      expect(result.providerMetadata?['mycustom'], {'extra': 1});
    });

    test('supportedUrls 透传:model.supportedUrls 返回对应值', () async {
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        supportedUrls: () => {
          'image/*': [RegExp(r'^https://example\.com/.*$')],
        },
      );

      final urls = await provider.chatModel('m1').supportedUrls;

      expect(urls.keys, ['image/*']);
      expect(
        urls['image/*']!.single.hasMatch('https://example.com/a.png'),
        isTrue,
      );
    });

    test('transformRequestBody 透传:请求体经变换后发出', () async {
      final client = _jsonClient();
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        transformRequestBody: (args) => {...args, 'injected': true},
        client: client,
      );

      await provider.chatModel('m1').doGenerate(_prompt);

      final body =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(body['injected'], true);
      expect(body['model'], 'm1');
    });

    test('errorStructure 同时对 chatModel 与 embeddingModel 生效', () async {
      // 两模态共用工厂同一个 errorStructure 入参(主动偏离上游工厂不接线
      // embedding 三项的裁决,见 openai_compatible_provider.dart 注释)。
      final customStructure = ProviderErrorStructure(
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
      );
      final client = _jsonClient(
        body: jsonEncode({'code': 'bad_request', 'detail': 'oops'}),
        statusCode: 400,
      );
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        errorStructure: customStructure,
        client: client,
      );

      await expectLater(
        provider.chatModel('m1').doGenerate(_prompt),
        throwsA(
          isA<ApiCallError>().having((e) => e.message, 'message', 'oops'),
        ),
      );
      await expectLater(
        provider
            .embeddingModel('my-embed-model')
            .doEmbed(const EmbeddingModelCallOptions(values: ['a'])),
        throwsA(
          isA<ApiCallError>().having((e) => e.message, 'message', 'oops'),
        ),
      );
    });

    test('convertUsage 透传:自定义 usage 转换生效', () async {
      final client = _jsonClient(
        body: jsonEncode({
          'id': 'chatcmpl-2',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'index': 0,
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 5, 'completion_tokens': 2},
        }),
      );
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        convertUsage: (usage) => const LanguageModelUsage(
          inputTokens: InputTokens(total: 999),
          outputTokens: OutputTokens(),
        ),
        client: client,
      );

      final result = await provider.chatModel('m1').doGenerate(_prompt);

      expect(result.usage.inputTokens.total, 999);
    });
  });

  group('embeddingModel 工厂接线', () {
    test('embeddingModel 的 provider 为 <name>.embedding、modelId 原样保留', () {
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );

      final model = provider.embeddingModel('my-embed-model');

      expect(model, isA<OpenAiCompatibleEmbeddingModel>());
      expect(model.provider, 'mycustom.embedding');
      expect(model.modelId, 'my-embed-model');
    });

    test(
        'embeddingMaxEmbeddingsPerCall/embeddingSupportsParallelCalls '
        '经工厂透传,缺省时为 2048/true', () async {
      final defaults = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );
      expect(await defaults.embeddingModel('m1').maxEmbeddingsPerCall, 2048);
      expect(await defaults.embeddingModel('m1').supportsParallelCalls, isTrue);

      final overridden = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
        embeddingMaxEmbeddingsPerCall: 64,
        embeddingSupportsParallelCalls: false,
      );
      expect(await overridden.embeddingModel('m1').maxEmbeddingsPerCall, 64);
      expect(
        await overridden.embeddingModel('m1').supportsParallelCalls,
        isFalse,
      );
    });

    test('embeddingModel 复用工厂的 url/headers 组装(含 apiKey 与 UA 后缀)', () async {
      final client = _jsonClient(
        body: jsonEncode({
          'data': [
            {
              'embedding': [0.1],
            },
          ],
        }),
      );
      final provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1/',
        apiKey: 'test-key',
        client: client,
      );

      await provider
          .embeddingModel('my-embed-model')
          .doEmbed(const EmbeddingModelCallOptions(values: ['a']));

      final request = client.recordedRequests.single;
      expect(
        request.url.toString(),
        'https://api.example.com/v1/embeddings',
      );
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(
        request.headers['User-Agent'],
        'pigcode_ai_openai_compatible/0.0.1',
      );
    });

    test('embeddingModel 经契约 Provider 接口调用满足 EmbeddingModel 类型', () {
      // 显式收窄为契约 [Provider] 类型再调用:若 `@override` 挂错签名或
      // 接口成员缺失,此处直接编译失败——编译期 + 运行期双重确认,
      // 防止实现方法与接口静默不匹配。
      final Provider provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );
      final model = provider.embeddingModel('m1');

      expect(model, isA<EmbeddingModel>());
      expect(model, isA<OpenAiCompatibleEmbeddingModel>());
      expect(model.modelId, 'm1');
      expect(model.provider, 'mycustom.embedding');
    });
  });

  group('imageModel 工厂接线', () {
    test('OpenAI compatible 当前不支持 imageModel,经契约调用抛 NoSuchModelError', () {
      final Provider provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(
        () => provider.imageModel('gpt-image-1'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'gpt-image-1')
              .having((e) => e.modelType, 'modelType', ModelType.imageModel),
        ),
      );
    });
  });

  group('rerankingModel 工厂接线', () {
    test(
        'OpenAI compatible 当前不支持 rerankingModel,'
        '经契约调用抛 NoSuchModelError', () {
      final Provider provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(
        () => provider.rerankingModel('rerank-1'),
        throwsA(
          isA<NoSuchModelError>()
              .having((e) => e.modelId, 'modelId', 'rerank-1')
              .having(
                (e) => e.modelType,
                'modelType',
                ModelType.rerankingModel,
              ),
        ),
      );
    });
  });

  group('files/skills 工厂接线', () {
    test('OpenAI compatible 当前不支持 files,经契约调用抛 UnsupportedFunctionalityError',
        () {
      final Provider provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(
        provider.files,
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'files',
          ),
        ),
      );
    });

    test('OpenAI compatible 当前不支持 skills,经契约调用抛 UnsupportedFunctionalityError',
        () {
      final Provider provider = createOpenAiCompatible(
        name: 'mycustom',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(
        provider.skills,
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            'skills',
          ),
        ),
      );
    });
  });
}
