import 'package:pigcode_ai/src/generate_text/generate_text.dart';
import 'package:pigcode_ai/src/generate_text/lifecycle_events.dart';
import 'package:pigcode_ai/src/generate_text/output.dart';
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/generate_text/tool_approval.dart';
import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_events.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_registry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_settings.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
// 别名 lm 用于 _ThrowingGenerateModel:其 `String get provider` 会遮蔽 provider 前缀。
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

final class _Seq with Telemetry {
  final List<String> seq = [];
  LanguageModelCallEndEvent? lmEnd;
  final List<ToolExecutionEndEvent> toolEnds = [];

  @override
  void onStart(GenerateTextStartEvent e, TelemetryMetadata m) =>
      seq.add('start');
  @override
  void onStepStart(GenerateTextStepStartEvent e, TelemetryMetadata m) =>
      seq.add('stepStart');
  @override
  void onLanguageModelCallStart(
          LanguageModelCallStartEvent e, TelemetryMetadata m) =>
      seq.add('lmStart');
  @override
  void onLanguageModelCallEnd(
      LanguageModelCallEndEvent e, TelemetryMetadata m) {
    seq.add('lmEnd');
    lmEnd = e;
  }

  @override
  void onToolExecutionStart(ToolExecutionStartEvent e, TelemetryMetadata m) =>
      seq.add('toolStart');
  @override
  void onToolExecutionEnd(ToolExecutionEndEvent e, TelemetryMetadata m) {
    seq.add('toolEnd');
    toolEnds.add(e);
  }

  @override
  void onStepEnd(StepResult step, TelemetryMetadata m) => seq.add('stepEnd');
  @override
  void onEnd(GenerateTextEndEvent e, TelemetryMetadata m) => seq.add('end');
  @override
  void onError(Object? error, TelemetryMetadata m) => seq.add('error');
}

ScriptedModel _textModel() => ScriptedModel(turns: [
      const ScriptedTurn(
        content: [provider.TextContent('hi')],
        finishReason: provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        usage: provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 7),
          outputTokens: provider.OutputTokens(total: 3),
        ),
      ),
    ]);

ScriptedModel _toolCallModel() => ScriptedModel(turns: [
      const ScriptedTurn(
        content: [
          provider.ToolCall(
            toolCallId: 'call-1',
            toolName: 'lookup',
            input: '{}',
          ),
        ],
        finishReason: provider.LanguageModelFinishReason(
          provider.FinishReasonType.toolCalls,
        ),
        usage: provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(total: 4),
          outputTokens: provider.OutputTokens(total: 2),
        ),
      ),
    ]);

void main() {
  tearDown(clearTelemetryIntegrations);

  test('single step (no tools) emits ordered lifecycle events', () async {
    final t = _Seq();
    await generateText(
      model: _textModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    expect(t.seq, ['start', 'stepStart', 'lmStart', 'lmEnd', 'stepEnd', 'end']);
    expect(t.lmEnd!.usage.inputTokens.total, 7);
    expect(t.lmEnd!.finishReason.unified, provider.FinishReasonType.stop);
    expect(t.lmEnd!.providerId, 'scripted');
  });

  test('tool execution emits start/end(success) between lmEnd and stepEnd',
      () async {
    final t = _Seq();
    await generateText(
      model: _toolCallModel(),
      prompt: 'run lookup',
      tools: {
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ok',
        ),
      },
      telemetry: TelemetrySettings(integrations: [t]),
    );
    expect(t.seq, [
      'start',
      'stepStart',
      'lmStart',
      'lmEnd',
      'toolStart',
      'toolEnd',
      'stepEnd',
      'end',
    ]);
    final end = t.toolEnds.single;
    expect(end, isA<ToolExecutionEndSuccess>());
    expect(end.toolCallId, 'call-1');
    expect(end.toolExecutionMs, greaterThanOrEqualTo(0));
  });

  test('tool execute error emits ToolExecutionEndError and onError; rethrows',
      () async {
    final t = _Seq();
    await expectLater(
      generateText(
        model: _toolCallModel(),
        prompt: 'run lookup',
        tools: {
          'lookup': Tool(
            inputSchema: const provider.JsonSchema({'type': 'object'}),
            execute: (input, options) async => throw StateError('boom'),
          ),
        },
        telemetry: TelemetrySettings(integrations: [t]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(t.toolEnds.single, isA<ToolExecutionEndError>());
    // 工具错误经 generate 外层 catch 派 onError;不构建 step,故无 stepEnd/end。
    expect(t.seq, [
      'start',
      'stepStart',
      'lmStart',
      'lmEnd',
      'toolStart',
      'toolEnd',
      'error'
    ]);
  });

  test('global registry receives events without a per-call telemetry param',
      () async {
    final g = _Seq();
    registerTelemetry([g]);
    await generateText(model: _textModel(), prompt: 'x');
    expect(g.seq, ['start', 'stepStart', 'lmStart', 'lmEnd', 'stepEnd', 'end']);
  });

  test('per-call integrations take precedence over global', () async {
    final g = _Seq();
    final local = _Seq();
    registerTelemetry([g]);
    await generateText(
      model: _textModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [local]),
    );
    expect(local.seq, isNotEmpty);
    expect(g.seq, isEmpty);
  });

  test(
      'C3: structured Output parse failure emits onError, never telemetry '
      'onEnd before it', () async {
    final t = _Seq();
    await expectLater(
      generateText(
        model: ScriptedModel(turns: [
          const ScriptedTurn(
            content: [provider.TextContent('not json')],
            finishReason: provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop,
            ),
            usage: provider.LanguageModelUsage(
              inputTokens: provider.InputTokens(total: 1),
              outputTokens: provider.OutputTokens(total: 1),
            ),
          ),
        ]),
        prompt: 'make object',
        output: Output.object(
          schema: const provider.JsonSchema({'type': 'object'}),
        ),
        telemetry: TelemetrySettings(integrations: [t]),
      ),
      throwsA(isA<provider.NoObjectGeneratedError>()),
    );
    // telemetry dispatchEnd 在 parse 成功之后:parse 失败 → 只 onError,无 telemetry 'end'。
    expect(t.seq, contains('error'));
    expect(t.seq, isNot(contains('end')));
    expect(t.seq.indexOf('stepEnd'), lessThan(t.seq.indexOf('error')));
  });

  test('no telemetry configured behaves identically (regression)', () async {
    final result = await generateText(model: _textModel(), prompt: 'x');
    expect(result.text, 'hi');
  });

  test('C2: resumed-approval tool execution emits tool telemetry', () async {
    final tools = <String, Tool>{
      'delete_file': Tool(
        inputSchema: const provider.JsonSchema({'type': 'object'}),
        execute: (input, options) async => 'deleted',
      ),
    };
    final first = await generateText(
      model: ScriptedModel(turns: [
        const ScriptedTurn(
          content: [
            provider.ToolCall(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: '{"path":"a.txt"}',
            ),
          ],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.toolCalls,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]),
      prompt: 'delete it',
      tools: tools,
      toolApproval: const {
        'delete_file': ToolApprovalStatus.userApproval,
      },
    );
    final approvalId = first.responseMessages
        .whereType<AssistantModelMessage>()
        .single
        .content
        .whereType<ToolApprovalRequestPart>()
        .single
        .approvalId;

    final t = _Seq();
    await generateText(
      model: ScriptedModel(turns: [
        const ScriptedTurn(
          content: [provider.TextContent('done')],
          finishReason: provider.LanguageModelFinishReason(
            provider.FinishReasonType.stop,
          ),
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(total: 1),
            outputTokens: provider.OutputTokens(total: 1),
          ),
        ),
      ]),
      messages: [
        UserModelMessage.text('delete it'),
        ...first.responseMessages,
        ToolModelMessage([
          ToolApprovalResponsePart(
            approvalId: approvalId,
            approved: true,
            reason: 'ok',
          ),
        ]),
      ],
      tools: tools,
      telemetry: TelemetrySettings(integrations: [t]),
    );

    // resumed-approval 的工具执行发生在首个模型调用之前(_executeResumedToolApprovals)。
    expect(t.seq, contains('toolStart'));
    expect(t.seq, contains('toolEnd'));
    expect(t.seq.indexOf('toolStart'), lessThan(t.seq.indexOf('stepStart')));
    final end = t.toolEnds.single;
    expect(end, isA<ToolExecutionEndSuccess>());
    expect(end.toolCallId, 'call-delete');
  });

  test('preflight prompt error emits telemetry onError (no onStart)', () async {
    final t = _Seq();
    await expectLater(
      // prompt 与 messages 同时缺失 → standardizePrompt 抛错(preflight)。
      generateText(
        model: _textModel(),
        telemetry: TelemetrySettings(integrations: [t]),
      ),
      throwsA(anything),
    );
    // 与流式路径对称:preflight 失败派 onError,不派 onStart。
    expect(t.seq, ['error']);
  });

  test('doGenerate throws: lmStart pairs with lmEnd(error); onError once',
      () async {
    final t = _Seq();
    await expectLater(
      generateText(
        model: _ThrowingGenerateModel(),
        prompt: 'x',
        telemetry: TelemetrySettings(integrations: [t]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(t.seq.where((s) => s == 'lmStart').length, 1);
    expect(t.seq.where((s) => s == 'lmEnd').length, 1);
    expect(t.seq.where((s) => s == 'error').length, 1);
    expect(t.lmEnd!.finishReason.unified, provider.FinishReasonType.error);
  });
}

/// doGenerate 直接抛错的最小 fake,验证 lmStart 恒配对 lmEnd(error)。
final class _ThrowingGenerateModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';
  @override
  String get provider => 'throwing';
  @override
  String get modelId => 'throwing-model';
  @override
  Map<String, List<RegExp>> get supportedUrls => const {};
  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw StateError('doGenerate boom');
  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw UnimplementedError();
}
