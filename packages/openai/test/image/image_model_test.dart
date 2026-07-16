import 'dart:convert';
import 'dart:typed_data';

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
  Map<String, String>? lastFields;
  List<http.MultipartFile>? lastFiles;
  List<List<int>>? lastFileBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastBody = jsonDecode(request.body) as Map<String, Object?>;
    } else if (request is http.MultipartRequest) {
      lastFields = Map<String, String>.of(request.fields);
      lastFiles = List<http.MultipartFile>.of(request.files);
      lastFileBytes = [
        for (final file in request.files) await file.finalize().toBytes(),
      ];
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

String _successBody() {
  return jsonEncode({
    'created': 123,
    'data': [
      {
        'b64_json': base64Encode([1, 2, 3]),
        'revised_prompt': 'a sharper prompt',
      },
      {
        'b64_json': base64Encode([4, 5])
      },
    ],
    'background': 'transparent',
    'output_format': 'webp',
    'size': '1024x1024',
    'quality': 'high',
    'usage': {
      'input_tokens': 12,
      'output_tokens': 20,
      'total_tokens': 32,
      'input_tokens_details': {
        'image_tokens': 7,
        'text_tokens': 5,
      },
    },
  });
}

void main() {
  group('OpenAiImageModel — 基础字段', () {
    test('provider/modelId/specificationVersion/maxImagesPerCall', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));
      final dallE3 = OpenAiImageModel('dall-e-3', config: _config(client));
      final unknown = OpenAiImageModel('custom-image', config: _config(client));

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'openai.image');
      expect(model.modelId, 'gpt-image-1');
      expect(await model.maxImagesPerCall, 10);
      expect(await dallE3.maxImagesPerCall, 1);
      expect(await unknown.maxImagesPerCall, 1);
      expect(model, isA<ImageModel>());
    });
  });

  group('OpenAiImageModel.doGenerate — 请求侧', () {
    test('发送 JSON 到 /images/generations,旧模型显式请求 b64_json', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('dall-e-3', config: _config(client));

      await model.doGenerate(
        const ImageModelCallOptions(
          prompt: 'draw a quiet lake',
          n: 1,
          size: '1024x1024',
          headers: {'x-custom': 'v'},
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/images/generations',
      );
      expect(client.lastRequest!.method, 'POST');
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      expect(client.lastRequest!.headers['x-custom'], 'v');
      expect(client.lastBody, {
        'model': 'dall-e-3',
        'prompt': 'draw a quiet lake',
        'n': 1,
        'size': '1024x1024',
        'response_format': 'b64_json',
      });
    });

    test('最新图片模型不发送 response_format,providerOptions 映射到 OpenAI 字段', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      await model.doGenerate(
        const ImageModelCallOptions(
          prompt: 'draw a product icon',
          n: 2,
          providerOptions: {
            'openai': {
              'quality': 'high',
              'style': 'vivid',
              'background': 'transparent',
              'moderation': 'low',
              'outputFormat': 'webp',
              'outputCompression': 80,
              'user': 'user-1',
            },
          },
        ),
      );

      expect(client.lastBody, {
        'model': 'gpt-image-1',
        'prompt': 'draw a product icon',
        'n': 2,
        'quality': 'high',
        'style': 'vivid',
        'background': 'transparent',
        'moderation': 'low',
        'output_format': 'webp',
        'output_compression': 80,
        'user': 'user-1',
      });
    });

    test('aspectRatio/seed 被忽略并返回 unsupported warning', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      final result = await model.doGenerate(
        const ImageModelCallOptions(
          prompt: 'draw a square icon',
          aspectRatio: '1:1',
          seed: 42,
        ),
      );

      expect(client.lastBody!.containsKey('aspectRatio'), isFalse);
      expect(client.lastBody!.containsKey('seed'), isFalse);
      expect(result.warnings, hasLength(2));
      expect(
        result.warnings
            .map((warning) => (warning as UnsupportedWarning).feature),
        ['aspectRatio', 'seed'],
      );
    });

    test('Azure providerName 时读取 azure 选项并以 azure key 返回 metadata', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel(
        'gpt-image-1',
        config: _config(client, providerName: 'azure-openai'),
      );

      final result = await model.doGenerate(
        const ImageModelCallOptions(
          prompt: 'draw an azure icon',
          providerOptions: {
            'azure': {'quality': 'high'},
          },
        ),
      );

      expect(model.provider, 'azure-openai.image');
      expect(client.lastBody!['quality'], 'high');
      expect(result.providerMetadata!.containsKey('openai'), isFalse);
      expect(result.providerMetadata!['azure'], isNotNull);
    });

    test('有编辑输入时发送 multipart 到 /images/edits', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));
      final imageBytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      final maskBytes = Uint8List.fromList([1, 2, 3, 4]);

      await model.doGenerate(
        ImageModelCallOptions(
          prompt: 'replace the sky',
          n: 1,
          size: '1024x1024',
          headers: const {'x-custom': 'v'},
          files: [
            ImageModelFileBytes(imageBytes, mediaType: 'image/png'),
          ],
          mask: ImageModelFileBase64(
            base64Encode(maskBytes),
            mediaType: 'image/png',
          ),
          providerOptions: const {
            'openai': {
              'quality': 'high',
              'background': 'transparent',
              'moderation': 'low',
              'outputFormat': 'webp',
              'outputCompression': 80,
              'inputFidelity': 'high',
              'user': 'user-1',
            },
          },
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/images/edits',
      );
      expect(client.lastRequest!.method, 'POST');
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      expect(client.lastRequest!.headers['x-custom'], 'v');
      expect(client.lastFields, {
        'model': 'gpt-image-1',
        'prompt': 'replace the sky',
        'n': '1',
        'size': '1024x1024',
        'quality': 'high',
        'background': 'transparent',
        'moderation': 'low',
        'output_format': 'webp',
        'output_compression': '80',
        'input_fidelity': 'high',
        'user': 'user-1',
      });
      expect(client.lastFiles, hasLength(2));
      expect(client.lastFiles![0].field, 'image');
      expect(client.lastFiles![0].filename, 'image.png');
      expect(client.lastFiles![0].contentType.toString(), 'image/png');
      expect(client.lastFileBytes![0], [0x89, 0x50, 0x4e, 0x47]);
      expect(client.lastFiles![1].field, 'mask');
      expect(client.lastFiles![1].filename, 'mask.png');
      expect(client.lastFiles![1].contentType.toString(), 'image/png');
      expect(client.lastFileBytes![1], [1, 2, 3, 4]);
    });

    test('多个编辑输入使用 image[] multipart 字段', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      await model.doGenerate(
        ImageModelCallOptions(
          prompt: 'combine images',
          files: [
            ImageModelFileBytes(
              Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
              mediaType: 'image/png',
            ),
            ImageModelFileBytes(
              Uint8List.fromList([0xff, 0xd8, 0xff]),
              mediaType: 'image/jpeg',
            ),
          ],
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/images/edits',
      );
      expect(client.lastFiles!.map((file) => file.field), [
        'image[]',
        'image[]',
      ]);
      expect(client.lastFiles!.map((file) => file.filename), [
        'image-1.png',
        'image-2.jpeg',
      ]);
    });

    test('dall-e-2 编辑请求显式要求 b64_json 响应', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('dall-e-2', config: _config(client));

      await model.doGenerate(
        ImageModelCallOptions(
          prompt: 'edit image',
          files: [
            ImageModelFileBytes(
              Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
              mediaType: 'image/png',
            ),
          ],
        ),
      );

      expect(client.lastFields!['response_format'], 'b64_json');
    });

    test('mask 没有 files 时抛 InvalidArgumentError', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      await expectLater(
        model.doGenerate(
          ImageModelCallOptions(
            prompt: 'edit image',
            mask: ImageModelFileBytes(
              Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
              mediaType: 'image/png',
            ),
          ),
        ),
        throwsA(
          isA<InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'mask'),
        ),
      );
      expect(client.lastRequest, isNull);
    });

    test('混合 URL 和 inline image edits 发送 JSON image_url 引用', () async {
      final client =
          _RecordingClient((request) async => _jsonResponse(_successBody()));
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));
      final imageUrl = Uri.parse('https://example.com/input.png');

      await model.doGenerate(
        ImageModelCallOptions(
          prompt: 'edit image',
          files: [
            ImageModelFileBytes(
              Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
              mediaType: 'image/png',
            ),
            ImageModelFileUrl(imageUrl),
          ],
          mask: ImageModelFileBase64(
            base64Encode([1, 2, 3, 4]),
            mediaType: 'image/png',
          ),
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/images/edits',
      );
      expect(client.lastRequest, isA<http.Request>());
      expect(client.lastBody, {
        'model': 'gpt-image-1',
        'prompt': 'edit image',
        'images': [
          {'image_url': 'data:image/png;base64,iVBORw=='},
          {'image_url': imageUrl.toString()},
        ],
        'mask': {'image_url': 'data:image/png;base64,AQIDBA=='},
        'n': 1,
      });
    });
  });

  group('OpenAiImageModel.doGenerate — 响应侧', () {
    test('成功响应解码图片、usage、response 与 providerMetadata', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          _successBody(),
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'req-1',
          },
        ),
      );
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      final result = await model.doGenerate(
        const ImageModelCallOptions(prompt: 'draw a quiet lake', n: 2),
      );

      expect(result.images.map((image) => image.toList()), [
        [1, 2, 3],
        [4, 5],
      ]);
      expect(
        result.usage,
        const ImageModelUsage(
          inputTokens: 12,
          outputTokens: 20,
          totalTokens: 32,
        ),
      );
      expect(result.response!.modelId, 'gpt-image-1');
      expect(result.response!.headers!['x-request-id'], 'req-1');
      expect(result.providerMetadata, {
        'openai': {
          'images': [
            {
              'revisedPrompt': 'a sharper prompt',
              'created': 123,
              'size': '1024x1024',
              'quality': 'high',
              'background': 'transparent',
              'outputFormat': 'webp',
              'imageTokens': 3,
              'textTokens': 2,
            },
            {
              'created': 123,
              'size': '1024x1024',
              'quality': 'high',
              'background': 'transparent',
              'outputFormat': 'webp',
              'imageTokens': 4,
              'textTokens': 3,
            },
          ],
        },
      });
    });

    test('错误响应经 openAiFailedResponseHandler 抛 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          jsonEncode({
            'error': {'message': 'bad image request'},
          }),
          statusCode: 400,
        ),
      );
      final model = OpenAiImageModel('gpt-image-1', config: _config(client));

      await expectLater(
        model.doGenerate(const ImageModelCallOptions(prompt: 'draw')),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'bad image request')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
