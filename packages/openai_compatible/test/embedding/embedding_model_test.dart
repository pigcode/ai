import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {'content-type': 'application/json'},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
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

OpenAiCompatibleEmbeddingConfig _config(
  http.Client client, {
  ProviderErrorStructure? errorStructure,
  int? maxEmbeddingsPerCall = 2048,
  bool supportsParallelCalls = true,
}) {
  return OpenAiCompatibleEmbeddingConfig(
    providerName: 'mycustom',
    url: (path) => Uri.parse('https://api.mycustom.dev/v1$path'),
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
    errorStructure: errorStructure,
    maxEmbeddingsPerCall: maxEmbeddingsPerCall,
    supportsParallelCalls: supportsParallelCalls,
  );
}

/// 标准成功响应体(两条 embedding;[includeUsage]/[providerMetadata] 控制
/// 对应可选字段在场与否)。
String _successBody({
  bool includeUsage = true,
  Map<String, Object?>? providerMetadata,
}) {
  return jsonEncode({
    'object': 'list',
    'data': [
      {
        'object': 'embedding',
        'index': 0,
        'embedding': [0.1, 0.2],
      },
      {
        'object': 'embedding',
        'index': 1,
        'embedding': [0.3, 0.4],
      },
    ],
    'model': 'my-embed-model',
    if (includeUsage) 'usage': {'prompt_tokens': 7, 'total_tokens': 7},
    if (providerMetadata != null) 'providerMetadata': providerMetadata,
  });
}

void main() {
  // Compatibility fixture (unit): P1-COMPAT-04
  group('OpenAiCompatibleEmbeddingModel — 基础字段与能力值', () {
    test(
        'provider/modelId,默认 maxEmbeddingsPerCall 2048、'
        'supportsParallelCalls true', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      expect(model.provider, 'mycustom.embedding');
      expect(model.modelId, 'my-embed-model');
      expect(await model.maxEmbeddingsPerCall, 2048);
      expect(await model.supportsParallelCalls, isTrue);
      expect(model, isA<EmbeddingModel>());
    });

    test('config 显式传 maxEmbeddingsPerCall: null 时 getter 经 ?? 兜底仍为 2048',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client, maxEmbeddingsPerCall: null),
      );

      expect(await model.maxEmbeddingsPerCall, 2048);
    });

    test('config 覆盖能力值:maxEmbeddingsPerCall 32、supportsParallelCalls false',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(
          client,
          maxEmbeddingsPerCall: 32,
          supportsParallelCalls: false,
        ),
      );

      expect(await model.maxEmbeddingsPerCall, 32);
      expect(await model.supportsParallelCalls, isFalse);
    });
  });

  group('OpenAiCompatibleEmbeddingModel.doEmbed — 请求侧', () {
    test('请求体含 model/input/encoding_format,缺省时 dimensions/user 键被剔除', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.mycustom.dev/v1/embeddings',
      );
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      // 整体相等断言:同时覆盖"缺省键被剔除而非 null 值"。
      expect(client.lastBody, {
        'model': 'my-embed-model',
        'input': ['a', 'b'],
        'encoding_format': 'float',
      });
    });

    test('providerOptions[providerName] 的 dimensions/user 进入请求体', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      await model.doEmbed(
        const EmbeddingModelCallOptions(
          values: ['a'],
          providerOptions: {
            'mycustom': {'dimensions': 256, 'user': 'u1'},
          },
        ),
      );

      expect(client.lastBody, {
        'model': 'my-embed-model',
        'input': ['a'],
        'encoding_format': 'float',
        'dimensions': 256,
        'user': 'u1',
      });
    });

    test(
        'values 超过 maxEmbeddingsPerCall 时抛 TooManyEmbeddingValuesForCallError '
        '且不发请求', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client, maxEmbeddingsPerCall: 2),
      );

      await expectLater(
        model.doEmbed(const EmbeddingModelCallOptions(values: ['a', 'b', 'c'])),
        throwsA(
          isA<TooManyEmbeddingValuesForCallError>()
              .having((e) => e.provider, 'provider', 'mycustom.embedding')
              .having((e) => e.modelId, 'modelId', 'my-embed-model')
              .having(
                (e) => e.maxEmbeddingsPerCall,
                'maxEmbeddingsPerCall',
                2,
              )
              .having((e) => e.valuesCount, 'valuesCount', 3),
        ),
      );
      expect(client.lastRequest, isNull);
    });

    test('providerOptions 非法且同时超量时,先抛 TypeValidationError', () async {
      // 顺序差异的行为后果:本包 doEmbed 先解析 providerOptions、后做超量
      // 守卫(对照 raw L100-134 解析在前、L136-143 守卫在后),与
      // pigcode_ai_openai 包(守卫在最前)相反——同一用例在 openai 包中预期抛
      // TooManyEmbeddingValuesForCallError,在本包中预期抛
      // TypeValidationError。
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client, maxEmbeddingsPerCall: 2),
      );

      await expectLater(
        model.doEmbed(
          const EmbeddingModelCallOptions(
            values: ['a', 'b', 'c'],
            providerOptions: {
              'mycustom': {'dimensions': true},
            },
          ),
        ),
        throwsA(isA<TypeValidationError>()),
      );
      expect(client.lastRequest, isNull);
    });
  });

  group('OpenAiCompatibleEmbeddingModel.doEmbed — 响应侧', () {
    test('成功响应解码为保序 List<double> embeddings', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(result.embeddings, [
        [0.1, 0.2],
        [0.3, 0.4],
      ]);
      expect(result.embeddings.first, isA<List<double>>());
    });

    test('usage 缺席时 tokens 为 null;带 prompt_tokens 时读取', () async {
      final withoutUsageClient = _RecordingClient(
        (request) async => _jsonResponse(_successBody(includeUsage: false)),
      );
      final withoutUsage = await OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(withoutUsageClient),
      ).doEmbed(const EmbeddingModelCallOptions(values: ['a']));

      expect(withoutUsage.usage.tokens, isNull);

      final withUsageClient = _RecordingClient(
        (request) async => _jsonResponse(_successBody()),
      );
      final withUsage = await OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(withUsageClient),
      ).doEmbed(const EmbeddingModelCallOptions(values: ['a']));

      expect(withUsage.usage.tokens, 7);
    });

    test('warnings 恒空;response 捕获响应头与完整解码 body', () async {
      final body = _successBody();
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          body,
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'req-1',
          },
        ),
      );
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(result.warnings, isEmpty);
      expect(result.response!.headers!['x-request-id'], 'req-1');
      expect(result.response!.body, jsonDecode(body));
    });

    test('响应体顶层 providerMetadata 整体透传', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          _successBody(
            providerMetadata: {
              'foo': {'bar': 1},
            },
          ),
        ),
      );
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      // 整体透传:不嵌套包一层 provider 名、不与 providerOptionsName 混合
      // (对照 raw `providerMetadata: response.providerMetadata`)。
      expect(result.providerMetadata, {
        'foo': {'bar': 1},
      });
    });

    test('响应体不带 providerMetadata 字段时结果为 null', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(result.providerMetadata, isNull);
    });

    test('自定义 errorStructure 生效(非默认 error 信封形状)', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          jsonEncode({'message': 'custom overloaded', 'code': 1}),
          statusCode: 503,
        ),
      );
      // 模拟一个私有错误体形状 {message, code} 的第三方服务(无 error 信封)。
      final customStructure = ProviderErrorStructure(
        validator: JsonSchemaValidator.fromContract(
          const JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'message': <String, Object?>{'type': 'string'},
              'code': <String, Object?>{'type': 'integer'},
            },
            'required': <Object?>['message'],
          }),
        ),
        errorToMessage: (JsonValue error) =>
            (error! as JsonObject)['message']! as String,
        isRetryable: (http.StreamedResponse response, JsonValue? error) =>
            false,
      );
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client, errorStructure: customStructure),
      );

      await expectLater(
        model.doEmbed(const EmbeddingModelCallOptions(values: ['a'])),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'custom overloaded')
              .having((e) => e.statusCode, 'statusCode', 503)
              // isRetryable 回调显式返回 false,覆盖契约默认对 503 的
              // 可重试推断——证明走的是自定义结构而非默认结构。
              .having((e) => e.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('未提供 errorStructure 时错误响应走默认 OpenAI 错误信封', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          jsonEncode({
            'error': {
              'message': 'Invalid API key',
              'type': 'invalid_request_error',
            },
          }),
          statusCode: 401,
        ),
      );
      final model = OpenAiCompatibleEmbeddingModel(
        'my-embed-model',
        config: _config(client),
      );

      await expectLater(
        model.doEmbed(const EmbeddingModelCallOptions(values: ['a'])),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'Invalid API key')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}
