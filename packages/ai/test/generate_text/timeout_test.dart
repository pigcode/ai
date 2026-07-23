import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(),
  outputTokens: lm.OutputTokens(),
);

final class _CallbackModel implements lm.LanguageModel {
  _CallbackModel({
    this.generate,
    this.stream,
  });

  final Future<lm.LanguageModelGenerateResult> Function(
    lm.LanguageModelCallOptions options,
  )? generate;
  final Future<lm.LanguageModelStreamResult> Function(
    lm.LanguageModelCallOptions options,
  )? stream;

  final List<lm.LanguageModelCallOptions> calls =
      <lm.LanguageModelCallOptions>[];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'timeout-test';

  @override
  String get modelId => 'timeout-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const <String, List<RegExp>>{};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) {
    calls.add(options);
    return generate!(options);
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) {
    calls.add(options);
    return stream!(options);
  }
}

Matcher _timeoutWith(String label) => isA<TimeoutException>().having(
      (error) => error.message,
      'message',
      contains(label),
    );

Stream<lm.LanguageModelStreamPart> _idleStream({
  List<lm.LanguageModelStreamPart> initial =
      const <lm.LanguageModelStreamPart>[],
}) {
  late final StreamController<lm.LanguageModelStreamPart> controller;
  controller = StreamController<lm.LanguageModelStreamPart>(
    onListen: () {
      for (final part in initial) {
        controller.add(part);
      }
    },
    // Simulate a provider whose cancellation cleanup never completes. Core
    // timeout delivery must not wait for this future.
    onCancel: () => Completer<void>().future,
  );
  return controller.stream;
}

Future<Object> _generateError({
  required Object timeout,
  required _CallbackModel model,
}) async {
  try {
    await generateText(model: model, prompt: 'wait', timeout: timeout);
  } catch (error) {
    return error;
  }
  throw StateError('generateText unexpectedly completed');
}

Future<List<TextStreamPart>> _streamParts({
  required Object timeout,
  required _CallbackModel model,
}) {
  return streamText(
    model: model,
    prompt: 'wait',
    timeout: timeout,
  ).stream.toList();
}

void main() {
  // Compatibility fixture (unit): P1-CORE-11
  group('P1-CORE-11 generate timeouts', () {
    test('legacy Duration bounds a model that ignores cancellation', () async {
      final model = _CallbackModel(
        generate: (_) => Completer<lm.LanguageModelGenerateResult>().future,
      );

      final error = await _generateError(
        model: model,
        timeout: const Duration(milliseconds: 30),
      );

      expect(error, _timeoutWith('Total'));
      expect(model.calls.single.cancellation?.reason, same(error));
    });

    test('structured step timeout preserves its reason', () async {
      final model = _CallbackModel(
        generate: (_) => Completer<lm.LanguageModelGenerateResult>().future,
      );

      final error = await _generateError(
        model: model,
        timeout: const TimeoutConfiguration(
          step: Duration(milliseconds: 30),
        ),
      );

      expect(error, _timeoutWith('Step'));
      expect(model.calls.single.cancellation?.reason, same(error));
    });

    test('per-tool timeout reaches the tool cancellation signal', () async {
      lm.CancellationSignal? toolSignal;
      final model = ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[
              lm.ToolCall(
                toolCallId: 'call-slow',
                toolName: 'slow',
                input: '{}',
              ),
            ],
            finishReason: lm.LanguageModelFinishReason(
              lm.FinishReasonType.toolCalls,
            ),
            usage: _usage,
          ),
        ],
      );

      Object? error;
      try {
        await generateText(
          model: model,
          prompt: 'slow',
          tools: <String, Tool>{
            'slow': Tool(
              inputSchema: const lm.JsonSchema(<String, Object?>{
                'type': 'object',
              }),
              execute: (input, options) {
                toolSignal = options.cancellation;
                return Completer<Object?>().future;
              },
            ),
          },
          timeout: const TimeoutConfiguration(
            tool: Duration(milliseconds: 30),
          ),
        );
      } catch (caught) {
        error = caught;
      }

      expect(error, _timeoutWith('Tool slow'));
      expect(toolSignal?.isCancelled, isTrue);
      expect(toolSignal?.reason, same(error));
    });
  });

  group('P1-CORE-11 stream timeouts', () {
    test('total and step timeouts interrupt an idle stream', () async {
      for (final entry in <(Object, String)>[
        (
          const TimeoutConfiguration(total: Duration(milliseconds: 30)),
          'Total',
        ),
        (
          const TimeoutConfiguration(step: Duration(milliseconds: 30)),
          'Step',
        ),
      ]) {
        final model = _CallbackModel(
          stream: (_) async => lm.LanguageModelStreamResult(
            stream: _idleStream(),
          ),
        );

        final parts = await _streamParts(timeout: entry.$1, model: model);

        expect(
            parts.whereType<ErrorPart>().single.error, _timeoutWith(entry.$2));
      }
    });

    test('source metadata does not satisfy the first semantic chunk timeout',
        () async {
      final model = _CallbackModel(
        stream: (_) async => lm.LanguageModelStreamResult(
          stream: _idleStream(
            initial: const <lm.LanguageModelStreamPart>[
              lm.StreamStart(<lm.Warning>[]),
              lm.SourceContent.url(
                id: 'source-1',
                url: 'https://example.com',
              ),
            ],
          ),
        ),
      );

      final parts = await _streamParts(
        model: model,
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 30),
        ),
      );

      expect(
        parts.whereType<ErrorPart>().single.error,
        _timeoutWith('First chunk'),
      );
    });

    test('chunk timeout starts again after a non-empty semantic delta',
        () async {
      final model = _CallbackModel(
        stream: (_) async => lm.LanguageModelStreamResult(
          stream: _idleStream(
            initial: const <lm.LanguageModelStreamPart>[
              lm.StreamStart(<lm.Warning>[]),
              lm.TextStart('text-1'),
              lm.TextDelta('text-1', 'a'),
            ],
          ),
        ),
      );

      final parts = await _streamParts(
        model: model,
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 100),
          chunk: Duration(milliseconds: 30),
        ),
      );

      expect(parts.whereType<TextDeltaPart>().single.delta, 'a');
      expect(parts.whereType<ErrorPart>().single.error, _timeoutWith('Chunk'));
    });

    test('successful terminal cleanup leaves step signals active', () async {
      final model = ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[
              lm.TextContent('done'),
            ],
            finishReason: lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
            usage: _usage,
          ),
        ],
      );
      final result = streamText(
        model: model,
        prompt: 'done',
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 30),
          chunk: Duration(milliseconds: 30),
        ),
      );

      final parts = await result.stream.toList();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(parts.last, isA<FinishPart>());
      expect(
          model.receivedCallOptions.single.cancellation?.isCancelled, isFalse);
    });
  });
}
