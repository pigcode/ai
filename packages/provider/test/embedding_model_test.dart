import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('EmbeddingModelCallOptions', () {
    test('holds values and optional fields', () {
      const options = EmbeddingModelCallOptions(
        values: ['hello', 'world'],
        headers: {'x-a': '1'},
        providerOptions: {
          'openai': {'dimensions': 256},
        },
      );

      expect(options.values, ['hello', 'world']);
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'openai': {'dimensions': 256},
      });
      expect(options.cancellation, isNull);
    });

    test('equality ignores cancellation identity', () {
      final controllerA = CancellationController();
      final controllerB = CancellationController();

      const values = ['a', 'b'];
      final withA = EmbeddingModelCallOptions(
        values: values,
        cancellation: controllerA.signal,
      );
      final withB = EmbeddingModelCallOptions(
        values: values,
        cancellation: controllerB.signal,
      );
      const withNone = EmbeddingModelCallOptions(values: values);

      expect(withA, equals(withB));
      expect(withA, equals(withNone));
      expect(withA.hashCode, equals(withB.hashCode));
    });

    test('differs when values differ', () {
      const a = EmbeddingModelCallOptions(values: ['a']);
      const b = EmbeddingModelCallOptions(values: ['b']);
      expect(a, isNot(equals(b)));
    });

    test('preserves cancellation identity via direct field access', () {
      final signal = CancellationController().signal;
      final options = EmbeddingModelCallOptions(
        values: const ['a'],
        cancellation: signal,
      );
      expect(options.cancellation, same(signal));
    });
  });

  group('EmbeddingUsage', () {
    test('defaults tokens to null', () {
      const usage = EmbeddingUsage();
      expect(usage.tokens, isNull);
    });

    test('equality by tokens value', () {
      expect(
        const EmbeddingUsage(tokens: 10),
        equals(const EmbeddingUsage(tokens: 10)),
      );
      expect(
        const EmbeddingUsage(tokens: 10),
        isNot(equals(const EmbeddingUsage(tokens: 20))),
      );
      expect(
        const EmbeddingUsage(),
        isNot(equals(const EmbeddingUsage(tokens: 0))),
      );
    });
  });

  group('EmbeddingResponseInfo', () {
    test('holds headers and body, equatable by value', () {
      const a = EmbeddingResponseInfo(
        headers: {'x-request-id': 'r1'},
        body: {'raw': true},
      );
      const b = EmbeddingResponseInfo(
        headers: {'x-request-id': 'r1'},
        body: {'raw': true},
      );
      expect(a, equals(b));
      expect(a.headers, {'x-request-id': 'r1'});
    });

    test('all fields optional', () {
      const info = EmbeddingResponseInfo();
      expect(info.headers, isNull);
      expect(info.body, isNull);
    });
  });

  group('EmbeddingModelResult', () {
    test('embeddings preserve order and default usage/response', () {
      const result = EmbeddingModelResult(
        embeddings: <Embedding>[
          [0.1, 0.2],
          [0.3, 0.4],
        ],
        warnings: <Warning>[],
      );

      expect(result.embeddings, hasLength(2));
      expect(result.embeddings[0], [0.1, 0.2]);
      expect(result.embeddings[1], [0.3, 0.4]);
      expect(result.usage, const EmbeddingUsage());
      expect(result.providerMetadata, isNull);
      expect(result.response, isNull);
    });

    test('carries warnings, usage, providerMetadata, response', () {
      const result = EmbeddingModelResult(
        embeddings: <Embedding>[
          [1.0],
        ],
        usage: EmbeddingUsage(tokens: 42),
        warnings: <Warning>[UnsupportedWarning('dimensions')],
        providerMetadata: {
          'openai': {'requestId': 'r1'},
        },
        response: EmbeddingResponseInfo(headers: {'x': 'y'}),
      );

      expect(result.usage.tokens, 42);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
      expect(result.providerMetadata, {
        'openai': {'requestId': 'r1'},
      });
      expect(result.response?.headers, {'x': 'y'});
    });

    test('equality by all value fields', () {
      const a = EmbeddingModelResult(
        embeddings: <Embedding>[
          [1.0, 2.0],
        ],
        usage: EmbeddingUsage(tokens: 5),
        warnings: <Warning>[],
      );
      const b = EmbeddingModelResult(
        embeddings: <Embedding>[
          [1.0, 2.0],
        ],
        usage: EmbeddingUsage(tokens: 5),
        warnings: <Warning>[],
      );
      expect(a, equals(b));
    });
  });

  group('EmbeddingModel interface shape', () {
    test('a minimal fake implementation satisfies the interface', () async {
      final model = _FakeEmbeddingModel();

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'fake.embedding');
      expect(model.modelId, 'fake-model');
      expect(await model.maxEmbeddingsPerCall, 2048);
      expect(await model.supportsParallelCalls, true);

      final result = await model.doEmbed(
        const EmbeddingModelCallOptions(values: ['hi']),
      );
      expect(result.embeddings, hasLength(1));
    });
  });
}

/// 最小 fake 实现,仅用于证明接口形状可被实现且方法签名如预期。
final class _FakeEmbeddingModel implements EmbeddingModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.embedding';

  @override
  String get modelId => 'fake-model';

  @override
  FutureOr<int?> get maxEmbeddingsPerCall => 2048;

  @override
  FutureOr<bool> get supportsParallelCalls => true;

  @override
  Future<EmbeddingModelResult> doEmbed(
    EmbeddingModelCallOptions options,
  ) async {
    return EmbeddingModelResult(
      embeddings: [
        for (final _ in options.values) [0.0, 0.0],
      ],
      warnings: const <Warning>[],
    );
  }
}
