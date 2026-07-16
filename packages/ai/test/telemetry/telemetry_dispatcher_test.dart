import 'dart:async';

import 'package:pigcode_ai/src/generate_text/lifecycle_events.dart';
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_dispatcher.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_events.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_registry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_settings.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../support/scripted_model.dart';

final class _Recorder with Telemetry {
  _Recorder([this.tag = '']);
  final String tag;
  final List<String> calls = [];
  LanguageModelCallStartEvent? lmStart;
  LanguageModelCallEndEvent? lmEnd;
  ToolExecutionStartEvent? toolStart;
  ToolExecutionEndEvent? toolEnd;
  GenerateTextStepStartEvent? stepStart;
  StepResult? stepEnd;
  GenerateTextEndEvent? end;
  TelemetryMetadata? meta;

  @override
  void onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) {
    calls.add('${tag}lmStart');
    lmStart = e;
    meta = m;
  }

  @override
  void onLanguageModelCallEnd(
      LanguageModelCallEndEvent e, TelemetryMetadata m) {
    calls.add('${tag}lmEnd');
    lmEnd = e;
    meta = m;
  }

  @override
  void onToolExecutionStart(ToolExecutionStartEvent e, TelemetryMetadata m) {
    calls.add('${tag}toolStart');
    toolStart = e;
  }

  @override
  void onToolExecutionEnd(ToolExecutionEndEvent e, TelemetryMetadata m) {
    calls.add('${tag}toolEnd');
    toolEnd = e;
  }

  @override
  void onStepStart(GenerateTextStepStartEvent e, TelemetryMetadata m) {
    calls.add('${tag}stepStart');
    stepStart = e;
  }

  @override
  void onStepEnd(StepResult step, TelemetryMetadata m) {
    calls.add('${tag}stepEnd');
    stepEnd = step;
  }

  @override
  void onEnd(GenerateTextEndEvent e, TelemetryMetadata m) {
    calls.add('${tag}end');
    end = e;
  }

  @override
  void onError(Object? error, TelemetryMetadata m) {
    calls.add('${tag}error');
    lastError = error;
  }

  Object? lastError;
}

StepResult _step({
  List<provider.LanguageModelContent> content = const [],
  List<provider.ToolResult> executedToolResults = const [],
  List<provider.ToolResultOutput> toolResultOutputs = const [],
  List<provider.ToolApprovalResponsePart> toolApprovalResponses = const [],
  Map<String, Object?> runtimeContext = const {},
  Map<String, Object?> toolsContext = const {},
  provider.ProviderMetadata? providerMetadata,
}) =>
    StepResult(
      content: content,
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(total: 3),
        outputTokens: provider.OutputTokens(total: 5),
      ),
      response: null,
      providerMetadata: providerMetadata,
      executedToolResults: executedToolResults,
      toolResultOutputs: toolResultOutputs,
      toolApprovalResponses: toolApprovalResponses,
      runtimeContext: runtimeContext,
      toolsContext: toolsContext,
      performance: StepResultPerformance.empty(),
    );

LanguageModelCallStartEvent _lmStart() => LanguageModelCallStartEvent(
      callId: 'c1',
      providerId: 'openai',
      modelId: 'gpt-4o',
      stepNumber: 0,
      messages: const [],
    );

LanguageModelCallEndEvent _lmEnd({
  List<provider.LanguageModelContent> content = const [],
}) =>
    LanguageModelCallEndEvent(
      callId: 'c1',
      providerId: 'openai',
      modelId: 'gpt-4o',
      stepNumber: 0,
      content: content,
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      warnings: const [],
      response: null,
      responseTime: Duration.zero,
    );

void main() {
  tearDown(clearTelemetryIntegrations);

  test('isEnabled:false makes every dispatch a no-op', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(isEnabled: false, integrations: [r]),
    );
    await d.dispatchLanguageModelCallStart(_lmStart());
    await d.dispatchError(StateError('x'));
    expect(r.calls, isEmpty);
  });

  test('per-call integrations take precedence over global', () async {
    final global = _Recorder('g:');
    final local = _Recorder('l:');
    registerTelemetry([global]);
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [local]));
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(local.calls, ['l:lmStart']);
    expect(global.calls, isEmpty);
  });

  test('falls back to global integrations when no per-call ones', () async {
    final global = _Recorder('g:');
    registerTelemetry([global]);
    final d = TelemetryDispatcher(const TelemetrySettings());
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(global.calls, ['g:lmStart']);
  });

  test('recordInputs:false clears messages and tool input', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r]),
    );
    await d.dispatchLanguageModelCallStart(
      LanguageModelCallStartEvent(
        callId: 'c1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        messages: const [],
      ),
    );
    await d.dispatchToolExecutionStart(const ToolExecutionStartEvent(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'lookup',
      input: {'q': 'secret'},
      toolContext: null,
    ));
    expect(r.lmStart!.messages, isEmpty);
    expect(r.toolStart!.input, isNull);
  });

  test('recordOutputs:false clears model content and tool output', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordOutputs: false, integrations: [r]),
    );
    await d.dispatchLanguageModelCallEnd(
      _lmEnd(content: const [provider.TextContent('secret')]),
    );
    await d.dispatchToolExecutionEnd(const ToolExecutionEndSuccess(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'lookup',
      output: {'secret': true},
      toolExecutionMs: 1,
    ));
    expect(r.lmEnd!.content, isEmpty);
    expect((r.toolEnd! as ToolExecutionEndSuccess).output, isNull);
  });

  test('recordOutputs:false clears nested StepResult output but keeps usage',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordOutputs: false, integrations: [r]),
    );
    final step = _step(
      content: const [provider.TextContent('secret')],
      executedToolResults: const [
        provider.ToolResult(toolCallId: 't1', toolName: 'x', result: 'r'),
      ],
    );
    await d.dispatchStepEnd(step);
    await d.dispatchEnd(GenerateTextEndEvent(steps: [step]));
    // onStepEnd 的 StepResult 脱敏:
    expect(r.stepEnd!.content, isEmpty);
    expect(r.stepEnd!.executedToolResults, isEmpty);
    // 保留统计:
    expect(r.stepEnd!.usage.inputTokens.total, 3);
    expect(r.stepEnd!.finishReason.unified, provider.FinishReasonType.stop);
    // onEnd 内嵌 steps 也脱敏:
    expect(r.end!.steps.single.content, isEmpty);
    expect(r.end!.usage.outputTokens.total, 5); // 聚合 getter 仍工作
  });

  test(
      'recordOutputs:false nulls StepResult.providerMetadata on all three '
      'sanitized paths (onStepStart embedded steps / onStepEnd / onEnd)',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordOutputs: false, integrations: [r]),
    );
    final step = _step(
      providerMetadata: const {
        'anthropic': {
          'container': {'id': 'container-1'},
        },
      },
    );
    await d.dispatchStepStart(GenerateTextStepStartEvent(
      stepNumber: 1,
      model: ScriptedModel(turns: const []),
      messages: const [],
      steps: [step],
    ));
    await d.dispatchStepEnd(step);
    await d.dispatchEnd(GenerateTextEndEvent(steps: [step]));

    expect(r.stepStart!.steps.single.providerMetadata, isNull);
    expect(r.stepEnd!.providerMetadata, isNull);
    expect(r.end!.steps.single.providerMetadata, isNull);
    // 非 output 字段照旧保留(既有 _sanitizeStep 语义不回归)。
    expect(r.stepEnd!.usage, step.usage);
  });

  test(
      'recordOutputs:true passes StepResult.providerMetadata through by '
      'reference (no deep-freeze) on all three sanitized paths', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [r]));
    const metadata = <String, provider.JsonObject>{
      'anthropic': {
        'container': {'id': 'container-1'},
      },
    };
    final step = _step(providerMetadata: metadata);
    await d.dispatchStepStart(GenerateTextStepStartEvent(
      stepNumber: 1,
      model: ScriptedModel(turns: const []),
      messages: const [],
      steps: [step],
    ));
    await d.dispatchStepEnd(step);
    await d.dispatchEnd(GenerateTextEndEvent(steps: [step]));

    expect(identical(r.stepStart!.steps.single.providerMetadata, metadata),
        isTrue);
    expect(identical(r.stepEnd!.providerMetadata, metadata), isTrue);
    expect(identical(r.end!.steps.single.providerMetadata, metadata), isTrue);
  });

  test('includeRuntimeContext allowlists StepResult.runtimeContext', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(
        includeRuntimeContext: const {'userId': true},
        integrations: [r],
      ),
    );
    await d.dispatchStepEnd(_step(
      runtimeContext: const {'userId': 'u1', 'secret': 's'},
    ));
    expect(r.stepEnd!.runtimeContext, {'userId': 'u1'});
  });

  test('runtimeContext excluded by default (no includeRuntimeContext)',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [r]));
    await d.dispatchStepEnd(_step(
      runtimeContext: const {'userId': 'u1'},
    ));
    expect(r.stepEnd!.runtimeContext, isEmpty);
  });

  test('includeToolsContext allowlists map tool context; non-map excluded',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(
        includeToolsContext: const {
          'search': {'region': true}
        },
        integrations: [r],
      ),
    );
    // map context → 按键过滤
    await d.dispatchToolExecutionStart(const ToolExecutionStartEvent(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'search',
      input: null,
      toolContext: {'region': 'us', 'secret': 'x'},
    ));
    expect(r.toolStart!.toolContext, {'region': 'us'});

    // 非 map context → 排除
    final r2 = _Recorder();
    final d2 = TelemetryDispatcher(
      TelemetrySettings(
        includeToolsContext: const {
          'search': {'region': true}
        },
        integrations: [r2],
      ),
    );
    await d2.dispatchToolExecutionStart(const ToolExecutionStartEvent(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'search',
      input: null,
      toolContext: 'not-a-map',
    ));
    expect(r2.toolStart!.toolContext, isNull);
  });

  test('fans out to multiple integrations', () async {
    final a = _Recorder('a:');
    final b = _Recorder('b:');
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [a, b]));
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(a.calls, ['a:lmStart']);
    expect(b.calls, ['b:lmStart']);
  });

  test('error in one integration is isolated and logged; others still run',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final bad = _Throwing();
    final good = _Recorder('good:');
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [bad, good]));

    // 不冒泡:
    await d.dispatchLanguageModelCallStart(_lmStart());

    expect(good.calls, ['good:lmStart']);
    expect(
      records.where((r) => r.level == Level.WARNING),
      isNotEmpty,
    );
  });

  test('awaits async integration callbacks', () async {
    final slow = _Slow();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [slow]));
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(slow.done, isTrue);
  });

  test('injects TelemetryMetadata with functionId and record flags', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(
        functionId: 'chatbot',
        recordInputs: false,
        integrations: [r],
      ),
    );
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(r.meta!.functionId, 'chatbot');
    expect(r.meta!.recordInputs, isFalse);
    expect(r.meta!.recordOutputs, isTrue);
  });

  test('recordOutputs:false nulls LanguageModelCallEnd.response (raw body)',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordOutputs: false, integrations: [r]),
    );
    await d.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
      callId: 'c1',
      providerId: 'openai',
      modelId: 'gpt-4o',
      stepNumber: 0,
      content: const [provider.TextContent('secret')],
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      warnings: const [],
      // response.body 承载原始 provider 响应体(可能含生成文本/工具输出)。
      response: const provider.ResponseInfo(id: 'resp', body: 'RAW OUTPUT'),
      responseTime: Duration.zero,
    ));
    expect(r.lmEnd!.content, isEmpty);
    expect(r.lmEnd!.response, isNull);
  });

  test('snapshots per-call integrations at construction (post-mutation safe)',
      () async {
    final a = _Recorder('a:');
    final added = _Recorder('added:');
    // 可变列表:构造 dispatcher 后再改动它,不得影响已开始调用的投递集。
    final integrations = <Telemetry>[a];
    final d =
        TelemetryDispatcher(TelemetrySettings(integrations: integrations));
    integrations.add(added);
    await d.dispatchLanguageModelCallStart(_lmStart());
    expect(a.calls, ['a:lmStart']);
    expect(added.calls, isEmpty);
  });

  test('snapshots includeRuntimeContext at construction (post-mutation safe)',
      () async {
    final r = _Recorder();
    final include = <String, bool>{'userId': true};
    final d = TelemetryDispatcher(
      TelemetrySettings(includeRuntimeContext: include, integrations: [r]),
    );
    // 构造后改动白名单 map,不得中途放宽已开始调用的过滤。
    include['secret'] = true;
    await d.dispatchStepEnd(_step(
      runtimeContext: const {'userId': 'u1', 'secret': 's'},
    ));
    expect(r.stepEnd!.runtimeContext, {'userId': 'u1'});
  });

  test('snapshots includeToolsContext at construction (post-mutation safe)',
      () async {
    final r = _Recorder();
    final inner = <String, bool>{'region': true};
    final include = <String, Map<String, bool>>{'search': inner};
    final d = TelemetryDispatcher(
      TelemetrySettings(includeToolsContext: include, integrations: [r]),
    );
    inner['secret'] = true; // 改内层白名单
    await d.dispatchToolExecutionStart(const ToolExecutionStartEvent(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'search',
      input: null,
      toolContext: {'region': 'us', 'secret': 'x'},
    ));
    expect(r.toolStart!.toolContext, {'region': 'us'});
  });

  test('recordInputs:false redacts ToolCall.input in content (outputs kept)',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r]),
    );
    await d.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
      callId: 'c1',
      providerId: 'openai',
      modelId: 'gpt-4o',
      stepNumber: 0,
      content: const [
        provider.ToolCall(
          toolCallId: 't1',
          toolName: 'lookup',
          input: '{"ssn":"123"}',
          providerMetadata: {
            'openai': {'rawItem': 'args'}
          },
        ),
        provider.TextContent('hello'),
      ],
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      warnings: const [],
      response: const provider.ResponseInfo(id: 'resp', body: 'RAW tool args'),
      responseTime: Duration.zero,
    ));
    final content = r.lmEnd!.content;
    final redactedCall = content.whereType<provider.ToolCall>().single;
    expect(redactedCall.input, '{}');
    // providerMetadata 也置空(provider 常把含参数的原始 item 存于此)。
    expect(redactedCall.providerMetadata, isNull);
    // recordOutputs=true:文本输出保留;但 response.body(不透明,含工具参数)
    // 剥离、response 元数据(id)保留。
    expect(content.whereType<provider.TextContent>().single.text, 'hello');
    expect(r.lmEnd!.response?.id, 'resp');
    expect(r.lmEnd!.response?.body, isNull);

    // StepResult.content 内的 ToolCall.input 同样脱敏。
    final r2 = _Recorder();
    final d2 = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r2]),
    );
    await d2.dispatchStepEnd(_step(content: const [
      provider.ToolCall(
        toolCallId: 't1',
        toolName: 'lookup',
        input: '{"ssn":"123"}',
      ),
    ]));
    expect(
        r2.stepEnd!.content.whereType<provider.ToolCall>().single.input, '{}');
  });

  test('tool input/output delivered to integrations are deep-unmodifiable',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [r]));
    // 与生成循环共享的可变结构:集成不得能改动它们(观察者不影响生成)。
    final input = <String, Object?>{
      'q': 'dart',
      'nested': <Object?>['a']
    };
    final output = <String, Object?>{
      'rows': <Object?>[1]
    };
    await d.dispatchToolExecutionStart(ToolExecutionStartEvent(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'lookup',
      input: input,
      toolContext: null,
    ));
    await d.dispatchToolExecutionEnd(ToolExecutionEndSuccess(
      callId: 'e1',
      toolCallId: 't1',
      toolName: 'lookup',
      output: output,
      toolExecutionMs: 1,
    ));
    final deliveredInput = r.toolStart!.input! as Map<String, Object?>;
    expect(() => deliveredInput['q'] = 'mutated', throwsUnsupportedError);
    expect(() => (deliveredInput['nested']! as List<Object?>).add('b'),
        throwsUnsupportedError);
    final deliveredOutput =
        (r.toolEnd! as ToolExecutionEndSuccess).output! as Map<String, Object?>;
    expect(() => deliveredOutput['rows'] = null, throwsUnsupportedError);
    // 原对象未被投递过程改动。
    expect(input, {
      'q': 'dart',
      'nested': ['a']
    });
    expect(output, {
      'rows': [1]
    });
  });

  test('lmEnd content ToolResult.result and response.body are deep-frozen',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [r]));
    final toolResultJson = <String, Object?>{
      'rows': <Object?>[1]
    };
    final rawBody = <String, Object?>{'raw': 'resp'};
    await d.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
      callId: 'c1',
      providerId: 'openai',
      modelId: 'gpt-4o',
      stepNumber: 0,
      content: [
        provider.ToolResult(
          toolCallId: 't1',
          toolName: 'lookup',
          result: toolResultJson,
        ),
      ],
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      warnings: const [],
      response: provider.ResponseInfo(
        id: 'resp',
        body: rawBody,
        headers: <String, String>{'x-req': 'abc'},
      ),
      responseTime: Duration.zero,
    ));
    final deliveredResult = r.lmEnd!.content
        .whereType<provider.ToolResult>()
        .single
        .result! as Map<String, Object?>;
    expect(() => deliveredResult['rows'] = null, throwsUnsupportedError);
    final deliveredBody = r.lmEnd!.response!.body! as Map<String, Object?>;
    expect(() => deliveredBody['raw'] = 'mutated', throwsUnsupportedError);
    // headers 同样不可变。
    expect(() => r.lmEnd!.response!.headers!['x-req'] = 'mutated',
        throwsUnsupportedError);
    // 原对象未被投递过程改动。
    expect(toolResultJson, {
      'rows': [1]
    });
    expect(rawBody, {'raw': 'resp'});
  });

  test('stepEnd executedToolResults/toolResultOutputs are deep-frozen',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(TelemetrySettings(integrations: [r]));
    final resultJson = <String, Object?>{
      'rows': <Object?>[1]
    };
    final outputJson = <String, Object?>{'v': 1};
    await d.dispatchStepEnd(StepResult(
      content: const [],
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
      response: null,
      executedToolResults: [
        provider.ToolResult(
          toolCallId: 't1',
          toolName: 'lookup',
          result: resultJson,
        ),
      ],
      toolResultOutputs: [provider.ToolResultJson(outputJson)],
      performance: StepResultPerformance.empty(),
    ));
    final deliveredResult =
        r.stepEnd!.executedToolResults.single.result! as Map<String, Object?>;
    expect(() => deliveredResult['rows'] = null, throwsUnsupportedError);
    final deliveredOutput =
        (r.stepEnd!.toolResultOutputs.single as provider.ToolResultJson).value!
            as Map<String, Object?>;
    expect(() => deliveredOutput['v'] = 2, throwsUnsupportedError);
    // 原对象未被投递过程改动。
    expect(resultJson, {
      'rows': [1]
    });
    expect(outputJson, {'v': 1});
  });

  test('recordInputs:false redacts denied approval reasons in step outputs',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r]),
    );
    await d.dispatchStepEnd(_step(
      executedToolResults: const [
        provider.ToolResult(
          toolCallId: 't1',
          toolName: 'delete_file',
          result: 'user said: contains secret rationale',
          isError: true,
        ),
      ],
      toolResultOutputs: const [
        provider.ToolResultExecutionDenied(
          reason: 'contains secret rationale',
          providerOptions: {
            'x': {'k': 'v'}
          },
        ),
      ],
    ));
    // denied 的 reason(输入侧)从两个出口都剥离:
    final output = r.stepEnd!.toolResultOutputs.single
        as provider.ToolResultExecutionDenied;
    expect(output.reason, isNull);
    expect(output.providerOptions, isNull);
    expect(
        r.stepEnd!.executedToolResults.single.result, 'Tool execution denied');
    // recordInputs=true(默认)时原样保留。
    final r2 = _Recorder();
    final d2 = TelemetryDispatcher(TelemetrySettings(integrations: [r2]));
    await d2.dispatchStepEnd(_step(
      toolResultOutputs: const [
        provider.ToolResultExecutionDenied(reason: 'keep me'),
      ],
    ));
    expect(
        (r2.stepEnd!.toolResultOutputs.single
                as provider.ToolResultExecutionDenied)
            .reason,
        'keep me');
  });

  test('recordInputs:false redacts InvalidPromptError.prompt in onError',
      () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r]),
    );
    await d.dispatchError(const provider.InvalidPromptError(
      prompt: 'raw secret prompt',
      message: 'prompt and messages are mutually exclusive',
    ));
    final delivered = r.lastError! as provider.InvalidPromptError;
    expect(delivered.prompt, isNull);
    expect(delivered.message, 'prompt and messages are mutually exclusive');

    // recordInputs=true(默认)时原样投递;其他错误类型恒原样。
    final r2 = _Recorder();
    final d2 = TelemetryDispatcher(TelemetrySettings(integrations: [r2]));
    const original = provider.InvalidPromptError(
      prompt: 'raw prompt',
      message: 'm',
    );
    await d2.dispatchError(original);
    expect(identical(r2.lastError, original), isTrue);
  });

  test('recordInputs:false redacts tool approval response reason', () async {
    final r = _Recorder();
    final d = TelemetryDispatcher(
      TelemetrySettings(recordInputs: false, integrations: [r]),
    );
    await d.dispatchStepEnd(_step(toolApprovalResponses: const [
      provider.ToolApprovalResponsePart(
        approvalId: 'a1',
        approved: true,
        reason: 'contains secret rationale',
        providerOptions: {
          'x': {'k': 'v'}
        },
      ),
    ]));
    final resp = r.stepEnd!.toolApprovalResponses.single;
    // 决定保留,理由/透传选项(输入侧)脱敏。
    expect(resp.approvalId, 'a1');
    expect(resp.approved, isTrue);
    expect(resp.reason, isNull);
    expect(resp.providerOptions, isNull);
  });
}

final class _Throwing with Telemetry {
  @override
  void onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) {
    throw StateError('integration boom');
  }
}

final class _Slow with Telemetry {
  bool done = false;
  @override
  Future<void> onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    done = true;
  }
}
