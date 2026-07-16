import 'dart:convert';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

import 'support/fake_http_client.dart';

/// 最小成功响应体(与 Task 16 口径一致),供 doGenerate 走通解析。
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

FakeHttpClient _minimalClient() => FakeHttpClient(
      responseBuilder: (request) async => fakeStreamedResponse(
        statusCode: 200,
        body: _minimalResponse(),
        headers: {'content-type': 'application/json'},
      ),
    );

const _prompt = <LanguageModelMessage>[
  UserMessage(<UserContentPart>[TextPart('hello')]),
];

/// 触发一次实际请求,便于观察 headers/URL(照 openai 包 triggerRequest 模式)。
Future<void> _triggerRequest(AnthropicProvider provider) async {
  await provider.messages('claude-sonnet-4-5').doGenerate(
        const LanguageModelCallOptions(prompt: _prompt),
      );
}

void main() {
  group('createAnthropic — 认证互斥', () {
    test('apiKey 与 authToken 同时提供时抛 ArgumentError(逐字文案)', () {
      expect(
        () => createAnthropic(apiKey: 'k', authToken: 't'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains(
              'Both apiKey and authToken were provided. '
              'Please use only one authentication method.',
            ),
          ),
        ),
      );
    });

    test('只传其一或都不传时构造不抛(header 惰性求值)', () {
      expect(() => createAnthropic(apiKey: 'k'), returnsNormally);
      expect(() => createAnthropic(authToken: 't'), returnsNormally);
      expect(() => createAnthropic(), returnsNormally);
    });
  });

  group('createAnthropic — header 组装', () {
    test('apiKey 路径:x-api-key + anthropic-version,不含 Authorization', () async {
      final client = _minimalClient();
      final provider = createAnthropic(apiKey: 'k', client: client);
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['x-api-key'], 'k');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.headers.containsKey('Authorization'), isFalse);
    });

    test('authToken 路径:Authorization Bearer,不含 x-api-key', () async {
      final client = _minimalClient();
      final provider = createAnthropic(authToken: 't', client: client);
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer t');
      expect(sent.headers.containsKey('x-api-key'), isFalse);
    });

    test('都不传:doGenerate 阶段抛契约 LoadApiKeyError(惰性语义)', () async {
      final client = _minimalClient();
      final provider = createAnthropic(client: client);

      await expectLater(
        _triggerRequest(provider),
        throwsA(isA<LoadApiKeyError>()),
      );
      expect(client.recordedRequests, isEmpty);
    });

    test('自定义 headers 出现在请求中且可覆盖默认头', () async {
      final client = _minimalClient();
      final provider = createAnthropic(
        apiKey: 'k',
        headers: {'X-Custom': 'v', 'anthropic-version': 'override'},
        client: client,
      );
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['X-Custom'], 'v');
      expect(sent.headers['anthropic-version'], 'override');
    });

    test('User-Agent 缺省为 pigcode_ai_anthropic/0.0.1', () async {
      final client = _minimalClient();
      final provider = createAnthropic(apiKey: 'k', client: client);
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.headers['User-Agent'], 'pigcode_ai_anthropic/0.0.1');
    });

    test('调用方自带 User-Agent 被追加后缀而非整体覆盖', () async {
      final client = _minimalClient();
      final provider = createAnthropic(
        apiKey: 'k',
        headers: {'User-Agent': 'my-app/1.0'},
        client: client,
      );
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(
          sent.headers['User-Agent'], 'my-app/1.0 pigcode_ai_anthropic/0.0.1');
    });
  });

  group('createAnthropic — baseURL 生效', () {
    test('自定义 baseUrl(带尾斜杠)→ 去斜杠后拼 /messages', () async {
      final client = _minimalClient();
      final provider = createAnthropic(
        apiKey: 'k',
        baseUrl: 'https://proxy.example.com/v1/',
        client: client,
      );
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(
        sent.url.toString(),
        startsWith('https://proxy.example.com/v1/messages'),
      );
    });

    test('缺省 baseUrl → https://api.anthropic.com/v1/messages', () async {
      final client = _minimalClient();
      final provider = createAnthropic(apiKey: 'k', client: client);
      await _triggerRequest(provider);

      final sent = client.recordedRequests.single;
      expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    });
  });

  group('createAnthropic — 三入口别名', () {
    test('languageModel/chat/messages 均返回 LanguageModel', () {
      final provider = createAnthropic(apiKey: 'k');

      expect(provider.languageModel('claude-sonnet-4-5'), isA<LanguageModel>());
      expect(provider.chat('claude-sonnet-4-5'), isA<LanguageModel>());
      expect(provider.messages('claude-sonnet-4-5'), isA<LanguageModel>());
    });
  });

  group('createAnthropic — 其余模态抛 NoSuchModelError', () {
    test('六个非语言模态各抛 NoSuchModelError 且 modelType 对应', () {
      final Provider provider = createAnthropic(apiKey: 'k');

      void expectNoSuchModel(
        void Function() call,
        ModelType expectedType,
      ) {
        expect(
          call,
          throwsA(
            isA<NoSuchModelError>()
                .having((e) => e.modelId, 'modelId', 'm')
                .having((e) => e.modelType, 'modelType', expectedType),
          ),
        );
      }

      expectNoSuchModel(
        () => provider.embeddingModel('m'),
        ModelType.embeddingModel,
      );
      expectNoSuchModel(() => provider.imageModel('m'), ModelType.imageModel);
      expectNoSuchModel(
        () => provider.transcriptionModel('m'),
        ModelType.transcriptionModel,
      );
      expectNoSuchModel(() => provider.speechModel('m'), ModelType.speechModel);
      expectNoSuchModel(() => provider.videoModel('m'), ModelType.videoModel);
      expectNoSuchModel(
        () => provider.rerankingModel('m'),
        ModelType.rerankingModel,
      );
    });
  });

  group('createAnthropic — files/skills resources', () {
    test('无认证时构造 resources 不求值 headers', () {
      final unauthenticated = createAnthropic();

      expect(() => unauthenticated.files(), returnsNormally);
      expect(() => unauthenticated.skills(), returnsNormally);
    });

    test('缺省名称映射为 anthropic.files/anthropic.skills', () {
      final Provider provider = createAnthropic(apiKey: 'k');

      final files = provider.files();
      final skills = provider.skills();

      expect(files, isA<AnthropicFiles>());
      expect(files.provider, 'anthropic.files');
      expect(skills, isA<AnthropicSkills>());
      expect(skills.provider, 'anthropic.skills');
    });

    test('自定义 .messages 名称替换为对应 resource 名称', () {
      final Provider provider = createAnthropic(
        apiKey: 'k',
        name: 'my-anthropic.messages',
      );

      expect(provider.files().provider, 'my-anthropic.files');
      expect(provider.skills().provider, 'my-anthropic.skills');
    });

    test('无 .messages 后缀的自定义名称追加 resource 名称', () {
      final Provider provider = createAnthropic(
        apiKey: 'k',
        name: 'my-anthropic',
      );

      expect(provider.files().provider, 'my-anthropic.files');
      expect(provider.skills().provider, 'my-anthropic.skills');
    });

    test('factory 配置贯穿到 Files 离线上传', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'id': 'file_factory',
            'type': 'file',
            'filename': 'blob',
            'mime_type': 'text/plain',
            'size_bytes': 1,
            'created_at': '2026-07-10T00:00:00Z',
            'downloadable': true,
            'scope': <String, Object?>{
              'type': 'workspace',
              'id': 'workspace_1',
            },
          }),
          headers: {'content-type': 'application/json'},
        ),
      );
      final provider = createAnthropic(
        apiKey: 'resource-key',
        baseUrl: 'https://gateway.example/api/',
        headers: {'x-custom': 'resource'},
        client: client,
      );

      final result = await provider.files().uploadFile(
            const FilesUploadOptions(
              data: FileDataText('x'),
              mediaType: 'text/plain',
            ),
          );

      final sent = client.recordedRequests.single;
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://gateway.example/api/files');
      expect(sent.headers['x-api-key'], 'resource-key');
      expect(sent.headers['x-custom'], 'resource');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(result.providerReference, <String, String>{
        'anthropic': 'file_factory',
      });
    });
  });

  group('createAnthropic — supportedUrls 与 provider 名', () {
    test('supportedUrls 恰含 image/* 与 application/pdf 两键', () async {
      final provider = createAnthropic(apiKey: 'k');
      final urls = await Future.value(
        provider.languageModel('claude-sonnet-4-5').supportedUrls,
      );

      expect(urls.keys, unorderedEquals(['image/*', 'application/pdf']));
    });

    test('缺省 provider 名为 anthropic.messages', () {
      final provider = createAnthropic(apiKey: 'k');
      final model = provider.languageModel('claude-sonnet-4-5');

      expect(model.provider, 'anthropic.messages');
    });

    test('AnthropicProvider 实现契约 Provider 接口', () {
      final provider = createAnthropic(apiKey: 'k');
      expect(provider, isA<Provider>());
      expect(provider.specificationVersion, providerSpecVersion);
    });
  });
}
