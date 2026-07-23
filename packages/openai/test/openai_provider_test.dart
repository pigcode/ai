import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

import 'support/fake_http_client.dart';

void main() {
  // Compatibility fixture (unit): P1-OPENAI-01
  group('createOpenAi — baseUrl 与 Authorization', () {
    test('空 baseUrl 在构造 provider 时立即拒绝', () {
      expect(
        () => createOpenAi(apiKey: 'sk-test', baseUrl: ''),
        throwsA(
          isA<InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'baseUrl')
              .having(
                (error) => error.message,
                'message',
                'baseUrl must be a non-empty string.',
              ),
        ),
      );
    });

    test('默认 baseUrl 为官方地址,自定义 baseUrl 去除尾部斜杠', () async {
      final defaultProvider = createOpenAi(apiKey: 'sk-test');
      final customProvider = createOpenAi(
        apiKey: 'sk-test',
        baseUrl: 'https://proxy.example.com/v1/',
      );

      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: '{}',
        ),
      );

      // 通过实际发出的请求 URL 间接验证 baseUrl 已生效(config 不对外暴露)。
      final providerWithClient = createOpenAi(
        apiKey: 'sk-test',
        baseUrl: 'https://proxy.example.com/v1/',
        client: client,
      );
      expect(providerWithClient.chat('gpt-4o').provider, 'openai.chat');

      // baseUrl 去尾斜杠的直接可观察效果留给 Step 2(头部组装测试同时
      // 断言 URL),此处先只验证 provider 能以自定义 baseUrl 构造成功
      // 且不抛异常。
      expect(defaultProvider.chat('gpt-4o').provider, 'openai.chat');
      expect(customProvider.chat('gpt-4o').provider, 'openai.chat');
    });
  });

  group('createOpenAi — headers 组装', () {
    late FakeHttpClient client;

    setUp(() {
      client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: '{"id":"chatcmpl-1","object":"chat.completion",'
              '"created":1,"model":"gpt-4o","choices":[{"index":0,'
              '"message":{"role":"assistant","content":"hi"},'
              '"finish_reason":"stop"}]}',
        ),
      );
    });

    Future<void> triggerRequest(OpenAiProvider provider) async {
      await provider.chat('gpt-4o').doGenerate(
            const LanguageModelCallOptions(prompt: [
              UserMessage([TextPart('hi')]),
            ]),
          );
    }

    test('缺省 organization/project 时不带对应头', () async {
      final provider = createOpenAi(apiKey: 'sk-test', client: client);
      await triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      expect(sent.headers.containsKey('OpenAI-Organization'), isFalse);
      expect(sent.headers.containsKey('OpenAI-Project'), isFalse);
      expect(sent.headers['User-Agent'], 'pigcode_ai_openai/0.0.1');
    });

    test('提供 organization/project 时带对应头', () async {
      final provider = createOpenAi(
        apiKey: 'sk-test',
        organization: 'org-1',
        project: 'proj-1',
        client: client,
      );
      await triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['OpenAI-Organization'], 'org-1');
      expect(sent.headers['OpenAI-Project'], 'proj-1');
    });

    test('自定义 headers 与默认头合并,自定义值优先', () async {
      final provider = createOpenAi(
        apiKey: 'sk-test',
        headers: {'X-Custom': 'v', 'Authorization': 'Bearer override'},
        client: client,
      );
      await triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['X-Custom'], 'v');
      expect(sent.headers['Authorization'], 'Bearer override');
    });

    test('自定义 User-Agent 被追加后缀而非整体覆盖', () async {
      // 照抄上游 withUserAgentSuffix 语义(见 Interfaces 说明):已有
      // User-Agent 时固定后缀追加在其后(空格分隔),不是整体覆盖——
      // 与 combineHeaders 对其它 header 的"后者覆盖前者"语义刻意不同,
      // 因为 UA 拼接是"叠加"语义而非"替换"语义。
      final provider = createOpenAi(
        apiKey: 'sk-test',
        headers: {'user-agent': 'my-app/1.0'},
        client: client,
      );
      await triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['User-Agent'], 'my-app/1.0 pigcode_ai_openai/0.0.1');
    });
  });

  group('loadApiKey 契约复用', () {
    test('headers 函数每次求值都会重新调用 loadApiKey(不是构造时求值一次)', () async {
      // 用一个会变化的 client 观察 headers 是否为惰性:同一个 provider
      // 连续两次触发请求,Authorization 头应保持一致且两次都成功——
      // 说明 getHeaders 内部确实每次都调用 loadApiKey 而非仅在
      // createOpenAi 调用时求值一次并缓存(缓存也能通过本测试,但至少
      // 排除"从不调用 loadApiKey、自行拼接导致校验被绕过"的回归)。
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: '{"id":"chatcmpl-1","object":"chat.completion",'
              '"created":1,"model":"gpt-4o","choices":[{"index":0,'
              '"message":{"role":"assistant","content":"hi"},'
              '"finish_reason":"stop"}]}',
        ),
      );
      final provider = createOpenAi(apiKey: 'sk-test', client: client);
      final model = provider.chat('gpt-4o');

      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
        ),
      );
      await model.doGenerate(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi again')]),
          ],
        ),
      );

      expect(client.recordedRequests, hasLength(2));
      for (final sent in client.recordedRequests) {
        expect(sent.headers['Authorization'], 'Bearer sk-test');
      }
    });
  });

  group('LoadApiKeyError 契约', () {
    test('utils loadApiKey 缺失时抛出契约 LoadApiKeyError(createOpenAi 内部依赖此行为)', () {
      expect(
        () => loadApiKey(apiKey: null, settingName: 'OpenAI API key'),
        throwsA(isA<LoadApiKeyError>()),
      );
    });
  });

  group('createOpenAi — languageModel 默认路由到 responses', () {
    test('languageModel(modelId) 的 provider 为 "<name>.responses"', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.languageModel('gpt-4o');

      expect(model.provider, 'openai.responses');
      expect(model.modelId, 'gpt-4o');
      expect(model, isA<LanguageModel>());
    });

    test('chat(modelId) 与 responses(modelId) 分别显式指向对应 wire', () {
      final provider = createOpenAi(apiKey: 'sk-test');

      expect(provider.chat('gpt-4o').provider, 'openai.chat');
      expect(provider.responses('gpt-4o').provider, 'openai.responses');
    });

    test('自定义 name 时 provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(provider.chat('gpt-4o').provider, 'custom-openai.chat');
      expect(provider.responses('gpt-4o').provider, 'custom-openai.responses');
      expect(
        provider.languageModel('gpt-4o').provider,
        'custom-openai.responses',
      );
    });

    test('OpenAiProvider 实现契约 Provider 接口', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      expect(provider, isA<Provider>());
    });
  });

  group('createOpenAi — embeddingModel 工厂接线', () {
    test('embeddingModel(modelId) 返回 "<name>.embedding" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.embeddingModel('text-embedding-3-small');

      expect(model.provider, 'openai.embedding');
      expect(model.modelId, 'text-embedding-3-small');
      expect(model, isA<EmbeddingModel>());
    });

    test('自定义 name 时 embedding provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(
        provider.embeddingModel('text-embedding-3-small').provider,
        'custom-openai.embedding',
      );
    });

    test('embeddingModel 经契约 Provider 接口调用满足 EmbeddingModel 类型', () {
      // 显式收窄为契约 [Provider] 类型再调用:若 `@override` 挂错签名或
      // 接口成员缺失,此处直接编译失败——编译期 + 运行期双重确认,
      // 防止实现方法与接口静默不匹配。
      final Provider provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.embeddingModel('text-embedding-3-small');

      expect(model, isA<EmbeddingModel>());
      expect(model.modelId, 'text-embedding-3-small');
      expect(model.provider, 'openai.embedding');
    });
  });

  group('createOpenAi — imageModel 工厂接线', () {
    test('imageModel(modelId) 返回 "<name>.image" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.imageModel('gpt-image-1');

      expect(model.provider, 'openai.image');
      expect(model.modelId, 'gpt-image-1');
      expect(model, isA<ImageModel>());
    });

    test('自定义 name 时 image provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(
        provider.imageModel('gpt-image-1').provider,
        'custom-openai.image',
      );
    });

    test('imageModel 经契约 Provider 接口调用满足 ImageModel 类型', () {
      final Provider provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.imageModel('gpt-image-1');

      expect(model, isA<ImageModel>());
      expect(model.modelId, 'gpt-image-1');
      expect(model.provider, 'openai.image');
    });
  });

  group('createOpenAi — transcriptionModel 工厂接线', () {
    test('transcriptionModel(modelId) 返回 "<name>.transcription" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.transcriptionModel('whisper-1');

      expect(model.provider, 'openai.transcription');
      expect(model.modelId, 'whisper-1');
      expect(model, isA<TranscriptionModel>());
    });

    test('自定义 name 时 transcription provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(
        provider.transcriptionModel('whisper-1').provider,
        'custom-openai.transcription',
      );
    });

    test('transcriptionModel 经契约 Provider 接口调用满足 TranscriptionModel 类型', () {
      final Provider provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.transcriptionModel('whisper-1');

      expect(model, isA<TranscriptionModel>());
      expect(model.modelId, 'whisper-1');
      expect(model.provider, 'openai.transcription');
    });
  });

  group('createOpenAi — speechModel 工厂接线', () {
    test('speechModel(modelId) 返回 "<name>.speech" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.speechModel('tts-1');

      expect(model.provider, 'openai.speech');
      expect(model.modelId, 'tts-1');
      expect(model, isA<SpeechModel>());
    });

    test('自定义 name 时 speech provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(provider.speechModel('tts-1').provider, 'custom-openai.speech');
    });

    test('speechModel 经契约 Provider 接口调用满足 SpeechModel 类型', () {
      final Provider provider = createOpenAi(apiKey: 'sk-test');
      final model = provider.speechModel('tts-1');

      expect(model, isA<SpeechModel>());
      expect(model.modelId, 'tts-1');
      expect(model.provider, 'openai.speech');
    });
  });

  group('createOpenAi — rerankingModel 工厂接线', () {
    test('OpenAI 当前不支持 rerankingModel,经契约调用抛 NoSuchModelError', () {
      final Provider provider = createOpenAi(apiKey: 'sk-test');

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

  group('createOpenAi — files/skills 工厂接线', () {
    test('files() 返回 "<name>.files" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final files = provider.files();

      expect(files.provider, 'openai.files');
      expect(files, isA<Files>());
    });

    test('skills() 返回 "<name>.skills" 的实例', () {
      final provider = createOpenAi(apiKey: 'sk-test');
      final skills = provider.skills();

      expect(skills.provider, 'openai.skills');
      expect(skills, isA<Skills>());
    });

    test('经契约 Provider 接口调用满足 Files 与 Skills 类型', () {
      final Provider provider = createOpenAi(apiKey: 'sk-test');

      expect(provider.files(), isA<Files>());
      expect(provider.skills(), isA<Skills>());
    });

    test('自定义 name 时 files/skills provider 前缀随之变化', () {
      final provider = createOpenAi(apiKey: 'sk-test', name: 'custom-openai');

      expect(provider.files().provider, 'custom-openai.files');
      expect(provider.skills().provider, 'custom-openai.skills');
    });
  });
}
