import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_embedding_model.dart';

typedef _EmbeddingModelCallOptions = provider.EmbeddingModelCallOptions;
typedef _EmbeddingModelResult = provider.EmbeddingModelResult;

void main() {
  group('wrapEmbeddingModel', () {
    test('reports v4 even when the wrapped model advertises an older version',
        () {
      final wrapped = wrapEmbeddingModel(
        _LegacyVersionEmbeddingModel(),
        const provider.EmbeddingModelMiddleware(),
      );

      expect(wrapped.specificationVersion, provider.embeddingModelSpecVersion);
    });

    test('transformParams changes values but preserves other fields', () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
        ],
      );
      final controller = provider.CancellationController();

      final wrapped = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
          transformParams: ({
            required provider.EmbeddingModelCallOptions params,
            required provider.EmbeddingModel model,
          }) async =>
              provider.EmbeddingModelCallOptions(
            values: [...params.values, 'extra'],
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );

      await wrapped.doEmbed(provider.EmbeddingModelCallOptions(
        values: const ['base'],
        headers: const {'x-custom': 'v'},
        providerOptions: const {
          'openai': {'dimensions': 256},
        },
        cancellation: controller.signal,
      ));

      final seen = scripted.receivedCallOptions.single;
      expect(seen.values, ['base', 'extra']);
      expect(seen.headers, {'x-custom': 'v'});
      expect(seen.providerOptions, {
        'openai': {'dimensions': 256},
      });
      expect(seen.cancellation, same(controller.signal));
    });

    test('wrapEmbed intercepts and can short-circuit doEmbed', () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
      );

      final wrapped = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
          wrapEmbed: ({
            required provider.EmbeddingModelDoEmbed doEmbed,
            required provider.EmbeddingModelCallOptions params,
            required provider.EmbeddingModel model,
          }) async =>
              const provider.EmbeddingModelResult(
            embeddings: [
              [9.0],
            ],
            warnings: [],
          ),
        ),
      );

      final result = await wrapped.doEmbed(
        const provider.EmbeddingModelCallOptions(values: ['hello']),
      );

      expect(result.embeddings, [
        [9.0],
      ]);
      expect(scripted.callCount, 0);
    });

    test('override hooks apply provider/modelId/capabilities', () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        maxEmbeddingsPerCall: 8,
        supportsParallelCalls: false,
        batches: const [],
      );

      final wrapped = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
          overrideProvider: (m) => 'wrapped-${m.provider}',
          overrideModelId: (m) => 'wrapped-${m.modelId}',
          overrideMaxEmbeddingsPerCall: (m) async => 2,
          overrideSupportsParallelCalls: (m) => true,
        ),
      );

      expect(wrapped.provider, 'wrapped-scripted-embedding');
      expect(wrapped.modelId, 'wrapped-embed-1');
      expect(await wrapped.maxEmbeddingsPerCall, 2);
      expect(await wrapped.supportsParallelCalls, isTrue);
    });

    test('overrideMaxEmbeddingsPerCall preserves null as unlimited', () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        maxEmbeddingsPerCall: 8,
        batches: const [],
      );

      final wrapped = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
          overrideMaxEmbeddingsPerCall: (m) => null,
        ),
      );

      expect(await wrapped.maxEmbeddingsPerCall, isNull);
    });

    test('explicit providerId/modelId overrides middleware identity hooks', () {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: const [],
      );

      final wrapped = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
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
        'nested wrapEmbeddingModel: on a conflicting field, the inner '
        '(last-wrapped, closest-to-model) transformParams wins', () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
      );

      final inner = wrapEmbeddingModel(
        scripted,
        provider.EmbeddingModelMiddleware(
          transformParams: ({
            required provider.EmbeddingModelCallOptions params,
            required provider.EmbeddingModel model,
          }) async =>
              provider.EmbeddingModelCallOptions(
            values: const ['inner'],
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );
      final outer = wrapEmbeddingModel(
        inner,
        provider.EmbeddingModelMiddleware(
          transformParams: ({
            required provider.EmbeddingModelCallOptions params,
            required provider.EmbeddingModel model,
          }) async =>
              provider.EmbeddingModelCallOptions(
            values: const ['outer'],
            headers: params.headers,
            providerOptions: params.providerOptions,
            cancellation: params.cancellation,
          ),
        ),
      );

      await outer.doEmbed(
        const provider.EmbeddingModelCallOptions(values: ['base']),
      );

      expect(scripted.receivedCallOptions.single.values, ['inner']);
    });
  });
}

final class _LegacyVersionEmbeddingModel implements provider.EmbeddingModel {
  @override
  String get specificationVersion => 'v3';

  @override
  String get provider => 'legacy';

  @override
  String get modelId => 'legacy-model';

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => null;

  @override
  FutureOr<bool> get supportsParallelCalls => true;

  @override
  Future<_EmbeddingModelResult> doEmbed(
    _EmbeddingModelCallOptions options,
  ) {
    throw UnsupportedError('doEmbed not needed in specification test');
  }
}
