import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
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

OpenAiConfig _config(http.Client client, {String providerName = 'openai'}) {
  return OpenAiConfig(
    providerName: providerName,
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
  );
}

/// 标准成功响应体(两条 embedding;[includeUsage] 控制 usage 字段在场与否)。
String _successBody({bool includeUsage = true}) {
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
    'model': 'text-embedding-3-small',
    if (includeUsage) 'usage': {'prompt_tokens': 7, 'total_tokens': 7},
  });
}

void main() {
  group('OpenAiEmbeddingModel — 基础字段', () {
    test('provider/modelId/maxEmbeddingsPerCall/supportsParallelCalls',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );

      expect(model.provider, 'openai.embedding');
      expect(model.modelId, 'text-embedding-3-small');
      expect(await model.maxEmbeddingsPerCall, 2048);
      expect(await model.supportsParallelCalls, isTrue);
      expect(model, isA<EmbeddingModel>());
    });
  });

  group('OpenAiEmbeddingModel.doEmbed — 请求侧', () {
    test('请求体含 model/input/encoding_format,缺省时 dimensions/user 键被剔除', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );

      await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/embeddings',
      );
      // 整体相等断言:同时覆盖"缺省键被剔除而非 null 值"。
      expect(client.lastBody, {
        'model': 'text-embedding-3-small',
        'input': ['a', 'b'],
        'encoding_format': 'float',
      });
    });

    test('providerOptions.openai 的 dimensions/user 进入请求体', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );

      await model.doEmbed(
        const EmbeddingModelCallOptions(
          values: ['a'],
          providerOptions: {
            'openai': {'dimensions': 256, 'user': 'u1'},
          },
        ),
      );

      expect(client.lastBody, {
        'model': 'text-embedding-3-small',
        'input': ['a'],
        'encoding_format': 'float',
        'dimensions': 256,
        'user': 'u1',
      });
    });

    test('azure providerName 时读取 azure 键下的选项(派生 key 对称)', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client, providerName: 'azure-foo'),
      );

      await model.doEmbed(
        const EmbeddingModelCallOptions(
          values: ['a'],
          providerOptions: {
            'azure': {'dimensions': 128},
          },
        ),
      );

      expect(model.provider, 'azure-foo.embedding');
      expect(client.lastBody!['dimensions'], 128);
    });

    test('values 超过 2048 时抛 TooManyEmbeddingValuesForCallError 且不发请求',
        () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );
      final values = List<String>.filled(2049, 'x');

      await expectLater(
        model.doEmbed(EmbeddingModelCallOptions(values: values)),
        throwsA(
          isA<TooManyEmbeddingValuesForCallError>()
              .having((e) => e.provider, 'provider', 'openai.embedding')
              .having(
                (e) => e.modelId,
                'modelId',
                'text-embedding-3-small',
              )
              .having(
                (e) => e.maxEmbeddingsPerCall,
                'maxEmbeddingsPerCall',
                2048,
              )
              .having((e) => e.valuesCount, 'valuesCount', 2049),
        ),
      );
      // 守卫必须在 options 解析与请求发送之前:未发起任何 HTTP 请求。
      expect(client.lastRequest, isNull);
    });
  });

  group('OpenAiEmbeddingModel.doEmbed — 响应侧', () {
    test('成功响应解码为保序 List<double> embeddings', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
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
      final withoutUsage = await OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(withoutUsageClient),
      ).doEmbed(const EmbeddingModelCallOptions(values: ['a']));

      expect(withoutUsage.usage.tokens, isNull);

      final withUsageClient = _RecordingClient(
        (request) async => _jsonResponse(_successBody()),
      );
      final withUsage = await OpenAiEmbeddingModel(
        'text-embedding-3-small',
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
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['a', 'b']),
      );

      expect(result.warnings, isEmpty);
      expect(result.response!.headers!['x-request-id'], 'req-1');
      expect(result.response!.body, jsonDecode(body));
    });

    test('错误响应经 openAiFailedResponseHandler 抛 ApiCallError', () async {
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
      final model = OpenAiEmbeddingModel(
        'text-embedding-3-small',
        config: _config(client),
      );

      await expectLater(
        model.doEmbed(const EmbeddingModelCallOptions(values: ['a'])),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'Invalid API key'),
        ),
      );
    });
  });
}
