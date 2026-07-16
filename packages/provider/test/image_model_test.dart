import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('ImageModelCallOptions', () {
    test('holds prompt and optional fields', () {
      final signal = CancellationController().signal;
      final options = ImageModelCallOptions(
        prompt: 'A tiny ceramic teapot',
        n: 2,
        size: '1024x1024',
        aspectRatio: '1:1',
        seed: 42,
        headers: const {'x-a': '1'},
        providerOptions: const {
          'openai': {'quality': 'high'},
        },
        cancellation: signal,
      );

      expect(options.prompt, 'A tiny ceramic teapot');
      expect(options.n, 2);
      expect(options.size, '1024x1024');
      expect(options.aspectRatio, '1:1');
      expect(options.seed, 42);
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'openai': {'quality': 'high'},
      });
      expect(options.cancellation, same(signal));
    });

    test('equality ignores cancellation identity', () {
      final a = ImageModelCallOptions(
        prompt: 'hello',
        cancellation: CancellationController().signal,
      );
      final b = ImageModelCallOptions(
        prompt: 'hello',
        cancellation: CancellationController().signal,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ImageModelResult', () {
    test('carries images, warnings, usage, metadata, request, and response',
        () {
      final image = Uint8List.fromList([1, 2, 3]);
      final timestamp = DateTime.utc(2026);
      final result = ImageModelResult(
        images: [image],
        warnings: const [OtherWarning('note')],
        usage: const ImageModelUsage(inputTokens: 1, outputTokens: 2),
        providerMetadata: const {
          'openai': {
            'images': [
              {'revisedPrompt': 'A tiny teapot'}
            ],
          },
        },
        request: const RequestInfo(body: 'json'),
        response: ResponseInfo(
          timestamp: timestamp,
          modelId: 'gpt-image-1',
          headers: const {'x-request-id': 'req-1'},
          body: {'ok': true},
        ),
      );

      expect(result.images, [image]);
      expect(result.warnings.single, isA<OtherWarning>());
      expect(result.usage.inputTokens, 1);
      expect(result.usage.outputTokens, 2);
      expect(result.usage.totalTokens, isNull);
      expect(result.providerMetadata, {
        'openai': {
          'images': [
            {'revisedPrompt': 'A tiny teapot'}
          ],
        },
      });
      expect(result.request?.body, 'json');
      expect(result.response?.timestamp, timestamp);
    });
  });

  group('ImageModel interface shape', () {
    test('a minimal fake implementation satisfies the interface', () async {
      final model = _FakeImageModel();

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'fake.image');
      expect(model.modelId, 'fake-model');
      expect(await model.maxImagesPerCall, 1);

      final result = await model.doGenerate(
        const ImageModelCallOptions(prompt: 'hello'),
      );
      expect(result.images.single, [1, 2, 3]);
    });
  });
}

final class _FakeImageModel implements ImageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.image';

  @override
  String get modelId => 'fake-model';

  @override
  FutureOr<int?> get maxImagesPerCall => 1;

  @override
  Future<ImageModelResult> doGenerate(
    ImageModelCallOptions options,
  ) async {
    return ImageModelResult(
      images: [
        Uint8List.fromList([1, 2, 3])
      ],
      warnings: const [],
    );
  }
}
