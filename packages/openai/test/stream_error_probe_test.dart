import 'dart:async';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

/// 测试用的 chat 风格 matcher:`{error:{...}}` 信封判定错误帧,
/// `choices[].delta.content` 非空判定输出 chunk——与
/// `chat_language_model.dart` 的调用点逐字一致,用于覆盖窗口循环的
/// 通用行为(不重复测试 chat/responses 各自 wire 特有的形状,那部分见
/// `test/chat/chat_language_model_stream_test.dart` 与
/// `test/responses/responses_language_model_test.dart`)。
JsonValue? _getError(JsonValue value) {
  final map = value as Map<String, Object?>;
  return map['error'];
}

bool _isOutputChunk(JsonValue value) {
  final map = value as Map<String, Object?>;
  if (map['error'] != null) {
    return false;
  }
  final choices = map['choices'] as List<Object?>?;
  if (choices == null) {
    return false;
  }
  return choices.any((rawChoice) {
    final choice = rawChoice as Map<String, Object?>;
    final delta = choice['delta'] as Map<String, Object?>?;
    final content = delta?['content'] as String?;
    return content != null && content.isNotEmpty;
  });
}

void main() {
  group('throwIfStreamErrorBeforeOutput — 正常帧前拼', () {
    test('首事件即输出 chunk 时,两帧完整无损传出', () async {
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        const ParseSuccess<JsonValue>(<String, Object?>{
          'id': 'chunk-1',
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{'content': 'hello'},
            },
          ],
        }),
        const ParseSuccess<JsonValue>(<String, Object?>{
          'id': 'chunk-2',
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{'content': ' world'},
            },
          ],
        }),
      ]);

      final result = await throwIfStreamErrorBeforeOutput(
        source,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: const <String, Object?>{'model': 'gpt-4o'},
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      final collected = await result.toList();
      expect(collected, hasLength(2));
      final first = collected[0] as ParseSuccess<JsonValue>;
      final second = collected[1] as ParseSuccess<JsonValue>;
      expect((first.value! as Map<String, Object?>)['id'], 'chunk-1');
      expect((second.value! as Map<String, Object?>)['id'], 'chunk-2');
    });

    test(
        '窗口扩展:首帧为非输出元数据帧(空 delta)、次帧才是输出 chunk 时,'
        '两帧按序完整前拼(不止 peek 首帧)', () async {
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        const ParseSuccess<JsonValue>(<String, Object?>{
          'id': 'chunk-meta',
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{'role': 'assistant'},
            },
          ],
        }),
        const ParseSuccess<JsonValue>(<String, Object?>{
          'id': 'chunk-output',
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{'content': 'hello'},
            },
          ],
        }),
      ]);

      final result = await throwIfStreamErrorBeforeOutput(
        source,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: const <String, Object?>{'model': 'gpt-4o'},
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      final collected = await result.toList();
      expect(collected, hasLength(2));
      final first = collected[0] as ParseSuccess<JsonValue>;
      final second = collected[1] as ParseSuccess<JsonValue>;
      expect((first.value! as Map<String, Object?>)['id'], 'chunk-meta');
      expect((second.value! as Map<String, Object?>)['id'], 'chunk-output');
    });
  });

  group('throwIfStreamErrorBeforeOutput — 错误帧同步 throw', () {
    test('首事件为标准 OpenAI 错误帧时,Future 层同步 throw ApiCallError', () {
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        const ParseSuccess<JsonValue>(<String, Object?>{
          'error': <String, Object?>{
            'message': 'You exceeded your current quota',
            'type': 'insufficient_quota',
            'param': null,
            'code': 'insufficient_quota',
          },
        }),
        const ParseSuccess<JsonValue>(<String, Object?>{'id': 'never-seen'}),
      ]);

      expect(
        () => throwIfStreamErrorBeforeOutput(
          source,
          url: Uri.parse('https://api.openai.com/v1/chat/completions'),
          requestBody: const <String, Object?>{'model': 'gpt-4o'},
          getError: _getError,
          isOutputChunk: _isOutputChunk,
        ),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message',
                  'You exceeded your current quota')
              .having((e) => e.url, 'url',
                  'https://api.openai.com/v1/chat/completions')
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });

    test('错误帧的 data 携带原始错误体', () async {
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        const ParseSuccess<JsonValue>(<String, Object?>{
          'error': <String, Object?>{
            'message': 'invalid request',
            'type': 'invalid_request_error',
          },
        }),
      ]);

      try {
        await throwIfStreamErrorBeforeOutput(
          source,
          url: Uri.parse('https://api.openai.com/v1/chat/completions'),
          requestBody: null,
          getError: _getError,
          isOutputChunk: _isOutputChunk,
        );
        fail('expected ApiCallError to be thrown');
      } on ApiCallError catch (error) {
        expect(error.data, isA<Map<String, Object?>>());
        expect(
          (error.data! as Map<String, Object?>)['message'],
          'invalid request',
        );
        expect(error.statusCode, 400);
      }
    });

    test(
        '窗口扩展:首帧为非输出元数据帧、次帧才是错误帧时,仍从 Future 层 '
        'throw ApiCallError(探测不止于首帧)', () {
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        const ParseSuccess<JsonValue>(<String, Object?>{
          'id': 'chunk-meta',
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{'role': 'assistant'},
            },
          ],
        }),
        const ParseSuccess<JsonValue>(<String, Object?>{
          'error': <String, Object?>{
            'message': 'The server had an error processing your request',
            'type': 'server_error',
            'code': null,
          },
        }),
      ]);

      expect(
        () => throwIfStreamErrorBeforeOutput(
          source,
          url: Uri.parse('https://api.openai.com/v1/chat/completions'),
          requestBody: null,
          getError: _getError,
          isOutputChunk: _isOutputChunk,
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'The server had an error processing your request',
          ),
        ),
      );
    });
  });

  group('throwIfStreamErrorBeforeOutput — 边界场景', () {
    test('空流(无任何事件即 done)不 throw,返回空流', () async {
      final source = const Stream<ParseResult<JsonValue>>.empty();

      final result = await throwIfStreamErrorBeforeOutput(
        source,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      final collected = await result.toList();
      expect(collected, isEmpty);
    });

    test('下游取消订阅会传导到上游(上游底层订阅被取消)', () async {
      var upstreamCancelled = false;
      late StreamController<ParseResult<JsonValue>> upstreamController;
      upstreamController = StreamController<ParseResult<JsonValue>>(
        onListen: () {
          upstreamController.add(
            const ParseSuccess<JsonValue>(<String, Object?>{
              'id': 'c1',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{'content': 'hi'},
                },
              ],
            }),
          );
        },
        onCancel: () {
          upstreamCancelled = true;
        },
      );

      final result = await throwIfStreamErrorBeforeOutput(
        upstreamController.stream,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      final subscription = result.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(upstreamCancelled, isTrue);
    });

    test(
        'probe 期间源流以连接级 error 完成(无任何事件)时,'
        'Future 正常完成、返回的流以该错误失败', () async {
      final sourceError = StateError('connection reset');
      late StreamController<ParseResult<JsonValue>> upstreamController;
      upstreamController = StreamController<ParseResult<JsonValue>>(
        onListen: () {
          upstreamController
            ..addError(sourceError)
            ..close();
        },
      );

      // Future 本身应正常完成(不 throw),即使源流的连接从未产出可解析
      // 事件就直接失败——这是与「错误帧 → Future 抛 ApiCallError」路径
      // 的关键区别:连接级流错误走流内,不走 Future 层。
      final result = await throwIfStreamErrorBeforeOutput(
        upstreamController.stream,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      await expectLater(
        result,
        emitsError(same(sourceError)),
      );
    });

    test(
        '窗口扩展:已读一个非输出元数据帧后,源流以连接级 error 完成时,'
        'Future 仍正常完成、返回的流先重放已缓冲的元数据帧再以该错误失败', () async {
      final sourceError = StateError('connection reset');
      late StreamController<ParseResult<JsonValue>> upstreamController;
      upstreamController = StreamController<ParseResult<JsonValue>>(
        onListen: () async {
          upstreamController.add(
            const ParseSuccess<JsonValue>(<String, Object?>{
              'id': 'chunk-meta',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{'role': 'assistant'},
                },
              ],
            }),
          );
          await Future<void>.delayed(Duration.zero);
          upstreamController
            ..addError(sourceError)
            ..close();
        },
      );

      final result = await throwIfStreamErrorBeforeOutput(
        upstreamController.stream,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      await expectLater(
        result,
        emitsInOrder(<Object>[
          isA<ParseSuccess<JsonValue>>().having(
            (e) => e.value! as Map<String, Object?>,
            'value',
            containsPair('id', 'chunk-meta'),
          ),
          emitsError(same(sourceError)),
        ]),
      );
    });

    test('首事件是 ParseFailure(解析失败帧)时不触发 throw,原样前拼', () async {
      final parseError = JsonParseError(text: '{invalid');
      final source =
          Stream<ParseResult<JsonValue>>.fromIterable(<ParseResult<JsonValue>>[
        ParseFailure<JsonValue>(parseError),
        const ParseSuccess<JsonValue>(<String, Object?>{'id': 'c2'}),
      ]);

      final result = await throwIfStreamErrorBeforeOutput(
        source,
        url: Uri.parse('https://api.openai.com/v1/chat/completions'),
        requestBody: null,
        getError: _getError,
        isOutputChunk: _isOutputChunk,
      );

      final collected = await result.toList();
      expect(collected, hasLength(2));
      expect(collected[0], isA<ParseFailure<JsonValue>>());
      expect(
        (collected[0] as ParseFailure<JsonValue>).error,
        same(parseError),
      );
      expect(
        ((collected[1] as ParseSuccess<JsonValue>).value!
            as Map<String, Object?>)['id'],
        'c2',
      );
    });
  });
}
