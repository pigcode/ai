import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/logging.dart';
import '../support/scripted_embedding_model.dart';

void main() {
  group('embed', () {
    test('单值往返:embedding 取 embeddings[0]', () async {
      final model = ScriptedEmbeddingModel(
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [0.1, 0.2, 0.3],
          ]),
        ],
      );

      final result = await embed(model: model, value: 'hello');

      expect(result.value, 'hello');
      expect(result.embedding, [0.1, 0.2, 0.3]);
      expect(result.usage, const provider.EmbeddingUsage());
      expect(result.warnings, isEmpty);
    });

    test('providerOptions/headers/cancellation 透传给 doEmbed', () async {
      final model = ScriptedEmbeddingModel(
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
      );
      final controller = provider.CancellationController();

      await embed(
        model: model,
        value: 'hello',
        providerOptions: const {
          'openai': {'dimensions': 256},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(received.values, ['hello']);
      expect(received.providerOptions, {
        'openai': {'dimensions': 256},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('usage/warnings/providerMetadata/response 原样透传', () async {
      final records = captureWarningLogs();
      final model = ScriptedEmbeddingModel(
        batches: [
          ScriptedEmbeddingBatch(
            embeddings: [
              [1.0],
            ],
            usage: const provider.EmbeddingUsage(tokens: 7),
            warnings: const [provider.OtherWarning('test warning')],
            providerMetadata: const {
              'openai': {'requestId': 'req-1'},
            },
            response: const provider.EmbeddingResponseInfo(
              headers: {'x-resp': 'v'},
              body: {'ok': true},
            ),
          ),
        ],
      );

      final result = await embed(model: model, value: 'hello');

      expect(result.usage.tokens, 7);
      expect(result.warnings, [const provider.OtherWarning('test warning')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning '
            '(scripted-embedding-provider / scripted-embedding-model): '
            'test warning',
      ]);
      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
      expect(result.response?.headers, {'x-resp': 'v'});
      expect(result.response?.body, {'ok': true});
    });

    test('doEmbed 返回空 embeddings 时抛出可诊断的 StateError', () async {
      final model = ScriptedEmbeddingModel(
        batches: [ScriptedEmbeddingBatch(embeddings: const [])],
      );

      expect(
        () => embed(model: model, value: 'hello'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
