import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

const _usage = lm.LanguageModelUsage(
  inputTokens: lm.InputTokens(total: 1),
  outputTokens: lm.OutputTokens(total: 1),
);

ScriptedTurn _textTurn(String text) {
  return ScriptedTurn(
    content: <lm.LanguageModelContent>[lm.TextContent(text)],
    finishReason: const lm.LanguageModelFinishReason(
      lm.FinishReasonType.stop,
    ),
    usage: _usage,
  );
}

void main() {
  // Compatibility fixture (scripted-peer): P1-CORE-01
  // Compatibility fixture (scripted-peer): P1-CORE-02
  // Compatibility fixture (scripted-peer): P1-CORE-03
  // Compatibility fixture (scripted-peer): P1-CORE-04
  // Compatibility fixture (scripted-peer): P1-CORE-05
  // Compatibility fixture (scripted-peer): P1-CORE-06
  // Compatibility fixture (scripted-peer): P1-CORE-07
  // Compatibility fixture (scripted-peer): P1-CORE-08
  // Compatibility fixture (scripted-peer): P1-CORE-09
  // Compatibility fixture (scripted-peer): P1-CORE-10
  // Compatibility fixture (scripted-peer): P1-CORE-11
  test('public generate API covers prompt, multi-step tools, repair and output',
      () async {
    final callbacks = <String>[];
    ToolCallRepairFailure? repairFailure;
    final model = ScriptedModel(
      turns: <ScriptedTurn>[
        const ScriptedTurn(
          content: <lm.LanguageModelContent>[
            lm.ToolCall(
              toolCallId: 'reused-id',
              toolName: 'missing',
              input: '{"value":1}',
            ),
          ],
          finishReason:
              lm.LanguageModelFinishReason(lm.FinishReasonType.toolCalls),
          usage: _usage,
          warnings: <lm.Warning>[lm.UnsupportedWarning('topK')],
        ),
        const ScriptedTurn(
          content: <lm.LanguageModelContent>[
            lm.ToolCall(
              toolCallId: 'reused-id',
              toolName: 'echo',
              input: '{"value":2}',
            ),
          ],
          finishReason:
              lm.LanguageModelFinishReason(lm.FinishReasonType.toolCalls),
          usage: _usage,
        ),
        _textTurn('{"answer":"done"}'),
      ],
    );
    final result = await generateText(
      model: model,
      messages: const <ModelMessage>[
        UserModelMessage(
          <UserContentPart>[TextPart('run')],
          providerOptions: <String, lm.JsonObject>{
            'openai': <String, Object?>{'user': true},
          },
        ),
      ],
      instructions: 'system instruction',
      providerOptions: const <String, lm.JsonObject>{
        'openai': <String, Object?>{'request': true},
      },
      tools: <String, Tool>{
        'echo': Tool(
          inputSchema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'value': <String, Object?>{'type': 'number'},
            },
            'required': <Object?>['value'],
          }),
          onInputStart: (options) {
            callbacks.add('start:${options.toolCallId}');
          },
          onInputAvailable: (options) {
            callbacks.add(
              'available:${(options.input as Map<String, Object?>)['value']}',
            );
          },
          execute: (input, options) {
            callbacks.add(
              'execute:${(input as Map<String, Object?>)['value']}',
            );
            return input['value'];
          },
        ),
      },
      activeTools: const <String>['echo'],
      toolOrder: const <String>['echo'],
      stopWhen: isStepCount(3),
      repairToolCall: (options) {
        repairFailure = options.error;
        return lm.ToolCall(
          toolCallId: options.toolCall.toolCallId,
          toolName: 'echo',
          input: options.toolCall.input,
        );
      },
      output: Output.object(
        schema: const lm.JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
          'required': <Object?>['answer'],
          'additionalProperties': false,
        }),
      ),
    );

    expect(repairFailure, isA<NoSuchToolError>());
    expect(result.output, <String, Object?>{'answer': 'done'});
    expect(result.steps, hasLength(3));
    expect(result.warnings, <lm.Warning>[const lm.UnsupportedWarning('topK')]);
    expect(result.usage.inputTokens.total, 3);
    expect(
      callbacks,
      <String>[
        'start:reused-id',
        'available:1',
        'execute:1',
        'start:reused-id',
        'available:2',
        'execute:2',
      ],
    );

    final firstPrompt = model.receivedCallOptions.first.prompt;
    expect(firstPrompt.first, isA<lm.SystemMessage>());
    expect(
      (firstPrompt.last as lm.UserMessage).providerOptions,
      const <String, lm.JsonObject>{
        'openai': <String, Object?>{'user': true},
      },
    );
    expect(
      model.receivedCallOptions.first.providerOptions,
      const <String, lm.JsonObject>{
        'openai': <String, Object?>{'request': true},
      },
    );

    final finalPrompt = model.receivedCallOptions.last.prompt;
    expect(
      finalPrompt
          .whereType<lm.AssistantMessage>()
          .expand((message) => message.content)
          .whereType<lm.ToolCallPart>()
          .map((call) => call.toolCallId),
      <String>['reused-id', 'reused-id'],
    );
    expect(
      finalPrompt
          .whereType<lm.ToolMessage>()
          .expand((message) => message.content)
          .whereType<lm.ToolResultPart>()
          .map((result) => result.toolCallId),
      <String>['reused-id', 'reused-id'],
    );
  });

  test('public output modes work for generate and stream partials', () async {
    final choice = await generateText(
      model: ScriptedModel(turns: <ScriptedTurn>[
        _textTurn('{"result":"blue"}'),
      ]),
      prompt: 'choice',
      output: Output.choice(options: const <String>['red', 'blue']),
    );
    final json = await generateText(
      model: ScriptedModel(turns: <ScriptedTurn>[
        _textTurn('[1,true,null]'),
      ]),
      prompt: 'json',
      output: Output.json(),
    );
    final text = await generateText(
      model: ScriptedModel(turns: <ScriptedTurn>[_textTurn('plain')]),
      prompt: 'text',
      output: Output.text(),
    );
    final stream = streamText(
      model: ScriptedModel(turns: <ScriptedTurn>[
        _textTurn('{"elements":[{"id":1},{"id":2}]}'),
      ]),
      prompt: 'array',
      output: Output.array(
        element: const lm.JsonSchema(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'number'},
          },
          'required': <Object?>['id'],
          'additionalProperties': false,
        }),
      ),
    );

    expect(choice.output, 'blue');
    expect(json.output, <Object?>[1, true, null]);
    expect(text.output, 'plain');
    expect(await stream.elementStream.toList(), <Object?>[
      <String, Object?>{'id': 1},
      <String, Object?>{'id': 2},
    ]);
    expect(await stream.output, <Object?>[
      <String, Object?>{'id': 1},
      <String, Object?>{'id': 2},
    ]);

    await expectLater(
      generateText(
        model: ScriptedModel(turns: <ScriptedTurn>[
          _textTurn('{"result":"green"}'),
        ]),
        prompt: 'invalid choice',
        output: Output.choice(options: const <String>['red', 'blue']),
      ),
      throwsA(isA<NoObjectGeneratedError>()),
    );
  });

  test('stream framing and error terminal are deterministic', () async {
    final success = streamText(
      model: ScriptedModel(turns: <ScriptedTurn>[_textTurn('hello')]),
      prompt: 'stream',
    );
    final successParts = await success.stream.toList();

    expect(
      successParts.map((part) => part.runtimeType),
      <Type>[
        StartPart,
        StartStepPart,
        TextStartPart,
        TextDeltaPart,
        TextEndPart,
        FinishStepPart,
        FinishPart,
      ],
    );

    final onErrors = <Object?>[];
    final failed = streamText(
      model: ErrorStreamModel(),
      prompt: 'error',
      onError: onErrors.add,
    );
    final failedParts = await failed.stream.toList();

    expect(failedParts.last, const ErrorPart('boom'));
    expect(failedParts.whereType<FinishPart>(), isEmpty);
    expect(onErrors, <Object?>['boom']);
  });

  test('approval denial, external abort and timeout are distinct terminals',
      () async {
    var executed = false;
    final denied = await generateText(
      model: ScriptedModel(
        turns: const <ScriptedTurn>[
          ScriptedTurn(
            content: <lm.LanguageModelContent>[
              lm.ToolCall(
                toolCallId: 'denied',
                toolName: 'delete',
                input: '{}',
              ),
            ],
            finishReason:
                lm.LanguageModelFinishReason(lm.FinishReasonType.toolCalls),
            usage: _usage,
          ),
        ],
      ),
      prompt: 'delete',
      tools: <String, Tool>{
        'delete': Tool(
          inputSchema: const lm.JsonSchema(<String, Object?>{
            'type': 'object',
          }),
          execute: (input, options) {
            executed = true;
            return 'deleted';
          },
        ),
      },
      toolApproval: const <String, Object?>{
        'delete': ToolApprovalStatus.denied(reason: 'policy'),
      },
    );
    expect(executed, isFalse);
    expect(
      denied.finalStep.toolResultOutputs.single,
      const lm.ToolResultExecutionDenied(reason: 'policy'),
    );

    final abortController = lm.CancellationController()
      ..cancel('scripted abort');
    final aborted = streamText(
      model: ScriptedModel(turns: <ScriptedTurn>[_textTurn('unused')]),
      prompt: 'abort',
      cancellation: abortController.signal,
    );
    final abortedParts = await aborted.stream.toList();
    expect(abortedParts.last, const AbortPart(reason: 'scripted abort'));
    expect(abortedParts.whereType<ErrorPart>(), isEmpty);

    final timedOut = streamText(
      model: _IdleStreamModel(),
      prompt: 'timeout',
      timeout: const TimeoutConfiguration(
        firstChunk: Duration(milliseconds: 30),
      ),
    );
    final timeoutParts = await timedOut.stream.toList();
    expect(
      timeoutParts.last,
      isA<ErrorPart>().having(
        (part) => part.error,
        'error',
        isA<TimeoutException>(),
      ),
    );
    expect(timeoutParts.whereType<AbortPart>(), isEmpty);
  });
}

final class _IdleStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted-peer';

  @override
  String get modelId => 'idle';

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
      },
      onCancel: () {},
    );
    return lm.LanguageModelStreamResult(stream: controller.stream);
  }
}
