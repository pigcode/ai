import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('generateImage', () {
    test('prompt/options/headers/cancellation 透传给 doGenerate', () async {
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [Uint8List.fromList(_pngBytes)],
          warnings: const [],
        ),
      );
      final controller = contracts.CancellationController();

      await generateImage(
        model: model,
        prompt: 'draw a calm lake',
        n: 1,
        size: '1024x1024',
        aspectRatio: '1:1',
        seed: 42,
        providerOptions: const {
          'openai': {'quality': 'high'},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(received.prompt, 'draw a calm lake');
      expect(received.n, 1);
      expect(received.size, '1024x1024');
      expect(received.aspectRatio, '1:1');
      expect(received.seed, 42);
      expect(received.providerOptions, {
        'openai': {'quality': 'high'},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('image 编辑输入转换为 provider image files 和 mask', () async {
      final bytes = Uint8List.fromList(_pngBytes);
      final base64 = base64Encode(_pngBytes);
      final url = Uri.parse('https://example.com/input.png');
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [Uint8List.fromList(_pngBytes)],
          warnings: const [],
        ),
      );

      await generateImage(
        model: model,
        prompt: 'replace the sky',
        images: [
          DataBytes(bytes),
          DataBase64(base64),
          DataUrl(url),
        ],
        mask: DataBase64(base64),
      );

      final received = model.receivedCallOptions.single;
      expect(received.files, hasLength(3));
      expect(
        received.files![0],
        isA<contracts.ImageModelFileBytes>()
            .having((file) => file.bytes.toList(), 'bytes', _pngBytes)
            .having((file) => file.mediaType, 'mediaType', 'image/png'),
      );
      expect(
        received.files![1],
        isA<contracts.ImageModelFileBase64>()
            .having((file) => file.base64, 'base64', base64)
            .having((file) => file.mediaType, 'mediaType', 'image/png'),
      );
      expect(
        received.files![2],
        isA<contracts.ImageModelFileUrl>()
            .having((file) => file.url, 'url', url),
      );
      expect(
        received.mask,
        isA<contracts.ImageModelFileBase64>()
            .having((file) => file.base64, 'base64', base64)
            .having((file) => file.mediaType, 'mediaType', 'image/png'),
      );
    });

    test('image 编辑输入拒绝文本和 provider reference', () async {
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [Uint8List.fromList(_pngBytes)],
          warnings: const [],
        ),
      );

      await expectLater(
        generateImage(
          model: model,
          prompt: 'edit image',
          images: const [DataText('not image bytes')],
        ),
        throwsA(
          isA<contracts.InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'images'),
        ),
      );

      await expectLater(
        generateImage(
          model: model,
          prompt: 'edit image',
          mask: const DataProviderRef({'openai': 'file-1'}),
        ),
        throwsA(
          isA<contracts.InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'mask'),
        ),
      );
    });

    test('mask 没有 images 时抛 InvalidArgumentError', () async {
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [Uint8List.fromList(_pngBytes)],
          warnings: const [],
        ),
      );

      await expectLater(
        generateImage(
          model: model,
          prompt: 'edit with mask',
          mask: DataBase64(base64Encode(_pngBytes)),
        ),
        throwsA(
          isA<contracts.InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'mask'),
        ),
      );
      expect(model.receivedCallOptions, isEmpty);
    });

    test('按 maxImagesPerCall 分批并聚合结果', () async {
      final records = captureWarningLogs();
      final responses = [
        contracts.ResponseInfo(
          modelId: 'image-model',
          timestamp: DateTime.utc(2026, 1),
        ),
        contracts.ResponseInfo(
          modelId: 'image-model',
          timestamp: DateTime.utc(2026, 2),
        ),
        contracts.ResponseInfo(
          modelId: 'image-model',
          timestamp: DateTime.utc(2026, 3),
        ),
      ];
      final model = _ScriptedImageModel(
        maxImagesPerCallValue: 2,
        resultForCall: (options, index) async {
          return contracts.ImageModelResult(
            images: [
              for (var i = 0; i < options.n; i++)
                Uint8List.fromList([index, i]),
            ],
            warnings: [contracts.OtherWarning('warning-$index')],
            usage: contracts.ImageModelUsage(
              inputTokens: index,
              outputTokens: index + 10,
              totalTokens: index + 20,
            ),
            providerMetadata: {
              'test': {
                'call$index': options.n,
                'images': [
                  for (var i = 0; i < options.n; i++) {'call': index, 'i': i},
                ],
              },
            },
            response: responses[index - 1],
          );
        },
      );

      final result = await generateImage(
        model: model,
        prompt: 'draw five icons',
        n: 5,
      );

      expect(
        model.receivedCallOptions.map((options) => options.n),
        [2, 2, 1],
      );
      expect(
        result.images.map((image) => image.bytes.toList()),
        [
          [1, 0],
          [1, 1],
          [2, 0],
          [2, 1],
          [3, 0],
        ],
      );
      expect(result.image.bytes.toList(), [1, 0]);
      expect(result.warnings, [
        const contracts.OtherWarning('warning-1'),
        const contracts.OtherWarning('warning-2'),
        const contracts.OtherWarning('warning-3'),
      ]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (test.image / test-image-model): warning-1',
        'Pigcode AI Warning (test.image / test-image-model): warning-2',
        'Pigcode AI Warning (test.image / test-image-model): warning-3',
      ]);
      expect(result.responses, responses);
      expect(result.providerMetadata, {
        'test': {
          'call1': 2,
          'call2': 2,
          'call3': 1,
          'images': [
            {'call': 1, 'i': 0},
            {'call': 1, 'i': 1},
            {'call': 2, 'i': 0},
            {'call': 2, 'i': 1},
            {'call': 3, 'i': 0},
          ],
        },
      });
      expect(
        result.usage,
        const contracts.ImageModelUsage(
          inputTokens: 6,
          outputTokens: 36,
          totalTokens: 66,
        ),
      );
    });

    test('多批 usage 只累加已知字段,全缺字段才保持 null', () async {
      final model = _ScriptedImageModel(
        maxImagesPerCallValue: 1,
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [
            Uint8List.fromList([index])
          ],
          warnings: const [],
          usage: index == 1
              ? const contracts.ImageModelUsage(
                  inputTokens: 3,
                  totalTokens: 5,
                )
              : const contracts.ImageModelUsage(
                  inputTokens: 4,
                  outputTokens: 2,
                ),
        ),
      );

      final result = await generateImage(
        model: model,
        prompt: 'draw two icons',
        n: 2,
      );

      expect(
        result.usage,
        const contracts.ImageModelUsage(
          inputTokens: 7,
          outputTokens: 2,
          totalTokens: 5,
        ),
      );
    });

    test('模型未声明 maxImagesPerCall 时默认每次生成 1 张', () async {
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [
            for (var i = 0; i < options.n; i++) Uint8List.fromList([index, i]),
          ],
          warnings: const [],
        ),
      );

      await generateImage(
        model: model,
        prompt: 'draw three icons',
        n: 3,
      );

      expect(
        model.receivedCallOptions.map((options) => options.n),
        [1, 1, 1],
      );
    });

    test('根据图片字节识别 mediaType 和 format', () async {
      final model = _ScriptedImageModel(
        maxImagesPerCallValue: 4,
        resultForCall: (options, index) async => contracts.ImageModelResult(
          images: [
            Uint8List.fromList(_pngBytes),
            Uint8List.fromList(_jpegBytes),
            Uint8List.fromList(_webpBytes),
            Uint8List.fromList([1, 2, 3]),
          ],
          warnings: const [],
        ),
      );

      final result = await generateImage(
        model: model,
        prompt: 'draw mixed image formats',
        n: 4,
      );

      expect(
        result.images.map((image) => image.mediaType),
        ['image/png', 'image/jpeg', 'image/webp', 'image/png'],
      );
      expect(
        result.images.map((image) => image.format),
        ['png', 'jpeg', 'webp', 'png'],
      );
    });

    test('空 images 抛 NoImageGeneratedError 并保留 responses', () async {
      const response = contracts.ResponseInfo(modelId: 'image-model');
      final model = _ScriptedImageModel(
        resultForCall: (options, index) async =>
            const contracts.ImageModelResult(
          images: [],
          warnings: [],
          response: response,
        ),
      );

      await expectLater(
        generateImage(model: model, prompt: 'draw nothing'),
        throwsA(
          isA<contracts.NoImageGeneratedError>()
              .having((error) => error.responses, 'responses', [response]),
        ),
      );
    });
  });
}

final class _ScriptedImageModel implements contracts.ImageModel {
  _ScriptedImageModel({
    required this.resultForCall,
    this.maxImagesPerCallValue,
  });

  final Future<contracts.ImageModelResult> Function(
    contracts.ImageModelCallOptions options,
    int callIndex,
  ) resultForCall;
  final int? maxImagesPerCallValue;
  final List<contracts.ImageModelCallOptions> receivedCallOptions = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.image';

  @override
  String get modelId => 'test-image-model';

  @override
  FutureOr<int?> get maxImagesPerCall => maxImagesPerCallValue;

  @override
  Future<contracts.ImageModelResult> doGenerate(
    contracts.ImageModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return resultForCall(options, receivedCallOptions.length);
  }
}

const _pngBytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const _jpegBytes = [0xff, 0xd8, 0xff, 0xe0];
const _webpBytes = [
  0x52,
  0x49,
  0x46,
  0x46,
  0,
  0,
  0,
  0,
  0x57,
  0x45,
  0x42,
  0x50,
];
