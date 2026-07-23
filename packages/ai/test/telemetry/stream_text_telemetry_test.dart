import 'dart:async';

import 'package:pigcode_ai/src/generate_text/lifecycle_events.dart';
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/generate_text/stop_condition.dart'
    show isStepCount;
import 'package:pigcode_ai/src/generate_text/output.dart';
import 'package:pigcode_ai/src/generate_text/stream_text.dart';
import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai/src/generate_text/tool_approval.dart';
import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_events.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_registry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_settings.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

/// 记录型 telemetry 集成:收集事件序列 + 关键事件对象,供断言。
final class _Seq with Telemetry {
  final List<String> seq = [];
  final List<LanguageModelCallStartEvent> lmStarts = [];
  final List<LanguageModelCallEndEvent> lmEnds = [];
  final List<ToolExecutionEndEvent> toolEnds = [];
  final List<GenerateTextAbortEvent> aborts = [];
  int errorCount = 0;

  @override
  void onStart(GenerateTextStartEvent e, TelemetryMetadata m) =>
      seq.add('start');
  @override
  void onStepStart(GenerateTextStepStartEvent e, TelemetryMetadata m) =>
      seq.add('stepStart');
  @override
  void onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) {
    seq.add('lmStart');
    lmStarts.add(e);
  }

  @override
  void onLanguageModelCallEnd(
      LanguageModelCallEndEvent e, TelemetryMetadata m) {
    seq.add('lmEnd');
    lmEnds.add(e);
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
  void onAbort(GenerateTextAbortEvent e, TelemetryMetadata m) {
    seq.add('abort');
    aborts.add(e);
  }

  @override
  void onError(Object? error, TelemetryMetadata m) {
    seq.add('error');
    errorCount++;
  }
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

ScriptedModel _toolThenTextModel() => ScriptedModel(turns: [
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
    ]);

/// 最小 fake:doStream 发 StreamStart 后立即在流中途**抛异常**(非 ErrorPart),
/// 用于验证 site ③(外层 catch)统一派一次 telemetry error。
final class _ThrowingStreamModel implements lm.LanguageModel {
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
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async =>
      lm.LanguageModelStreamResult(
        stream: () async* {
          yield lm.StreamStart(const []);
          throw StateError('mid-stream boom');
        }(),
      );
}

/// 最小 fake:`doStream` 本身抛异常(尚未返回流),验证 lmStart 恒配对 lmEnd(error)。
final class _DoStreamThrowsModel implements lm.LanguageModel {
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
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async =>
      throw StateError('doStream boom');
}

/// 最小 fake:发出 TextStart/TextDelta(未闭合)后流中途抛异常,用于验证 catch
/// 路径的 lmEnd 冲刷未闭合文本缓冲(partial 保真)。
final class _TextThenThrowsModel implements lm.LanguageModel {
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
      throw UnimplementedError();

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    Stream<lm.LanguageModelStreamPart> parts() async* {
      yield lm.StreamStart(const []);
      yield const lm.TextStart('txt_1');
      yield const lm.TextDelta('txt_1', 'partial');
      throw StateError('disconnect');
    }

    return lm.LanguageModelStreamResult(stream: parts());
  }
}

void main() {
  // Compatibility fixture (unit): P1-CORE-13
  tearDown(clearTelemetryIntegrations);

  test('single step (no tools): start->stepStart->lmStart->lmEnd->stepEnd->end',
      () async {
    final t = _Seq();
    final result = streamText(
      model: _textModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    expect(t.seq, ['start', 'stepStart', 'lmStart', 'lmEnd', 'stepEnd', 'end']);
    expect(t.lmEnds.single.usage.inputTokens.total, 7);
    expect(
        t.lmEnds.single.finishReason.unified, provider.FinishReasonType.stop);
    expect(t.lmEnds.single.providerId, 'scripted');
  });

  test('single tool call: toolStart/toolEnd(success) between lmEnd and stepEnd',
      () async {
    final t = _Seq();
    final result = streamText(
      model: _toolThenTextModel(),
      prompt: 'run lookup',
      tools: {
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ok',
        ),
      },
      stopWhen: isStepCount(2),
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    // 第一步:lmEnd → toolStart → toolEnd → stepEnd;第二步:lmStart → lmEnd → stepEnd。
    expect(t.seq, [
      'start',
      'stepStart',
      'lmStart',
      'lmEnd',
      'toolStart',
      'toolEnd',
      'stepEnd',
      'stepStart',
      'lmStart',
      'lmEnd',
      'stepEnd',
      'end',
    ]);
    final end = t.toolEnds.single;
    expect(end, isA<ToolExecutionEndSuccess>());
    expect(end.toolCallId, 'call-1');
    expect(end.toolExecutionMs, greaterThanOrEqualTo(0));
  });

  test('C4: every lmStart pairs with an lmEnd on the normal path', () async {
    final t = _Seq();
    final result = streamText(
      model: _toolThenTextModel(),
      prompt: 'run lookup',
      tools: {
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => 'ok',
        ),
      },
      stopWhen: isStepCount(2),
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    expect(t.lmStarts, hasLength(2));
    expect(t.lmEnds, hasLength(2));
    for (var i = 0; i < t.lmStarts.length; i++) {
      expect(t.lmEnds[i].callId, t.lmStarts[i].callId);
    }
  });

  test(
      'error site ①(provider ErrorPart): onError once, lmStart paired with '
      'an error lmEnd', () async {
    final t = _Seq();
    // TextThenErrorStreamModel 发一个完整文本块后再发终端 ErrorPart(site ①)。
    final result = streamText(
      model: TextThenErrorStreamModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    expect(t.errorCount, 1);
    expect(t.lmStarts, hasLength(1));
    expect(t.lmEnds, hasLength(1));
    expect(t.lmEnds.single.callId, t.lmStarts.single.callId);
    expect(
        t.lmEnds.single.finishReason.unified, provider.FinishReasonType.error);
    // provider ErrorPart 终端:end 不派,error 恰好一次,序列含 stepEnd 后 error。
    expect(t.seq, isNot(contains('end')));
    expect(t.seq.indexOf('lmEnd'), lessThan(t.seq.indexOf('error')));
    expect(t.seq.indexOf('stepEnd'), lessThan(t.seq.indexOf('error')));
  });

  test('error site ③(model throws mid-stream): onError exactly once', () async {
    final t = _Seq();
    final result = streamText(
      model: _ThrowingStreamModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    expect(t.errorCount, 1);
    expect(t.seq, isNot(contains('end')));
    // C4(codex 复审):流「直接抛异常」终止(非 ErrorPart)时,lmStart 仍恒配对
    // 一个 lmEnd(finishReason=error),不给 callId 留孤儿 in-flight。
    expect(t.lmStarts, hasLength(1));
    expect(t.lmEnds, hasLength(1));
    expect(
        t.lmEnds.single.finishReason.unified, provider.FinishReasonType.error);
  });

  test('doStream itself throws: lmStart pairs with lmEnd(error); onError once',
      () async {
    final t = _Seq();
    final result = streamText(
      model: _DoStreamThrowsModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    // error-as-terminal:doStream 抛错被转成流上终端 ErrorPart,流不向消费者抛。
    await result.stream.toList();
    expect(t.errorCount, 1);
    expect(t.lmStarts, hasLength(1));
    expect(t.lmEnds, hasLength(1));
    expect(
        t.lmEnds.single.finishReason.unified, provider.FinishReasonType.error);
  });

  test('mid-stream throw after TextDelta: lmEnd flushes buffered partial text',
      () async {
    final t = _Seq();
    final result = streamText(
      model: _TextThenThrowsModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    // 断连前已投递的部分文本冲刷进 lmEnd.content(与 ErrorPart 分支一致,
    // partial 保真),不得记录成空输出。
    expect(t.lmEnds, hasLength(1));
    final text = t.lmEnds.single.content
        .whereType<provider.TextContent>()
        .map((c) => c.text)
        .join();
    expect(text, 'partial');
    expect(t.errorCount, 1);
  });

  test(
      'error site ②→③ dedup: tool execute throws -> onError exactly once, '
      'stepEnd sees error step, toolEnd is error variant', () async {
    final t = _Seq();
    final result = streamText(
      model: _toolThenTextModel(),
      prompt: 'run lookup',
      tools: {
        'lookup': Tool(
          inputSchema: const provider.JsonSchema({'type': 'object'}),
          execute: (input, options) async => throw StateError('boom'),
        ),
      },
      stopWhen: isStepCount(2),
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    // step 级 onError 恰好一次(不因 ②③ 各派而重复)。
    expect(t.errorCount, 1);
    // per-tool onToolExecutionEnd 走 error 变体(与 step 级 onError 不同粒度)。
    expect(t.toolEnds.single, isA<ToolExecutionEndError>());
    expect(
        (t.toolEnds.single as ToolExecutionEndError).error, isA<StateError>());
    // 内部工具 catch(②)派了 stepEnd(该步是 error 步),再 rethrow 到 ③ 派 error。
    expect(t.seq, contains('stepEnd'));
    expect(t.seq.indexOf('stepEnd'), lessThan(t.seq.indexOf('error')));
    // 该错误路径 lmStart 已配对 lmEnd(C4:模型侧流读完时已派)。
    expect(t.lmStarts, hasLength(1));
    expect(t.lmEnds, hasLength(1));
    expect(t.seq, isNot(contains('end')));
  });

  test('C2: resumed-approval tool execution emits toolStart/toolEnd', () async {
    final tools = <String, Tool>{
      'delete_file': Tool(
        inputSchema: const provider.JsonSchema({'type': 'object'}),
        execute: (input, options) async => 'deleted',
      ),
    };
    final first = streamText(
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
    await first.consumeStream();
    final firstResponseMessages = await first.responseMessages;
    final approvalId = firstResponseMessages
        .whereType<AssistantModelMessage>()
        .single
        .content
        .whereType<ToolApprovalRequestPart>()
        .single
        .approvalId;

    final t = _Seq();
    final second = streamText(
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
        ...firstResponseMessages,
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
    await second.stream.toList();

    // resumed-approval 的工具执行发生在首个模型调用之前。
    expect(t.seq, contains('toolStart'));
    expect(t.seq, contains('toolEnd'));
    expect(t.seq.indexOf('toolStart'), lessThan(t.seq.indexOf('stepStart')));
    final end = t.toolEnds.single;
    expect(end, isA<ToolExecutionEndSuccess>());
    expect(end.toolCallId, 'call-delete');
  });

  test('global registry receives events without a per-call telemetry param',
      () async {
    final g = _Seq();
    registerTelemetry([g]);
    final result = streamText(model: _textModel(), prompt: 'x');
    await result.stream.toList();
    expect(g.seq, ['start', 'stepStart', 'lmStart', 'lmEnd', 'stepEnd', 'end']);
  });

  test('per-call integrations take precedence over global', () async {
    final g = _Seq();
    final local = _Seq();
    registerTelemetry([g]);
    final result = streamText(
      model: _textModel(),
      prompt: 'x',
      telemetry: TelemetrySettings(integrations: [local]),
    );
    await result.stream.toList();
    expect(local.seq, isNotEmpty);
    expect(g.seq, isEmpty);
  });

  test('no telemetry configured: streaming behavior unchanged (regression)',
      () async {
    final result = streamText(model: _textModel(), prompt: 'x');
    expect(await result.text, 'hi');
    expect((await result.finishReason).unified, provider.FinishReasonType.stop);
  });

  test('existing onError callback behavior unchanged with telemetry active',
      () async {
    final t = _Seq();
    final errors = <Object?>[];
    final result = streamText(
      model: ErrorStreamModel(),
      prompt: 'x',
      onError: errors.add,
      telemetry: TelemetrySettings(integrations: [t]),
    );
    await result.stream.toList();
    expect(errors, ['boom']);
    expect(t.errorCount, 1);
  });

  test('external cancellation dispatches abort only, with the original reason',
      () async {
    final t = _Seq();
    final reason = StateError('user cancelled');
    final cancellation = provider.CancellationController()..cancel(reason);
    final model = _textModel();
    final result = streamText(
      model: model,
      prompt: 'x',
      cancellation: cancellation.signal,
      telemetry: TelemetrySettings(integrations: <Telemetry>[t]),
    );

    final parts = await result.stream.toList();

    expect(parts.last, isA<AbortPart>());
    expect(t.aborts, hasLength(1));
    expect(t.aborts.single.reason, same(reason));
    expect(t.aborts.single.steps, isEmpty);
    expect(t.seq.where((event) => event == 'abort'), hasLength(1));
    expect(t.seq, isNot(contains('end')));
    expect(t.seq, isNot(contains('error')));
    expect(t.errorCount, 0);
    expect(model.callCount, 0);
  });

  test(
      'stream structured output: telemetry onEnd fires on stream completion; '
      'parse failure surfaces via .output, not telemetry', () async {
    final t = _Seq();
    final result = streamText(
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
    );
    // 流成功收尾 → telemetry 派 onEnd(= 流完成)、非 onError。结构化 output 解析
    // 是惰性的:失败只在读 `.output` 时抛出,不进 telemetry(不为遥测提前解析,
    // 避免对自定义 Output 双重触发副作用/一次性解析器)。
    await result.stream.toList();
    expect(t.seq, contains('end'));
    expect(t.seq, isNot(contains('error')));
    await expectLater(
      result.output,
      throwsA(isA<provider.NoObjectGeneratedError>()),
    );
  });
}
