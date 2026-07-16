import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('RerankingModelCallOptions', () {
    test('holds text documents and request options', () {
      final controller = CancellationController();
      final options = RerankingModelCallOptions(
        documents: const RerankingDocumentsText(['a', 'b']),
        query: 'rain',
        topN: 1,
        headers: const {'x-custom': 'v'},
        providerOptions: const {
          'cohere': {
            'rankFields': ['title']
          },
        },
        cancellation: controller.signal,
      );

      expect(options.documents, const RerankingDocumentsText(['a', 'b']));
      expect(options.query, 'rain');
      expect(options.topN, 1);
      expect(options.headers, {'x-custom': 'v'});
      expect(options.providerOptions, {
        'cohere': {
          'rankFields': ['title']
        },
      });
      expect(options.cancellation, same(controller.signal));
    });

    test('equality ignores cancellation identity', () {
      final a = RerankingModelCallOptions(
        documents: const RerankingDocumentsText(['a']),
        query: 'q',
        cancellation: CancellationController().signal,
      );
      final b = RerankingModelCallOptions(
        documents: const RerankingDocumentsText(['a']),
        query: 'q',
        cancellation: CancellationController().signal,
      );

      expect(a, b);
    });
  });

  group('RerankingModelResult', () {
    test('holds ranking, warnings, provider metadata, and response', () {
      final response = ResponseInfo(
        id: 'resp-1',
        timestamp: DateTime.utc(2026, 1, 1),
        modelId: 'rerank-model',
        headers: const {'x-resp': 'v'},
        body: const {'ok': true},
      );
      final result = RerankingModelResult(
        ranking: const [
          RerankingModelRanking(index: 2, relevanceScore: 0.9),
        ],
        warnings: const [OtherWarning('test warning')],
        providerMetadata: const {
          'cohere': {'requestId': 'req-1'},
        },
        response: response,
      );

      expect(result.ranking.single.index, 2);
      expect(result.ranking.single.relevanceScore, 0.9);
      expect(result.warnings, [const OtherWarning('test warning')]);
      expect(result.providerMetadata, {
        'cohere': {'requestId': 'req-1'},
      });
      expect(result.response, response);
    });
  });
}
