import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

typedef _ImageModelCallOptions = contracts.ImageModelCallOptions;
typedef _ImageModelResult = contracts.ImageModelResult;

void main() {
  group('wrapImageModel', () {
    test('reports v4 even when the wrapped model advertises an older version',
        () {
      final wrapped = wrapImageModel(
        _LegacyVersionImageModel(),
        const contracts.ImageModelMiddleware(),
      );

      expect(wrapped.specificationVersion, contracts.imageModelSpecVersion);
    });

    test('transformParams changes values but preserves other fields', () async {
      final scripted = _ScriptedImageModel(
        resultForCall: (options) async => contracts.ImageModelResult(
          images: [
            Uint8List.fromList([1])
          ],
          warnings: const [],
        ),
      );
      final controller = contracts.CancellationController();

      final wrapped = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          transformParams: ({
            required contracts.ImageModelCallOptions params,
            required contracts.ImageModel model,
          }) async =>
              contracts.ImageModelCallOptions(
            prompt: '${params.prompt} with color',
            n: 2,
            size: params.size,
            aspectRatio: params.aspectRatio,
            seed: params.seed,
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );

      await wrapped.doGenerate(contracts.ImageModelCallOptions(
        prompt: 'draw icon',
        n: 1,
        size: '1024x1024',
        aspectRatio: '1:1',
        seed: 42,
        headers: const {'x-custom': 'v'},
        providerOptions: const {
          'openai': {'quality': 'high'},
        },
        cancellation: controller.signal,
      ));

      final seen = scripted.receivedCallOptions.single;
      expect(seen.prompt, 'draw icon with color');
      expect(seen.n, 2);
      expect(seen.size, '1024x1024');
      expect(seen.aspectRatio, '1:1');
      expect(seen.seed, 42);
      expect(seen.headers, {'x-custom': 'v'});
      expect(seen.providerOptions, {
        'openai': {'quality': 'high'},
      });
      expect(seen.cancellation, same(controller.signal));
    });

    test('wrapGenerate intercepts and can short-circuit doGenerate', () async {
      final scripted = _ScriptedImageModel(
        resultForCall: (options) async => contracts.ImageModelResult(
          images: [
            Uint8List.fromList([1])
          ],
          warnings: const [],
        ),
      );

      final wrapped = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          wrapGenerate: ({
            required contracts.ImageModelDoGenerate doGenerate,
            required contracts.ImageModelCallOptions params,
            required contracts.ImageModel model,
          }) async =>
              contracts.ImageModelResult(
            images: [
              Uint8List.fromList([9])
            ],
            warnings: const [],
          ),
        ),
      );

      final result = await wrapped.doGenerate(
        const contracts.ImageModelCallOptions(prompt: 'draw icon'),
      );

      expect(result.images.single.toList(), [9]);
      expect(scripted.callCount, 0);
    });

    test('override hooks apply provider/modelId/capabilities', () async {
      final scripted = _ScriptedImageModel(
        maxImagesPerCallValue: 8,
        resultForCall: (options) async =>
            const contracts.ImageModelResult(images: [], warnings: []),
      );

      final wrapped = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          overrideProvider: (m) => 'wrapped-${m.provider}',
          overrideModelId: (m) => 'wrapped-${m.modelId}',
          overrideMaxImagesPerCall: (m) async => 2,
        ),
      );

      expect(wrapped.provider, 'wrapped-scripted-image');
      expect(wrapped.modelId, 'wrapped-image-1');
      expect(await wrapped.maxImagesPerCall, 2);
    });

    test('overrideMaxImagesPerCall preserves null as no declared limit',
        () async {
      final scripted = _ScriptedImageModel(
        maxImagesPerCallValue: 8,
        resultForCall: (options) async =>
            const contracts.ImageModelResult(images: [], warnings: []),
      );

      final wrapped = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          overrideMaxImagesPerCall: (m) => null,
        ),
      );

      expect(await wrapped.maxImagesPerCall, isNull);
    });

    test('explicit providerId/modelId overrides middleware identity hooks', () {
      final scripted = _ScriptedImageModel(
        resultForCall: (options) async =>
            const contracts.ImageModelResult(images: [], warnings: []),
      );

      final wrapped = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          overrideProvider: (m) => 'wrapped-${m.provider}',
          overrideModelId: (m) => 'wrapped-${m.modelId}',
        ),
        providerId: 'explicit-provider',
        modelId: 'explicit-model',
      );

      expect(wrapped.provider, 'explicit-provider');
      expect(wrapped.modelId, 'explicit-model');
    });

    test(
        'nested wrapImageModel: on a conflicting field, the inner '
        '(last-wrapped, closest-to-model) transformParams wins', () async {
      final scripted = _ScriptedImageModel(
        resultForCall: (options) async => contracts.ImageModelResult(
          images: [
            Uint8List.fromList([1])
          ],
          warnings: const [],
        ),
      );

      final inner = wrapImageModel(
        scripted,
        contracts.ImageModelMiddleware(
          transformParams: ({
            required contracts.ImageModelCallOptions params,
            required contracts.ImageModel model,
          }) async =>
              contracts.ImageModelCallOptions(
            prompt: 'inner',
            n: params.n,
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );
      final outer = wrapImageModel(
        inner,
        contracts.ImageModelMiddleware(
          transformParams: ({
            required contracts.ImageModelCallOptions params,
            required contracts.ImageModel model,
          }) async =>
              contracts.ImageModelCallOptions(
            prompt: 'outer',
            n: params.n,
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );

      await outer.doGenerate(
        const contracts.ImageModelCallOptions(prompt: 'base'),
      );

      expect(scripted.receivedCallOptions.single.prompt, 'inner');
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
  ) resultForCall;
  final int? maxImagesPerCallValue;
  final List<contracts.ImageModelCallOptions> receivedCallOptions = [];
  int callCount = 0;

  @override
  String get specificationVersion => contracts.imageModelSpecVersion;

  @override
  String get provider => 'scripted-image';

  @override
  String get modelId => 'image-1';

  @override
  FutureOr<int?> get maxImagesPerCall => maxImagesPerCallValue;

  @override
  Future<contracts.ImageModelResult> doGenerate(
    contracts.ImageModelCallOptions options,
  ) async {
    callCount++;
    receivedCallOptions.add(options);
    return resultForCall(options);
  }
}

final class _LegacyVersionImageModel implements contracts.ImageModel {
  @override
  String get specificationVersion => 'v3';

  @override
  String get provider => 'legacy';

  @override
  String get modelId => 'legacy-model';

  @override
  FutureOr<int?> get maxImagesPerCall => null;

  @override
  Future<_ImageModelResult> doGenerate(
    _ImageModelCallOptions options,
  ) {
    throw UnsupportedError('doGenerate not needed in specification test');
  }
}
