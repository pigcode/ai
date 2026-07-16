import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

/// 供中间件签名测试使用的最小 fake 模型：不触网，仅承载 provider/modelId。
final class _FakeLanguageModel implements LanguageModel {
  const _FakeLanguageModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) {
    throw UnsupportedError('doGenerate not needed in middleware shape test');
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) {
    throw UnsupportedError('doStream not needed in middleware shape test');
  }
}

/// 供 image 中间件签名测试使用的最小 fake 模型。
final class _FakeImageModel implements ImageModel {
  const _FakeImageModel({required this.provider, required this.modelId});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<int?> get maxImagesPerCall => 4;

  @override
  Future<ImageModelResult> doGenerate(ImageModelCallOptions options) {
    throw UnsupportedError('doGenerate not needed in middleware shape test');
  }
}

void main() {
  const model = _FakeLanguageModel(provider: 'fake', modelId: 'm-1');
  const LanguageModelPrompt prompt = [];
  const params = LanguageModelCallOptions(prompt: prompt);
  const imageModel = _FakeImageModel(provider: 'fake-image', modelId: 'i-1');
  const imageParams = ImageModelCallOptions(prompt: 'draw icon');

  group('LanguageModelMiddleware', () {
    test('construct with only transformParams set leaves other hooks null', () {
      final middleware = LanguageModelMiddleware(
        transformParams: ({
          required bool stream,
          required LanguageModelCallOptions params,
          required LanguageModel model,
        }) async =>
            params.copyWith(temperature: 0.5),
      );

      expect(middleware.transformParams, isNotNull);
      expect(middleware.overrideProvider, isNull);
      expect(middleware.overrideModelId, isNull);
      expect(middleware.overrideSupportedUrls, isNull);
      expect(middleware.wrapGenerate, isNull);
      expect(middleware.wrapStream, isNull);
    });

    test('a fully-empty middleware has every hook null', () {
      const middleware = LanguageModelMiddleware();

      expect(middleware.transformParams, isNull);
      expect(middleware.overrideProvider, isNull);
      expect(middleware.overrideModelId, isNull);
      expect(middleware.overrideSupportedUrls, isNull);
      expect(middleware.wrapGenerate, isNull);
      expect(middleware.wrapStream, isNull);
    });

    test('invoking the provided transformParams hook works', () async {
      final middleware = LanguageModelMiddleware(
        transformParams: ({
          required bool stream,
          required LanguageModelCallOptions params,
          required LanguageModel model,
        }) async =>
            params.copyWith(temperature: stream ? 0.1 : 0.9),
      );

      final transformed = await middleware.transformParams!(
        stream: false,
        params: params,
        model: model,
      );

      expect(transformed.temperature, 0.9);
      expect(transformed.prompt, same(params.prompt));
    });

    test('invoking the provided override hooks works', () async {
      final middleware = LanguageModelMiddleware(
        overrideProvider: (m) => 'wrapped-${m.provider}',
        overrideModelId: (m) => 'wrapped-${m.modelId}',
        overrideSupportedUrls: (m) => {
          'image/*': [RegExp(r'^https://cdn\.example\.com/')],
        },
      );

      expect(middleware.overrideProvider!(model), 'wrapped-fake');
      expect(middleware.overrideModelId!(model), 'wrapped-m-1');

      final urls = await middleware.overrideSupportedUrls!(model);
      expect(urls.keys, contains('image/*'));
    });

    test('invoking wrapGenerate hook delegates to doGenerate', () async {
      const inner = LanguageModelGenerateResult(
        content: [],
        finishReason: LanguageModelFinishReason(FinishReasonType.stop),
        usage: LanguageModelUsage(
          inputTokens: InputTokens(),
          outputTokens: OutputTokens(),
        ),
        warnings: [],
      );

      final middleware = LanguageModelMiddleware(
        wrapGenerate: ({
          required LanguageModelDoGenerate doGenerate,
          required LanguageModelDoStream doStream,
          required LanguageModelCallOptions params,
          required LanguageModel model,
        }) async =>
            doGenerate(),
      );

      final result = await middleware.wrapGenerate!(
        doGenerate: () async => inner,
        doStream: () async =>
            throw UnsupportedError('doStream unused in this path'),
        params: params,
        model: model,
      );

      expect(result, same(inner));
    });

    test('invoking wrapStream hook delegates to doStream', () async {
      final inner = LanguageModelStreamResult(
        stream: const Stream<LanguageModelStreamPart>.empty(),
      );

      final middleware = LanguageModelMiddleware(
        wrapStream: ({
          required LanguageModelDoGenerate doGenerate,
          required LanguageModelDoStream doStream,
          required LanguageModelCallOptions params,
          required LanguageModel model,
        }) async =>
            doStream(),
      );

      final result = await middleware.wrapStream!(
        doGenerate: () async =>
            throw UnsupportedError('doGenerate unused in this path'),
        doStream: () async => inner,
        params: params,
        model: model,
      );

      expect(result, same(inner));
    });
  });

  group('ImageModelMiddleware', () {
    test('construct with only transformParams set leaves other hooks null', () {
      final middleware = ImageModelMiddleware(
        transformParams: ({
          required ImageModelCallOptions params,
          required ImageModel model,
        }) async =>
            ImageModelCallOptions(prompt: '${params.prompt} in blue'),
      );

      expect(middleware.transformParams, isNotNull);
      expect(middleware.overrideProvider, isNull);
      expect(middleware.overrideModelId, isNull);
      expect(middleware.overrideMaxImagesPerCall, isNull);
      expect(middleware.wrapGenerate, isNull);
    });

    test('a fully-empty middleware has every hook null', () {
      const middleware = ImageModelMiddleware();

      expect(middleware.transformParams, isNull);
      expect(middleware.overrideProvider, isNull);
      expect(middleware.overrideModelId, isNull);
      expect(middleware.overrideMaxImagesPerCall, isNull);
      expect(middleware.wrapGenerate, isNull);
    });

    test('invoking the provided transformParams hook works', () async {
      final middleware = ImageModelMiddleware(
        transformParams: ({
          required ImageModelCallOptions params,
          required ImageModel model,
        }) async =>
            ImageModelCallOptions(
          prompt: params.prompt,
          n: 3,
          size: params.size,
          aspectRatio: params.aspectRatio,
          seed: params.seed,
          headers: params.headers,
          providerOptions: params.providerOptions,
          cancellation: params.cancellation,
        ),
      );

      final transformed = await middleware.transformParams!(
        params: imageParams,
        model: imageModel,
      );

      expect(transformed.n, 3);
      expect(transformed.prompt, imageParams.prompt);
    });

    test('invoking the provided override hooks works', () async {
      final middleware = ImageModelMiddleware(
        overrideProvider: (m) => 'wrapped-${m.provider}',
        overrideModelId: (m) => 'wrapped-${m.modelId}',
        overrideMaxImagesPerCall: (m) async => 2,
      );

      expect(middleware.overrideProvider!(imageModel), 'wrapped-fake-image');
      expect(middleware.overrideModelId!(imageModel), 'wrapped-i-1');
      expect(await middleware.overrideMaxImagesPerCall!(imageModel), 2);
    });

    test('invoking wrapGenerate hook delegates to doGenerate', () async {
      const inner = ImageModelResult(images: [], warnings: []);

      final middleware = ImageModelMiddleware(
        wrapGenerate: ({
          required ImageModelDoGenerate doGenerate,
          required ImageModelCallOptions params,
          required ImageModel model,
        }) async =>
            doGenerate(),
      );

      final result = await middleware.wrapGenerate!(
        doGenerate: () async => inner,
        params: imageParams,
        model: imageModel,
      );

      expect(result, same(inner));
    });
  });
}
