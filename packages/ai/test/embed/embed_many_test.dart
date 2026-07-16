import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
// 前缀刻意不用 `provider`:下方探针类实现 [spec.EmbeddingModel] 自带
// `provider` 成员,会在类作用域内遮蔽同名 import 前缀(同
// `scripted_embedding_model.dart` 的先例)。
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as spec;
import 'package:test/test.dart';

import '../support/logging.dart';
import '../support/scripted_embedding_model.dart';

/// 局部时序探针 fake:每次 doEmbed 记录 start 事件、等待对应 gate
/// 完成、记录 end 事件后返回预设 embedding。只服务本文件的并行度
/// 时序测试,不进 test/support(scripted_embedding_model 的固定批次
/// 消费模型无法表达"调用中途阻塞"的时序控制)。
final class _TimingProbeEmbeddingModel implements spec.EmbeddingModel {
  _TimingProbeEmbeddingModel({
    required this.maxEmbeddingsPerCall,
    required this.supportsParallelCalls,
    required this.events,
    required this.gates,
    required this.embeddingsByIndex,
  });

  @override
  String get specificationVersion => 'v4';

  @override
  final int? maxEmbeddingsPerCall;
  @override
  final bool supportsParallelCalls;
  final List<String> events;
  final List<Completer<void>> gates;
  final List<spec.Embedding> embeddingsByIndex;

  @override
  String get provider => 'timing-probe';
  @override
  String get modelId => 'timing-probe-model';

  int _callCount = 0;

  @override
  Future<spec.EmbeddingModelResult> doEmbed(
    spec.EmbeddingModelCallOptions options,
  ) async {
    final index = _callCount++;
    events.add('start-$index');
    await gates[index].future;
    events.add('end-$index');
    return spec.EmbeddingModelResult(
      embeddings: [embeddingsByIndex[index]],
      warnings: const [],
    );
  }
}

/// [_TimingProbeEmbeddingModel] 的 Future 能力值变体:两项能力值均声明为
/// [FutureOr],用于锚定 [embedMany] 消费侧对 Future 形态能力值的
/// await 语义(而不仅是接受同步值)。其余行为(事件记录、gate 阻塞)
/// 与 [_TimingProbeEmbeddingModel] 一致。
final class _TimingProbeFutureCapabilityEmbeddingModel
    implements spec.EmbeddingModel {
  _TimingProbeFutureCapabilityEmbeddingModel({
    required this.maxEmbeddingsPerCall,
    required this.supportsParallelCalls,
    required this.events,
    required this.gates,
    required this.embeddingsByIndex,
  });

  @override
  String get specificationVersion => 'v4';

  @override
  final FutureOr<int?> maxEmbeddingsPerCall;
  @override
  final FutureOr<bool> supportsParallelCalls;
  final List<String> events;
  final List<Completer<void>> gates;
  final List<spec.Embedding> embeddingsByIndex;

  @override
  String get provider => 'timing-probe-future-capability';
  @override
  String get modelId => 'timing-probe-future-capability-model';

  int _callCount = 0;

  @override
  Future<spec.EmbeddingModelResult> doEmbed(
    spec.EmbeddingModelCallOptions options,
  ) async {
    final index = _callCount++;
    events.add('start-$index');
    await gates[index].future;
    events.add('end-$index');
    return spec.EmbeddingModelResult(
      embeddings: [embeddingsByIndex[index]],
      warnings: const [],
    );
  }
}

void main() {
  final values = ['a', 'b', 'c'];

  group('embedMany 快路径与切批边界', () {
    test('快路径:maxEmbeddingsPerCall 为 null 时单次全量调用', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: null,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(model.callCount, 1);
      expect(model.receivedCallOptions.single.values, values);
      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
      ]);
      expect(result.responses, hasLength(1));
    });

    test('切批边界:恰好整除', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
            [4.0],
          ]),
        ],
      );

      final result = await embedMany(
        model: model,
        values: ['a', 'b', 'c', 'd'],
      );

      expect(model.callCount, 2);
      expect(model.receivedCallOptions[0].values, ['a', 'b']);
      expect(model.receivedCallOptions[1].values, ['c', 'd']);
      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
        [4.0],
      ]);
    });

    test('切批边界:有余数', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(model.callCount, 2);
      expect(model.receivedCallOptions[1].values, ['c']);
      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
      ]);
    });

    test('切批边界:单元素 values', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [9.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: ['solo']);

      expect(model.callCount, 1);
      expect(result.embeddings, [
        [9.0],
      ]);
    });

    test('切批边界:空 values 列表', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: const [],
      );

      final result = await embedMany(model: model, values: const []);

      expect(model.callCount, 0);
      expect(result.embeddings, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.responses, isEmpty);
      expect(result.usage.tokens, 0);
    });
  });

  group('embedMany 并行度', () {
    test('supportsParallelCalls=false 时严格串行', () async {
      final events = <String>[];
      final gates = List.generate(3, (_) => Completer<void>());
      final model = _TimingProbeEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: false,
        events: events,
        gates: gates,
        embeddingsByIndex: [
          [0.1],
          [0.2],
          [0.3],
        ],
      );

      final future = embedMany(model: model, values: ['a', 'b', 'c']);
      for (final gate in gates) {
        gate.complete();
      }
      final result = await future;

      expect(events, [
        'start-0', 'end-0', // 第一批完全结束才开始第二批
        'start-1', 'end-1',
        'start-2', 'end-2',
      ]);
      expect(result.embeddings, [
        [0.1],
        [0.2],
        [0.3],
      ]);
    });

    test('supportsParallelCalls=true 且无 maxParallelCalls 时全量并发', () async {
      final events = <String>[];
      final gates = List.generate(3, (_) => Completer<void>());
      final model = _TimingProbeEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: true,
        events: events,
        gates: gates,
        embeddingsByIndex: [
          [0.1],
          [0.2],
          [0.3],
        ],
      );

      final future = embedMany(model: model, values: ['a', 'b', 'c']);
      for (final gate in gates) {
        gate.complete();
      }
      final result = await future;

      expect(events, [
        'start-0', 'start-1', 'start-2', // 全部先 start
        'end-0', 'end-1', 'end-2',
      ]);
      expect(result.embeddings, [
        [0.1],
        [0.2],
        [0.3],
      ]);
    });

    test('maxParallelCalls=2 时按二为一组', () async {
      final events = <String>[];
      final gates = List.generate(3, (_) => Completer<void>());
      final model = _TimingProbeEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: true,
        events: events,
        gates: gates,
        embeddingsByIndex: [
          [0.1],
          [0.2],
          [0.3],
        ],
      );

      final future = embedMany(
        model: model,
        values: ['a', 'b', 'c'],
        maxParallelCalls: 2,
      );
      for (final gate in gates) {
        gate.complete();
      }
      final result = await future;

      expect(events, [
        'start-0', 'start-1', // 第一组:0/1 并发
        'end-0', 'end-1',
        'start-2', 'end-2', // 第二组:仅 2
      ]);
      expect(result.embeddings, [
        [0.1],
        [0.2],
        [0.3],
      ]);
    });
  });

  group('embedMany 保序', () {
    test('多批结果按原始 values 顺序拼接', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: true,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
      ]);
    });
  });

  group('embedMany usage null 传染', () {
    test('三批其一 tokens 为 null 时总和为 null', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: false,
        batches: [
          ScriptedEmbeddingBatch(
            embeddings: [
              [1.0],
            ],
            usage: const spec.EmbeddingUsage(tokens: 10),
          ),
          ScriptedEmbeddingBatch(
            embeddings: [
              [2.0],
            ],
            usage: const spec.EmbeddingUsage(),
          ),
          ScriptedEmbeddingBatch(
            embeddings: [
              [3.0],
            ],
            usage: const spec.EmbeddingUsage(tokens: 20),
          ),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(result.usage.tokens, isNull);
    });

    test('全部批次都有 tokens 时求和', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: [
          ScriptedEmbeddingBatch(
            embeddings: [
              [1.0],
              [2.0],
            ],
            usage: const spec.EmbeddingUsage(tokens: 10),
          ),
          ScriptedEmbeddingBatch(
            embeddings: [
              [3.0],
            ],
            usage: const spec.EmbeddingUsage(tokens: 20),
          ),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(result.usage.tokens, 30);
    });
  });

  group('embedMany providerMetadata 合并', () {
    test('同 provider 名内层键后批覆盖前批,不同 provider 名并存', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: false,
        batches: [
          ScriptedEmbeddingBatch(
            embeddings: [
              [1.0],
            ],
            providerMetadata: const {
              'openai': {'requestId': 'req-1', 'shared': 'old'},
            },
          ),
          ScriptedEmbeddingBatch(
            embeddings: [
              [2.0],
            ],
            providerMetadata: const {
              'openai': {'shared': 'new'},
              'gateway': {'resolvedProvider': 'test'},
            },
          ),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1', 'shared': 'new'},
        'gateway': {'resolvedProvider': 'test'},
      });
    });
  });

  group('embedMany warnings 串接', () {
    test('多批 warnings 按批次顺序串接', () async {
      final records = captureWarningLogs();
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: false,
        batches: [
          ScriptedEmbeddingBatch(
            embeddings: [
              [1.0],
            ],
            warnings: const [spec.OtherWarning('w1')],
          ),
          ScriptedEmbeddingBatch(
            embeddings: [
              [2.0],
            ],
            warnings: const [spec.OtherWarning('w2')],
          ),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(result.warnings, [
        const spec.OtherWarning('w1'),
        const spec.OtherWarning('w2'),
      ]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning '
            '(scripted-embedding-provider / scripted-embedding-model): w1',
        'Pigcode AI Warning '
            '(scripted-embedding-provider / scripted-embedding-model): w2',
      ]);
    });
  });

  group('embedMany 错误传播', () {
    test('某批 doEmbed 抛错时 embedMany 直接向上抛出', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: false,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
        ],
        errors: {1: StateError('doEmbed failed')},
      );

      expect(
        () => embedMany(model: model, values: values),
        throwsA(isA<StateError>()),
      );
    });

    test('supportsParallelCalls=true 时组内其一抛错,embedMany 以该错误失败', () async {
      // 三批同组并发(supportsParallelCalls=true、无 maxParallelCalls),
      // 中间一批(序号 1)抛错:锚定 Future.wait 组内路径的错误传播
      // (embed/embed_many.dart ~L106-117),而非仅测过的组间串行路径。
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        supportsParallelCalls: true,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
        errors: {1: StateError('parallel batch failed')},
      );

      expect(
        () => embedMany(model: model, values: values),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('embedMany 能力值 FutureOr 的 Future 形态', () {
    test('maxEmbeddingsPerCall 以 Future.value(null) 提供时走快路径', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: Future.value(null),
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      // 快路径特征:单次全量调用、responses 长度为 1
      // (与同步 null 形态的快路径用例断言口径一致)。
      expect(model.callCount, 1);
      expect(model.receivedCallOptions.single.values, values);
      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
      ]);
      expect(result.responses, hasLength(1));
    });

    test('maxEmbeddingsPerCall 以 Future.value(2) 提供时正确切批', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: Future.value(2),
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );

      final result = await embedMany(model: model, values: values);

      expect(model.callCount, 2);
      expect(model.receivedCallOptions[0].values, ['a', 'b']);
      expect(model.receivedCallOptions[1].values, ['c']);
      expect(result.embeddings, [
        [1.0],
        [2.0],
        [3.0],
      ]);
    });

    test('supportsParallelCalls 以 Future.value(false) 提供时严格串行', () async {
      final events = <String>[];
      final gates = List.generate(3, (_) => Completer<void>());
      final model = _TimingProbeFutureCapabilityEmbeddingModel(
        maxEmbeddingsPerCall: Future.value(1),
        supportsParallelCalls: Future.value(false),
        events: events,
        gates: gates,
        embeddingsByIndex: [
          [0.1],
          [0.2],
          [0.3],
        ],
      );

      final future = embedMany(model: model, values: ['a', 'b', 'c']);
      for (final gate in gates) {
        gate.complete();
      }
      final result = await future;

      // 顺序断言:第一批完全结束(start-0/end-0)才开始第二批,
      // 锚定 [embedMany] 消费侧对 Future 形态能力值的 await 语义
      // 确实驱动了串行分组,而非恰好并发也能通过。
      expect(events, [
        'start-0',
        'end-0',
        'start-1',
        'end-1',
        'start-2',
        'end-2',
      ]);
      expect(result.embeddings, [
        [0.1],
        [0.2],
        [0.3],
      ]);
    });
  });

  group('embedMany 透传:headers/providerOptions/cancellation', () {
    test('快路径:三项透传给 doEmbed', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: null,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
            [3.0],
          ]),
        ],
      );
      final controller = spec.CancellationController();

      await embedMany(
        model: model,
        values: values,
        providerOptions: const {
          'openai': {'dimensions': 256},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(received.providerOptions, {
        'openai': {'dimensions': 256},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('切批路径:每批 doEmbed 都收到相同的三项透传值', () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 2,
        batches: [
          ScriptedEmbeddingBatch(embeddings: [
            [1.0],
            [2.0],
          ]),
          ScriptedEmbeddingBatch(embeddings: [
            [3.0],
          ]),
        ],
      );
      final controller = spec.CancellationController();

      await embedMany(
        model: model,
        values: values,
        providerOptions: const {
          'openai': {'dimensions': 256},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(2));
      for (final received in model.receivedCallOptions) {
        expect(received.providerOptions, {
          'openai': {'dimensions': 256},
        });
        expect(received.headers, {'x-custom': 'v'});
        expect(received.cancellation, same(controller.signal));
      }
    });
  });

  group('embedMany maxParallelCalls 入口守卫', () {
    test('maxParallelCalls=0 时抛出 ArgumentError 且信息提及 maxParallelCalls',
        () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        batches: const [],
      );

      expect(
        () => embedMany(model: model, values: values, maxParallelCalls: 0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString()',
            contains('maxParallelCalls'),
          ),
        ),
      );
    });

    test('maxParallelCalls=-1 时抛出 ArgumentError 且信息提及 maxParallelCalls',
        () async {
      final model = ScriptedEmbeddingModel(
        maxEmbeddingsPerCall: 1,
        batches: const [],
      );

      expect(
        () => embedMany(model: model, values: values, maxParallelCalls: -1),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString()',
            contains('maxParallelCalls'),
          ),
        ),
      );
    });
  });
}
