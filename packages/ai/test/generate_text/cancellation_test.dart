import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(),
  outputTokens: lm.OutputTokens(),
);

void main() {
  // Compatibility fixture (unit): P1-CORE-10
  group('P1-CORE-10 cancellation reason propagation', () {
    test('generateText throws the original reason before the model call',
        () async {
      final reason = StateError('cancel before call');
      final cancellation = lm.CancellationController()..cancel(reason);
      final model = ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[lm.TextContent('unused')],
            finishReason:
                lm.LanguageModelFinishReason(lm.FinishReasonType.stop),
            usage: _usage,
          ),
        ],
      );

      await expectLater(
        generateText(
          model: model,
          prompt: 'cancel',
          cancellation: cancellation.signal,
        ),
        throwsA(same(reason)),
      );
      expect(model.callCount, 0);
    });

    test('streamText emits AbortPart before the model call', () async {
      final reason = StateError('cancel before stream');
      final cancellation = lm.CancellationController()..cancel(reason);
      final model = ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[lm.TextContent('unused')],
            finishReason:
                lm.LanguageModelFinishReason(lm.FinishReasonType.stop),
            usage: _usage,
          ),
        ],
      );

      final parts = await streamText(
        model: model,
        prompt: 'cancel',
        cancellation: cancellation.signal,
      ).stream.toList();

      expect(parts, <TextStreamPart>[
        const StartPart(),
        AbortPart(reason: reason.toString()),
      ]);
      expect(model.callCount, 0);
    });

    test('streamText aborts while waiting for a model stream', () async {
      final invoked = Completer<void>();
      final model = _IdleStreamModel(invoked);
      final cancellation = lm.CancellationController();
      final result = streamText(
        model: model,
        prompt: 'cancel',
        cancellation: cancellation.signal,
      );
      await invoked.future;

      cancellation.cancel('model stream cancelled');
      final parts = await result.stream.toList();

      expect(parts.last, const AbortPart(reason: 'model stream cancelled'));
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('streamText aborts while a tool execution is pending', () async {
      final toolStarted = Completer<void>();
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
            finishReason:
                lm.LanguageModelFinishReason(lm.FinishReasonType.toolCalls),
            usage: _usage,
          ),
        ],
      );
      final cancellation = lm.CancellationController();
      final result = streamText(
        model: model,
        prompt: 'cancel tool',
        cancellation: cancellation.signal,
        tools: <String, Tool>{
          'slow': Tool(
            inputSchema: const lm.JsonSchema(<String, Object?>{
              'type': 'object',
            }),
            execute: (input, options) {
              toolStarted.complete();
              return Completer<Object?>().future;
            },
          ),
        },
      );
      await toolStarted.future;

      cancellation.cancel('tool cancelled');
      final parts = await result.stream.toList();

      expect(parts.last, const AbortPart(reason: 'tool cancelled'));
      expect(parts.whereType<ToolCallStreamPart>(), hasLength(1));
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });
  });
}

final class _IdleStreamModel implements lm.LanguageModel {
  _IdleStreamModel(this.invoked);

  final Completer<void> invoked;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'cancellation-test';

  @override
  String get modelId => 'idle-stream';

  @override
  Map<String, List<RegExp>> get supportedUrls => const <String, List<RegExp>>{};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    late final StreamController<lm.LanguageModelStreamPart> controller;
    controller = StreamController<lm.LanguageModelStreamPart>(
      onListen: () {
        controller.add(const lm.StreamStart(<lm.Warning>[]));
        invoked.complete();
      },
      onCancel: () {},
    );
    return lm.LanguageModelStreamResult(stream: controller.stream);
  }
}
