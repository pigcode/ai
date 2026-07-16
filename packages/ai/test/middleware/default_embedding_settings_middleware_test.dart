import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_embedding_model.dart';

void main() {
  group('defaultEmbeddingSettingsMiddleware', () {
    test('fills missing embedding metadata and deeply merges options',
        () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
      );
      final controller = provider.CancellationController();

      final wrapped = ai.wrapEmbeddingModel(
        scripted,
        ai.defaultEmbeddingSettingsMiddleware(
          settings: const ai.DefaultEmbeddingModelSettings(
            headers: {
              'x-default': 'default',
              'x-shared': 'default',
            },
            providerOptions: {
              'openai': {
                'outer': {
                  'default': true,
                  'shared': 'default',
                  'array': [1, 2],
                },
                'defaultOnly': 'yes',
              },
              'custom': {'enabled': true},
            },
          ),
        ),
      );

      await wrapped.doEmbed(provider.EmbeddingModelCallOptions(
        values: const ['hello'],
        headers: const {
          'x-shared': 'call',
          'x-call': 'call',
        },
        providerOptions: const {
          'openai': {
            'outer': {
              'shared': 'call',
              'array': [3],
              'callOnly': true,
            },
            'callOnlyTop': 'yes',
          },
        },
        cancellation: controller.signal,
      ));

      final seen = scripted.receivedCallOptions.single;
      expect(seen.values, ['hello']);
      expect(seen.cancellation, same(controller.signal));
      expect(seen.headers, {
        'x-default': 'default',
        'x-shared': 'call',
        'x-call': 'call',
      });
      expect(seen.providerOptions, {
        'openai': {
          'outer': {
            'default': true,
            'shared': 'call',
            'array': [3],
            'callOnly': true,
          },
          'defaultOnly': 'yes',
          'callOnlyTop': 'yes',
        },
        'custom': {'enabled': true},
      });
    });

    test('leaves metadata null when neither defaults nor params provide it',
        () async {
      final scripted = ScriptedEmbeddingModel(
        provider: 'scripted-embedding',
        modelId: 'embed-1',
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
      );
      final wrapped = ai.wrapEmbeddingModel(
        scripted,
        ai.defaultEmbeddingSettingsMiddleware(
          settings: const ai.DefaultEmbeddingModelSettings(),
        ),
      );

      await wrapped.doEmbed(
        const provider.EmbeddingModelCallOptions(values: ['hello']),
      );

      final seen = scripted.receivedCallOptions.single;
      expect(seen.headers, isNull);
      expect(seen.providerOptions, isNull);
    });
  });
}
