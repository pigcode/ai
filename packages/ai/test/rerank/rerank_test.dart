import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('rerank', () {
    test('passes string documents to doRerank and maps ranking', () async {
      final records = captureWarningLogs();
      final model = _ScriptedRerankingModel(
        result: const contracts.RerankingModelResult(
          ranking: [
            contracts.RerankingModelRanking(index: 2, relevanceScore: 0.9),
            contracts.RerankingModelRanking(index: 0, relevanceScore: 0.8),
          ],
          warnings: [contracts.OtherWarning('rerank note')],
          providerMetadata: {
            'test': {'requestId': 'req-1'},
          },
          response: contracts.ResponseInfo(
            id: 'resp-1',
            modelId: 'rerank-response-model',
          ),
        ),
      );

      final result = await rerank(
        model: model,
        documents: const [
          'sunny day at the beach',
          'rainy day in the city',
          'cloudy day in the mountains',
        ],
        query: 'weather',
        topN: 2,
        providerOptions: const {
          'test': {'truncate': 'END'},
        },
        headers: const {'x-custom': 'v'},
      );

      expect(model.calls, hasLength(1));
      final call = model.calls.single;
      expect(
        call.documents,
        const contracts.RerankingDocumentsText([
          'sunny day at the beach',
          'rainy day in the city',
          'cloudy day in the mountains',
        ]),
      );
      expect(call.query, 'weather');
      expect(call.topN, 2);
      expect(call.providerOptions, {
        'test': {'truncate': 'END'},
      });
      expect(call.headers, {'x-custom': 'v'});

      expect(result.originalDocuments, [
        'sunny day at the beach',
        'rainy day in the city',
        'cloudy day in the mountains',
      ]);
      expect(result.rerankedDocuments, [
        'cloudy day in the mountains',
        'sunny day at the beach',
      ]);
      expect(result.ranking, [
        const RerankRanking(
          originalIndex: 2,
          score: 0.9,
          document: 'cloudy day in the mountains',
        ),
        const RerankRanking(
          originalIndex: 0,
          score: 0.8,
          document: 'sunny day at the beach',
        ),
      ]);
      expect(result.providerMetadata, {
        'test': {'requestId': 'req-1'},
      });
      expect(result.response.id, 'resp-1');
      expect(result.response.modelId, 'rerank-response-model');
      expect(result.warnings, [const contracts.OtherWarning('rerank note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (test / rerank-model): rerank note',
      ]);
    });

    test('passes JSON object documents to doRerank', () async {
      final model = _ScriptedRerankingModel(
        result: const contracts.RerankingModelResult(
          ranking: [
            contracts.RerankingModelRanking(index: 1, relevanceScore: 0.7),
          ],
          warnings: [],
        ),
      );
      const documents = [
        <String, Object?>{'id': '1', 'title': 'Sunny'},
        <String, Object?>{'id': '2', 'title': 'Rainy'},
      ];

      final result = await rerank(
        model: model,
        documents: documents,
        query: 'rain',
      );

      expect(
        model.calls.single.documents,
        const contracts.RerankingDocumentsObject(documents),
      );
      expect(result.rerankedDocuments, [
        {'id': '2', 'title': 'Rainy'},
      ]);
    });

    test('empty documents returns empty result without calling model',
        () async {
      final model = _ScriptedRerankingModel(
        result: const contracts.RerankingModelResult(
          ranking: [],
          warnings: [],
        ),
      );

      final result = await rerank<String>(
        model: model,
        documents: const [],
        query: 'rain',
      );

      expect(model.calls, isEmpty);
      expect(result.originalDocuments, isEmpty);
      expect(result.rerankedDocuments, isEmpty);
      expect(result.ranking, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.response.modelId, 'rerank-model');
      expect(result.response.timestamp, isNotNull);
    });

    test('rejects mixed document types', () async {
      final model = _ScriptedRerankingModel(
        result: const contracts.RerankingModelResult(
          ranking: [],
          warnings: [],
        ),
      );

      await expectLater(
        rerank<Object>(
          model: model,
          documents: const [
            'text',
            <String, Object?>{'id': '1'},
          ],
          query: 'rain',
        ),
        throwsA(isA<contracts.InvalidArgumentError>()),
      );
    });
  });
}

final class _ScriptedRerankingModel implements contracts.RerankingModel {
  _ScriptedRerankingModel({required this.result});

  final contracts.RerankingModelResult result;
  final List<contracts.RerankingModelCallOptions> calls = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test';

  @override
  String get modelId => 'rerank-model';

  @override
  Future<contracts.RerankingModelResult> doRerank(
    contracts.RerankingModelCallOptions options,
  ) async {
    calls.add(options);
    return result;
  }
}
