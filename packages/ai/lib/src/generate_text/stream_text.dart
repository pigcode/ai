import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../logger/log_warnings.dart';
import '../prompt/content_part.dart';
import '../prompt/from_language_model_prompt.dart';
import '../prompt/model_message.dart';
import '../prompt/standardize_prompt.dart';
import '../prompt/to_language_model_prompt.dart';
import '../telemetry/telemetry_dispatcher.dart';
import '../telemetry/telemetry_events.dart';
import '../telemetry/telemetry_settings.dart';
import '../tool/tool.dart';
import 'active_tools.dart';
import 'context.dart';
import 'lifecycle_events.dart';
import 'output.dart';
import 'output_utils.dart';
import 'performance.dart';
import 'prepare_step.dart';
import 'request_options_snapshot.dart';
import 'step_result.dart';
import 'stop_condition.dart';
import 'text_stream_part.dart';
import 'tool_approval.dart';
import 'tool_call_parser.dart';
import 'tool_call_repair.dart';
import 'tool_order.dart';

/// `streamText` 结果中需要额外包含的数据。
final class StreamTextInclude {
  const StreamTextInclude({this.rawChunks});

  /// 是否在流中透传 provider 原始分块。
  final bool? rawChunks;
}

/// 流式生成入口:同步返回 [StreamTextResult],内部惰性启动多步流式循环。
///
/// 与 `generateText` 共享同样的续/停判定逻辑(§7.3),仅将 `model.doStream`
/// 的分块实时转发为 [TextStreamPart] 事件,并在每步之间执行工具调用。
/// 错误是流上的终端事件([ErrorPart]),不会以抛异常的方式出现。
///
/// 参数二选一:`prompt` 或 `messages`(恰好一个非空,否则
/// [provider.InvalidPromptError],校验发生在 [standardizePrompt] 内)。
/// `stopWhen` 缺省时循环只跑一步(与 `generateText` 一致)。
///
/// provider 侧已执行(`providerExecuted`)的工具默认不驱动续接(v7 语义,详见
/// `generate_text/tool_loop.dart` 的边缘态说明);标记 `supportsDeferredResults`
/// 的 provider 工具例外——同响应无配对结果时经 `pendingDeferredToolCalls`
/// 自动续接。其余场景可把 `responseMessages` 续入下一轮请求自行发起。
///
/// [include.rawChunks] 会映射到每步的
/// [provider.LanguageModelCallOptions.includeRawChunks];为 `true` 时,
/// provider 侧若产出 [provider.RawPart] 分块,会被转发为 [RawStreamPart]
/// 事件(缺省 `null` 时该转发路径不可达)。
StreamTextResult<Complete, Partial, Element>
    streamText<Complete, Partial, Element>({
  required provider.LanguageModel model,
  String? prompt,
  List<ModelMessage>? messages,
  String? instructions,
  ToolSet? tools,
  provider.ToolChoice? toolChoice,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  double? topK,
  double? presencePenalty,
  double? frequencyPenalty,
  int? seed,
  List<String>? stopSequences,
  provider.ReasoningEffort? reasoning,
  Output<Complete, Partial, Element>? output,
  Object? stopWhen,
  provider.CancellationSignal? cancellation,
  Map<String, String>? headers,
  provider.ProviderOptions? providerOptions,
  RuntimeContext? runtimeContext,
  ToolsContext? toolsContext,
  ActiveTools? activeTools,
  ToolOrder? toolOrder,
  PrepareStepFunction? prepareStep,
  Object? toolApproval,
  ToolCallRepairFunction? repairToolCall,
  StreamTextInclude? include,
  GenerateTextOnStartCallback? onStart,
  GenerateTextOnStepStartCallback? onStepStart,
  void Function(StepResult step)? onStepEnd,
  GenerateTextOnEndCallback? onEnd,
  void Function(Object? error)? onError,
  TelemetrySettings? telemetry,
}) {
  final outputSpec =
      output ?? (Output.text() as Output<Complete, Partial, Element>);
  // telemetry dispatcher 在调用时刻(同步)构造:解析生效集成集合于此固定,
  // 与其余请求快照同源;无生效集成时 isActive==false,驱动内所有 dispatch 短路。
  final dispatcher = TelemetryDispatcher(telemetry);
  final responseFormat =
      output == null ? null : outputResponseFormat(outputSpec);
  // 在调用时刻(同步)标准化 + 转换,把 caller 持有的可变 messages 及其内部
  // content 子列表固化为全新、不可变的 provider prompt 快照:
  // convertToLanguageModelPrompt 为每条消息、每个 content part 新建结构,故
  // caller 在 streamText() 返回后改动其原始 list、或某条消息的 content list,
  // 都不再影响本次调用。转换若因非法输入抛 InvalidPromptError,在此同步捕获、
  // 交由 StreamTextResult 驱动作为流上的终端 ErrorPart 发出——streamText() 自身
  // 仍正常返回、不同步抛(保持 error-as-terminal)。
  List<provider.LanguageModelMessage>? initialMessages;
  List<ModelMessage>? startMessages;
  Object? promptError;
  try {
    final standardized = standardizePrompt(
      prompt: prompt,
      messages: messages,
      instructions: instructions,
    );
    initialMessages = convertToLanguageModelPrompt(standardized);
    startMessages = convertFromLanguageModelPrompt(
      initialMessages.where((message) => message is! provider.SystemMessage),
    );
  } catch (error) {
    promptError = error;
  }
  // 同理在调用时刻对 tools map 拍不可变快照,而非等 deferred 驱动里再拍:
  // 驱动 microtask 在 streamText() 返回之后才运行,若那时才读 tools,caller 在
  // 返回后、驱动运行前清空/改动该 map,会让首个模型调用广告不到工具、返回的
  // tool-call 被当作 blocking。
  final toolSet = tools == null ? null : Map<String, Tool>.unmodifiable(tools);
  // 同理:stopWhen 若是可变 List<StopCondition>,在调用时刻拍不可变副本再传入
  // 驱动。否则 caller 在 streamText() 返回后改动该列表(增删条件),会改掉驱动
  // 里激活的停条件(如 [isStepCount(2)] 被清空/替换),使流停/续与调用时刻请求
  // 不一致。单个 StopCondition / null 本就不可变,无需快照。
  final stopWhenSnapshot = stopWhen is List<StopCondition>
      ? List<StopCondition>.unmodifiable(stopWhen)
      : stopWhen;
  // 同理:stopSequences 若为可变 List<String>,在调用时刻拍不可变副本再传入
  // 驱动;否则 caller 在 streamText() 返回后改动它会改掉首个模型调用的停用词。
  final stopSequencesSnapshot =
      stopSequences == null ? null : List<String>.unmodifiable(stopSequences);
  // headers/providerOptions 同样在调用时刻拍快照:驱动 microtask 在
  // streamText() 返回后才运行,不能让 caller 随后对 Map 的改动污染本次请求。
  final headersSnapshot = snapshotHeaders(headers);
  final providerOptionsSnapshot = snapshotProviderOptions(providerOptions);
  final runtimeContextSnapshot = snapshotRuntimeContext(runtimeContext);
  final toolsContextSnapshot = snapshotToolsContext(toolsContext);
  final activeToolsSnapshot =
      activeTools == null ? null : List<String>.unmodifiable(activeTools);
  final toolOrderSnapshot =
      toolOrder == null ? null : List<String>.unmodifiable(toolOrder);
  final toolApprovalSnapshot = toolApproval is Map<String, Object?>
      ? Map<String, Object?>.unmodifiable(toolApproval)
      : toolApproval;
  return StreamTextResult._(
    model: model,
    instructions: instructions,
    startMessages: startMessages,
    initialMessages: initialMessages,
    promptError: promptError,
    tools: toolSet,
    toolChoice: toolChoice,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    topP: topP,
    topK: topK,
    presencePenalty: presencePenalty,
    frequencyPenalty: frequencyPenalty,
    seed: seed,
    stopSequences: stopSequencesSnapshot,
    reasoning: reasoning,
    output: outputSpec,
    responseFormat: responseFormat,
    stopWhen: stopWhenSnapshot,
    cancellation: cancellation,
    headers: headersSnapshot,
    providerOptions: providerOptionsSnapshot,
    runtimeContext: runtimeContextSnapshot,
    toolsContext: toolsContextSnapshot,
    activeTools: activeToolsSnapshot,
    toolOrder: toolOrderSnapshot,
    prepareStep: prepareStep,
    toolApproval: toolApprovalSnapshot,
    repairToolCall: repairToolCall,
    includeRawChunks: include?.rawChunks,
    onStart: onStart,
    onStepStart: onStepStart,
    onStepEnd: onStepEnd,
    onEnd: onEnd,
    onError: onError,
    dispatcher: dispatcher,
  );
}

/// 流式聚合 text/reasoning 内容块时使用的缓冲:累积正文文本,并跟踪该块
/// 当前已知的 providerMetadata。
///
/// metadata 合并语义逐字对齐 v7 `stream-text.ts` 的 `activeTextContent`/
/// `activeReasoningContent`:Start 事件的 metadata 打底,随后每个
/// Delta/End 事件若带非空 metadata 则覆盖之前的值(`part.providerMetadata
/// ?? activeText.providerMetadata`,最新非空值胜出);OpenAI Responses 流
/// 的 reasoning encrypted_content 就落在 End 事件,靠这条规则才能被捕获。
final class _StreamContentBuffer {
  _StreamContentBuffer(this.providerMetadata);

  final StringBuffer _text = StringBuffer();

  /// 该内容块当前已知的 providerMetadata(可能来自 Start,也可能已被
  /// 后续 Delta/End 覆盖)。
  provider.ProviderMetadata? providerMetadata;

  void write(String delta) => _text.write(delta);

  /// 若 [next] 非空,覆盖当前累积的 [providerMetadata]。
  void mergeMetadata(provider.ProviderMetadata? next) {
    providerMetadata = next ?? providerMetadata;
  }

  @override
  String toString() => _text.toString();
}

/// 已聚合的流式结果内部快照:由缓冲监听器在流结束时一次性产出。
final class _StreamTextAggregate {
  const _StreamTextAggregate({
    required this.text,
    required this.steps,
    required this.finishReason,
    required this.usage,
    required this.responseMessages,
  });

  final String text;
  final List<StepResult> steps;
  final provider.LanguageModelFinishReason finishReason;
  final provider.LanguageModelUsage usage;
  final List<ModelMessage> responseMessages;
}

/// `streamText` 的结果视图:内部把驱动循环产出的分块缓冲(buffered-replay),
/// 使 `.stream`/`.textStream` 可在任意时刻、被任意数量的消费者订阅,均能收到
/// 完整有序的分块序列(含已产出的历史分块 + 尚未产出的后续分块)。
///
/// 这满足设计 §9「多次消费/缓存已产出分块」与 §14 开放问题 #3 的约束:late
/// subscriber(例如先 `await result.text` 再订阅 `.stream`)不会丢事件。
final class StreamTextResult<Complete, Partial, Element> {
  StreamTextResult._({
    required provider.LanguageModel model,
    required String? instructions,
    required List<ModelMessage>? startMessages,
    required List<provider.LanguageModelMessage>? initialMessages,
    required Object? promptError,
    required ToolSet? tools,
    required provider.ToolChoice? toolChoice,
    required int? maxOutputTokens,
    required double? temperature,
    required double? topP,
    required double? topK,
    required double? presencePenalty,
    required double? frequencyPenalty,
    required int? seed,
    required List<String>? stopSequences,
    required provider.ReasoningEffort? reasoning,
    required Output<Complete, Partial, Element> output,
    required provider.ResponseFormat? responseFormat,
    required Object? stopWhen,
    required provider.CancellationSignal? cancellation,
    required Map<String, String>? headers,
    required provider.ProviderOptions? providerOptions,
    required RuntimeContext runtimeContext,
    required ToolsContext toolsContext,
    required ActiveTools? activeTools,
    required ToolOrder? toolOrder,
    required PrepareStepFunction? prepareStep,
    required Object? toolApproval,
    required ToolCallRepairFunction? repairToolCall,
    required bool? includeRawChunks,
    required GenerateTextOnStartCallback? onStart,
    required GenerateTextOnStepStartCallback? onStepStart,
    required void Function(StepResult step)? onStepEnd,
    required GenerateTextOnEndCallback? onEnd,
    required void Function(Object? error)? onError,
    required TelemetryDispatcher dispatcher,
  }) : _output = output {
    final capturedSteps = <StepResult>[];
    final responseMessages = <ModelMessage>[];

    void emit(TextStreamPart part) {
      _buffer.add(part);
      _wake();
    }

    // 驱动循环:调度为异步任务,保证构造函数先返回、消费者能先挂上。
    scheduleMicrotask(() async {
      emit(const StartPart());
      // 是否因错误终结(provider 流出 ErrorPart,或 try 内抛出被下方 catch 捕获):
      // 用于把聚合结果的 finishReason 置为 error(与 v7 一致),避免失败的生成在
      // `await result.finishReason` 处看起来是 stop/toolCalls。
      var hadError = false;
      try {
        // 调用时刻(streamText())捕获的 prompt 校验错误在此作为流上的终端
        // ErrorPart 抛出——走下方 catch → ErrorPart + onError(error-as-terminal:
        // 不从同步的 streamText() 调用处抛)。promptError==null 时 initialMessages
        // 必非空(转换成功)。
        if (promptError != null) {
          throw promptError;
        }
        onStart?.call(GenerateTextStartEvent(
          model: model,
          messages: startMessages!,
        ));
        if (dispatcher.isActive) {
          await dispatcher.dispatchStart(GenerateTextStartEvent(
            model: model,
            messages: startMessages!,
          ));
        }
        final terminatedByError = await _runToolLoopStream(
          model: model,
          initialMessages: initialMessages!,
          instructions: instructions,
          tools: tools,
          toolChoice: toolChoice,
          maxOutputTokens: maxOutputTokens,
          temperature: temperature,
          topP: topP,
          topK: topK,
          presencePenalty: presencePenalty,
          frequencyPenalty: frequencyPenalty,
          seed: seed,
          stopSequences: stopSequences,
          reasoning: reasoning,
          responseFormat: responseFormat,
          stopWhen: stopWhen,
          cancellation: cancellation,
          headers: headers,
          providerOptions: providerOptions,
          runtimeContext: runtimeContext,
          toolsContext: toolsContext,
          activeTools: activeTools,
          toolOrder: toolOrder,
          prepareStep: prepareStep,
          toolApproval: toolApproval,
          repairToolCall: repairToolCall,
          includeRawChunks: includeRawChunks,
          emit: emit,
          onError: onError,
          onStepStart: onStepStart,
          dispatcher: dispatcher,
          onResumedToolMessage: (message) {
            responseMessages.add(_toModelToolMessage(message));
          },
          onStepEnd: (step, newMessages) {
            capturedSteps.add(step);
            responseMessages.addAll(newMessages);
            onStepEnd?.call(step);
          },
        );
        hadError = terminatedByError;
        // error 已作为终端事件发出时,不再追加 FinishPart(error-as-terminal)。
        if (!terminatedByError) {
          if (capturedSteps.isNotEmpty) {
            onEnd?.call(GenerateTextEndEvent(
              steps: List<StepResult>.unmodifiable(capturedSteps),
            ));
            // telemetry onEnd 在流成功收尾(= 流完成、finishReason 非 error)时派发。
            // **注(与生成路径的差异,已知且有意):** 流式结构化 output 解析是惰性的
            // ——只有 consumer 读 `.output` getter 时才 `parseCompleteOutput`。因此
            // 结构化输出解析失败经 `.output` 抛出、**不进 telemetry onError**。不在此
            // 为 telemetry 提前解析:那会对自定义 [Output] 双重触发解析/副作用、并可能
            // 让一次性解析器在 consumer 读取前就失败(codex 复审)。
            if (dispatcher.isActive) {
              await dispatcher.dispatchEnd(GenerateTextEndEvent(
                steps: List<StepResult>.unmodifiable(capturedSteps),
              ));
            }
          }
          final lastStep = capturedSteps.isEmpty ? null : capturedSteps.last;
          emit(FinishPart(
            finishReason: lastStep?.finishReason ??
                const provider.LanguageModelFinishReason(
                  provider.FinishReasonType.stop,
                ),
            totalUsage: _sumUsage(capturedSteps),
          ));
        }
      } catch (error) {
        hadError = true;
        emit(ErrorPart(error));
        onError?.call(error);
        // site ③ 外层 catch:所有"抛出/重抛"错误在此统一派一次 telemetry error
        // (provider ErrorPart 终端分支是自派、不进此路;内部工具 catch ② 只派
        // stepEnd 后 rethrow 到此)。
        if (dispatcher.isActive) {
          await dispatcher.dispatchError(error);
        }
      } finally {
        var lastFinishReason = const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        );
        var hasInputTotal = false;
        var hasOutputTotal = false;
        var inputTotal = 0;
        var outputTotal = 0;
        for (final step in capturedSteps) {
          lastFinishReason = step.finishReason;
          final input = step.usage.inputTokens.total;
          final output = step.usage.outputTokens.total;
          if (input != null) {
            hasInputTotal = true;
            inputTotal += input;
          }
          if (output != null) {
            hasOutputTotal = true;
            outputTotal += output;
          }
        }
        final aggregate = _StreamTextAggregate(
          // 末步文本(与 generateText.text 一致,对齐 v7 StreamTextResult.text
          // 的 last-step 语义):多步流中早期步在工具调用前的叙述不混入最终
          // 回答;需要全部增量的调用方用 textStream。无步(如 prompt 校验
          // 失败)时为空串。
          text: capturedSteps.isEmpty ? '' : capturedSteps.last.text,
          steps: List.unmodifiable(capturedSteps),
          // 因错误终结时聚合 finishReason 置为 error(而非末步的 stop/toolCalls),
          // 与 v7 一致:失败的生成不应在 result.finishReason 处显示为成功。
          finishReason: hadError
              ? const provider.LanguageModelFinishReason(
                  provider.FinishReasonType.error,
                )
              : lastFinishReason,
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(
              total: hasInputTotal ? inputTotal : null,
            ),
            outputTokens: provider.OutputTokens(
              total: hasOutputTotal ? outputTotal : null,
            ),
          ),
          responseMessages: List.unmodifiable(responseMessages),
        );
        _resultCompleter.complete(aggregate);
        _done = true;
        _wake();
      }
    });
  }

  /// 已产出分块的有序缓冲(供延迟/多个订阅者重放)。
  final List<TextStreamPart> _buffer = [];

  /// 驱动循环是否已结束(不再有新分块追加进 [_buffer])。
  bool _done = false;

  /// 等待「有新分块或已结束」信号的等待者队列。
  final List<Completer<void>> _waiters = [];

  final Completer<_StreamTextAggregate> _resultCompleter = Completer();

  /// 唤醒所有当前等待者(每次追加分块或标记结束后调用)。
  void _wake() {
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  /// 返回一个在下一次 [_wake] 时完成的 Future,供 [stream] 的 `await` 使用。
  Future<void> _nextSignal() {
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// 完整分块流(含步骤框架、文本/工具分块、流首/流尾事件)。
  ///
  /// buffered-replay:每次订阅都从头重放 [_buffer] 中已产出的分块,再跟随
  /// 驱动循环的后续产出,直至结束;可安全地延迟订阅或重复订阅多次。
  Stream<TextStreamPart> get stream async* {
    var i = 0;
    while (true) {
      while (i < _buffer.length) {
        yield _buffer[i];
        i++;
      }
      if (_done) {
        return;
      }
      await _nextSignal();
    }
  }

  /// 仅文本增量的精简视图,派生自 [stream]。
  Stream<String> get textStream => stream
      .where((part) => part is TextDeltaPart)
      .map((part) => (part as TextDeltaPart).delta);

  /// 末步的聚合文本(与 `generateText` 的 `text` 一致:多步工具流只取最终
  /// 回答步);需要全部步骤文本增量的调用方用 [textStream]。
  Future<String> get text => _resultCompleter.future.then((a) => a.text);

  /// 每步 [StepResult] 列表。
  Future<List<StepResult>> get steps =>
      _resultCompleter.future.then((a) => a.steps);

  /// 循环的最后一步。
  Future<StepResult> get finalStep =>
      _resultCompleter.future.then((a) => a.steps.last);

  /// 所有步骤生成的内容项。
  Future<List<provider.LanguageModelContent>> get content =>
      _resultCompleter.future.then(
        (a) => a.steps.expand((step) => step.content).toList(growable: false),
      );

  /// 所有步骤生成的文件内容项。
  Future<List<provider.FileContent>> get files => _resultCompleter.future.then(
        (a) => a.steps.expand((step) => step.files).toList(growable: false),
      );

  /// 所有步骤生成的来源引用内容项。
  Future<List<provider.SourceContent>> get sources =>
      _resultCompleter.future.then(
        (a) => a.steps.expand((step) => step.sources).toList(growable: false),
      );

  /// 所有步骤模型发起的工具调用。
  Future<List<provider.ToolCall>> get toolCalls => _resultCompleter.future.then(
        (a) => a.steps.expand((step) => step.toolCalls).toList(growable: false),
      );

  /// 所有步骤执行出的工具结果。
  Future<List<provider.ToolResult>> get toolResults =>
      _resultCompleter.future.then(
        (a) =>
            a.steps.expand((step) => step.toolResults).toList(growable: false),
      );

  /// 末步结束原因。
  Future<provider.LanguageModelFinishReason> get finishReason =>
      _resultCompleter.future.then((a) => a.finishReason);

  /// 各步累加用量。
  Future<provider.LanguageModelUsage> get usage =>
      _resultCompleter.future.then((a) => a.usage);

  /// 所有步骤的 provider 侧告警。
  Future<List<provider.Warning>> get warnings => _resultCompleter.future.then(
        (a) => a.steps.expand((step) => step.warnings).toList(growable: false),
      );

  /// 解析后的最终输出。
  ///
  /// 仅当最终终止原因是 stop(完整完成)时可用;若模型以工具调用、长度限制、
  /// 内容过滤或错误等非 stop 原因结束,没有完整输出可解析,访问本 getter 会
  /// 抛出契约层错误。错误前或工具调用前的文本仍可通过 [text]、[steps] 或
  /// [stream] 读取,但不会被视为最终 [output]。
  Future<Complete> get output async {
    final aggregate = await _resultCompleter.future;
    final step = aggregate.steps.isEmpty ? null : aggregate.steps.last;
    if (step == null ||
        aggregate.finishReason.unified != provider.FinishReasonType.stop) {
      throw const provider.NoOutputGeneratedError();
    }
    return _output.parseCompleteOutput(
      OutputText(step.text),
      OutputParseContext(
        response: step.response,
        usage: aggregate.usage,
        finishReason: aggregate.finishReason,
      ),
    );
  }

  /// 随文本增量渐进解析出的部分输出。
  Stream<Partial> get partialOutputStream async* {
    Partial? last;
    var hasLast = false;
    var buffer = StringBuffer();

    await for (final part in stream) {
      if (part is StartStepPart) {
        buffer = StringBuffer();
        hasLast = false;
        last = null;
      } else if (part is TextDeltaPart) {
        buffer.write(part.delta);
        final parsedPartial =
            await _output.parsePartialOutput(buffer.toString());
        if (parsedPartial == null) {
          continue;
        }
        final partial = parsedPartial.partial;
        if (hasLast && jsonDeepEquals(partial, last)) {
          continue;
        }
        hasLast = true;
        last = partial;
        yield partial;
      }
    }
  }

  /// 数组输出模式下的逐元素流。
  Stream<Element> get elementStream {
    final arrayStream = _createArrayElementStream();
    if (arrayStream != null) {
      return arrayStream;
    }

    final stream = _output.createElementStream(partialOutputStream);
    if (stream == null) {
      throw provider.UnsupportedFunctionalityError(
        functionality: 'element streams in ${_output.name} mode',
      );
    }
    return stream;
  }

  Stream<Element>? _createArrayElementStream() {
    final output = _output;
    if (output is! ArrayOutput) {
      return null;
    }
    return _arrayElementStream(output as ArrayOutput).cast<Element>();
  }

  Stream<provider.JsonValue> _arrayElementStream(ArrayOutput output) async* {
    var buffer = StringBuffer();
    var publishedElements = 0;

    await for (final part in stream) {
      if (part is StartStepPart) {
        buffer = StringBuffer();
        publishedElements = 0;
      } else if (part is TextDeltaPart) {
        buffer.write(part.delta);
        final parsedPartial = output.parsePartialOutput(
          buffer.toString(),
        );
        if (parsedPartial == null) {
          continue;
        }
        final partial = parsedPartial.partial;
        while (publishedElements < partial.length) {
          yield partial[publishedElements];
          publishedElements++;
        }
      }
    }
  }

  /// 供多轮续接的响应消息(assistant + tool 消息)。
  Future<List<ModelMessage>> get responseMessages =>
      _resultCompleter.future.then((a) => a.responseMessages);

  /// 消费完整流并等待所有聚合 Future 就绪;可安全多次调用。
  Future<void> consumeStream() async {
    await stream.drain<void>();
    await _resultCompleter.future;
  }

  final Output<Complete, Partial, Element> _output;
}

/// 跨全部步骤累加 token 用量,规则同 `GenerateTextResult.usage`:
/// 输入/输出 total 逐步相加(某步为 `null` 时按 0 计);仅当所有步骤该字段
/// 均为 `null` 时,汇总结果该字段才为 `null`。
provider.LanguageModelUsage _sumUsage(List<StepResult> steps) {
  var hasInputTotal = false;
  var hasOutputTotal = false;
  var inputTotal = 0;
  var outputTotal = 0;
  for (final step in steps) {
    final input = step.usage.inputTokens.total;
    final output = step.usage.outputTokens.total;
    if (input != null) {
      hasInputTotal = true;
      inputTotal += input;
    }
    if (output != null) {
      hasOutputTotal = true;
      outputTotal += output;
    }
  }
  return provider.LanguageModelUsage(
    inputTokens: provider.InputTokens(total: hasInputTotal ? inputTotal : null),
    outputTokens:
        provider.OutputTokens(total: hasOutputTotal ? outputTotal : null),
  );
}

/// 流式多步工具循环:驱动 [provider.LanguageModel.doStream] 逐步生成,
/// 把每个 provider 分块实时转发为 [TextStreamPart] 事件,并在每步之间
/// 执行工具调用。续/停判定与 `generate_text/tool_loop.dart` 的 `runToolLoopGenerate`
/// 完全一致,唯一差异是驱动 `doStream` 而非 `doGenerate`。
///
/// [onStepEnd] 在每步收尾时收到该步 [StepResult] 与本步新增的、供下一轮
/// 续接的 [ModelMessage] 列表(assistant 文本/工具调用 + 工具结果)。
/// 返回是否**因 [ErrorPart] 终结**(true 时调用方不得再追加 [FinishPart],
/// 遵循 error-as-terminal 语义);正常收尾返回 false。
Future<bool> _runToolLoopStream({
  required provider.LanguageModel model,
  required List<provider.LanguageModelMessage> initialMessages,
  required String? instructions,
  required ToolSet? tools,
  required provider.ToolChoice? toolChoice,
  required int? maxOutputTokens,
  required double? temperature,
  required double? topP,
  required double? topK,
  required double? presencePenalty,
  required double? frequencyPenalty,
  required int? seed,
  required List<String>? stopSequences,
  required provider.ReasoningEffort? reasoning,
  required provider.ResponseFormat? responseFormat,
  required Object? stopWhen,
  required provider.CancellationSignal? cancellation,
  required Map<String, String>? headers,
  required provider.ProviderOptions? providerOptions,
  required RuntimeContext runtimeContext,
  required ToolsContext toolsContext,
  required ActiveTools? activeTools,
  required ToolOrder? toolOrder,
  required PrepareStepFunction? prepareStep,
  required Object? toolApproval,
  required ToolCallRepairFunction? repairToolCall,
  required bool? includeRawChunks,
  required void Function(TextStreamPart part) emit,
  required void Function(Object? error)? onError,
  required GenerateTextOnStepStartCallback? onStepStart,
  required TelemetryDispatcher dispatcher,
  required void Function(provider.ToolMessage message)? onResumedToolMessage,
  required void Function(
    StepResult step,
    List<ModelMessage> newMessages,
  ) onStepEnd,
}) async {
  final stopConditions = _normalizeStopWhen(stopWhen);
  // tools 已由 streamText() 在调用时刻拍为不可变快照后传入(见 streamText),
  // 此处直接使用(循环内只读不写):advertisedTools(广告)与 await doStream 之后
  // 的按名查表执行同源,caller 在返回后或模型运行期间改动原 map 都不影响。
  final toolSet = tools;
  var currentRuntimeContext = snapshotRuntimeContext(runtimeContext);
  var currentToolsContext = snapshotToolsContext(toolsContext);
  final initialMessagesSnapshot =
      List<provider.LanguageModelMessage>.unmodifiable(initialMessages);
  final initialModelMessagesSnapshot =
      convertFromLanguageModelPrompt(initialMessagesSnapshot);
  var messagesForNextStep =
      List<provider.LanguageModelMessage>.of(initialMessagesSnapshot);
  final responseMessages = <provider.LanguageModelMessage>[];
  final resumedToolMessage = await _executeResumedToolApprovals(
    messages: initialMessagesSnapshot,
    tools: toolSet,
    toolsContext: currentToolsContext,
    toolApproval: toolApproval,
    repairToolCall: repairToolCall,
    instructions: instructions,
    cancellation: cancellation,
    dispatcher: dispatcher,
  );
  if (resumedToolMessage != null) {
    messagesForNextStep.add(resumedToolMessage);
    responseMessages.add(resumedToolMessage);
    for (final part in resumedToolMessage.content) {
      if (part is provider.ToolResultPart) {
        emit(ToolResultStreamPart(provider.ToolResult(
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          result: _toolResultOutputValue(part.output),
          isError: _isErrorOutput(part.output) ? true : null,
        )));
      }
    }
    onResumedToolMessage?.call(resumedToolMessage);
  }
  final steps = <StepResult>[];
  final generateApprovalId = createIdGenerator(prefix: 'approval');
  final generateModelCallId = createIdGenerator(prefix: 'lmcall');
  // provider 工具自动续接的 pending 表(toolCallId → toolName):跨步存续、
  // 单次调用级(:1094-1097)。providerExecuted 且标记 supportsDeferredResults
  // 的调用在同响应无配对结果时记入,结果跨轮到达时解销。
  final pendingDeferredToolCalls = <String, String>{};

  while (true) {
    final stepInputMessages =
        List<provider.LanguageModelMessage>.unmodifiable(messagesForNextStep);
    final prepareStepResult = await prepareStep?.call(PrepareStepOptions(
      steps: steps,
      stepNumber: steps.length,
      model: model,
      messages: convertFromLanguageModelPrompt(stepInputMessages),
      initialMessages: initialModelMessagesSnapshot,
      responseMessages: convertFromLanguageModelPrompt(responseMessages),
      runtimeContext: currentRuntimeContext,
      toolsContext: currentToolsContext,
    ));
    if (prepareStepResult?.runtimeContext != null) {
      currentRuntimeContext =
          snapshotRuntimeContext(prepareStepResult!.runtimeContext);
    }
    if (prepareStepResult?.toolsContext != null) {
      currentToolsContext =
          snapshotToolsContext(prepareStepResult!.toolsContext);
    }
    final stepModel = prepareStepResult?.model ?? model;
    final stepMessages = prepareStepResult?.messages == null
        ? stepInputMessages
        : List<provider.LanguageModelMessage>.unmodifiable(
            convertModelMessagesToLanguageModelPrompt(
              prepareStepResult!.messages!,
            ),
          );
    final stepTools = filterActiveTools(
      toolSet,
      prepareStepResult?.activeTools ?? activeTools,
    );
    final stepToolChoice = filterToolChoiceForTools(
      prepareStepResult?.toolChoice ?? toolChoice,
      stepTools,
    );
    final stepToolOrder = prepareStepResult?.toolOrder ?? toolOrder;
    // 广告给模型的工具列表每步冻结(理由同 tool_loop.dart);activeTools/
    // prepareStep 可以改变每步工具集合,但 callOptions.tools 仍是值快照。
    final advertisedTools = stepTools == null || stepTools.isEmpty
        ? const <provider.LanguageModelTool>[]
        : List<provider.LanguageModelTool>.unmodifiable(
            buildOrderedLanguageModelTools(
              stepTools,
              stepToolOrder,
              toolSet,
            ),
          );
    final stepProviderOptions = mergeProviderOptions(
      providerOptions,
      prepareStepResult?.providerOptions,
    );
    final callOptions = provider.LanguageModelCallOptions(
      // 每步传入 messages 的不可变快照(理由同 tool_loop.dart)。
      prompt: stepMessages,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      presencePenalty: presencePenalty,
      frequencyPenalty: frequencyPenalty,
      seed: seed,
      stopSequences: stopSequences,
      responseFormat: responseFormat,
      tools: advertisedTools.isEmpty ? null : advertisedTools,
      toolChoice: stepToolChoice,
      reasoning: reasoning,
      includeRawChunks: includeRawChunks,
      cancellation: cancellation,
      headers: headers,
      providerOptions: stepProviderOptions,
    );

    onStepStart?.call(GenerateTextStepStartEvent(
      stepNumber: steps.length,
      model: stepModel,
      messages: convertFromLanguageModelPrompt(stepMessages),
      steps: steps,
    ));
    // 本步模型调用的 telemetry callId(start/end 配对);无生效集成时不会用到。
    final telemetryCallId = generateModelCallId();
    if (dispatcher.isActive) {
      final stepModelMessages = convertFromLanguageModelPrompt(stepMessages);
      await dispatcher.dispatchStepStart(GenerateTextStepStartEvent(
        stepNumber: steps.length,
        model: stepModel,
        messages: stepModelMessages,
        steps: steps,
      ));
      await dispatcher
          .dispatchLanguageModelCallStart(LanguageModelCallStartEvent(
        callId: telemetryCallId,
        providerId: stepModel.provider,
        modelId: stepModel.modelId,
        stepNumber: steps.length,
        messages: stepModelMessages,
      ));
    }
    final stepStopwatch = Stopwatch()..start();
    Duration? timeToFirstOutput;
    Duration? previousOutputChunkTime;
    final outputChunkTimes = <Duration>[];
    final toolExecutionTimes = <String, Duration>{};

    void recordOutputChunk() {
      final now = stepStopwatch.elapsed;
      if (timeToFirstOutput == null) {
        timeToFirstOutput = now;
      } else if (previousOutputChunkTime != null) {
        outputChunkTimes.add(now - previousOutputChunkTime!);
      }
      previousOutputChunkTime = now;
    }

    final provider.LanguageModelStreamResult streamResult;
    try {
      streamResult = await stepModel.doStream(callOptions);
    } catch (error) {
      // doStream 本身抛错(请求建立/传输失败,尚未返回流)时,补派 lmEnd
      // (finishReason=error)使 lmStart 恒配对;随后 rethrow 交外层 catch 派 onError。
      if (dispatcher.isActive) {
        await dispatcher.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
          callId: telemetryCallId,
          providerId: stepModel.provider,
          modelId: stepModel.modelId,
          stepNumber: steps.length,
          content: const [],
          usage: const provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
          finishReason: const provider.LanguageModelFinishReason(
            provider.FinishReasonType.error,
          ),
          warnings: const [],
          response: null,
          responseTime: stepStopwatch.elapsed,
        ));
      }
      rethrow;
    }
    final content = <provider.LanguageModelContent>[];
    final parsedToolCallsById = <String, ParsedToolCall>{};
    final deferredToolCallFailuresById = <String, ToolCallRepairFailure>{};
    // 文本块缓冲:按 id 累积 TextDelta,并跟踪 providerMetadata(v7 语义:
    // Start 事件的 metadata 打底,后续 Delta/End 事件给出非空值时覆盖——
    // 最新非空值胜出),TextEnd 时落成 TextContent 进 content。
    final textBuffers = <String, _StreamContentBuffer>{};
    // 推理块缓冲,与 textBuffers 同构:按 id 累积 ReasoningDelta 与
    // providerMetadata,ReasoningEnd 时落成 ReasoningContent 进 content
    // (与非流式 result.content 一致)。
    final reasoningBuffers = <String, _StreamContentBuffer>{};
    // 本步 provider 告警(来自 StreamStart 分块),建步时记入
    // StepResult.warnings,与非流式 doGenerate 结果的 warnings 对称。
    var stepWarnings = const <provider.Warning>[];
    provider.LanguageModelFinishReason? finishReason;
    // FinishPart 携带的结果级 provider 元数据:解构点存入,建步时进
    // StepResult.providerMetadata(error 步取当时已累积值,通常为 null)。
    provider.ProviderMetadata? stepProviderMetadata;
    var usage = const provider.LanguageModelUsage(
      inputTokens: provider.InputTokens(),
      outputTokens: provider.OutputTokens(),
    );
    // 流分块携带的响应元数据(id/timestamp/modelId),与 `streamResult.response`
    // 分开累积,循环结束后再合并——避免其中任一为非空就短路另一侧信息。
    String? metadataId;
    DateTime? metadataTimestamp;
    String? metadataModelId;
    var hasResponseMetadata = false;
    var startStepEmitted = false;

    // 合并响应元数据的两个来源(见循环后原用法):headers/body 来自
    // streamResult.response;id/timestamp/modelId 若流分块给出 ResponseMetadata
    // 则以其为准(覆盖同名字段),否则回落到 streamResult.response。定义为局部
    // 函数,使循环中途(ErrorPart 报错时)与循环正常结束时都能按当时已累积的
    // 元数据构建同一份 response。
    provider.ResponseInfo? buildResponse() => hasResponseMetadata
        ? provider.ResponseInfo(
            id: metadataId ?? streamResult.response?.id,
            timestamp: metadataTimestamp ?? streamResult.response?.timestamp,
            modelId: metadataModelId ?? streamResult.response?.modelId,
            headers: streamResult.response?.headers,
            body: streamResult.response?.body,
          )
        : streamResult.response;

    try {
      await for (final part in streamResult.stream) {
        if (!startStepEmitted && part is! provider.StreamStart) {
          // 兜底:约定上 `StreamStart` 通常是首个分块,但类型系统未强制;
          // 若 provider 未发出 `StreamStart` 就产出了其他分块,仍需先补上
          // 步骤开始框架分块,保持 `StartStepPart` 先于步内其余分块的顺序。
          emit(StartStepPart(request: streamResult.request, warnings: []));
          startStepEmitted = true;
        }
        switch (part) {
          case provider.StreamStart(:final warnings):
            // 无论早晚,warnings 都记入本步 StepResult(聚合不丢诊断信息)。
            stepWarnings = warnings;
            logWarnings(
              warnings: warnings,
              provider: stepModel.provider,
              model: stepModel.modelId,
            );
            // 兜底可能已先行发过 StartStepPart(provider 未按约定先发 StreamStart
            // 就产出了其他分块);若此处再发一次会造成重复的步骤开始框架分块
            // (StartStepPart, 内容..., StartStepPart)。仅在尚未发出时才发;这种
            // 极端乱序下迟到 StreamStart 的 warnings 不再随框架分块发出(步骤已
            // 开始),但仍经上面的 stepWarnings 保留进聚合。
            if (!startStepEmitted) {
              emit(StartStepPart(
                request: streamResult.request,
                warnings: warnings,
              ));
              startStepEmitted = true;
            }
          case provider.TextStart(:final id, :final providerMetadata):
            textBuffers[id] = _StreamContentBuffer(providerMetadata);
            emit(TextStartPart(id, providerMetadata: providerMetadata));
          case provider.TextDelta(
              :final id,
              :final delta,
              :final providerMetadata
            ):
            if (delta.isNotEmpty) {
              recordOutputChunk();
            }
            final buffer = textBuffers[id]!;
            buffer.write(delta);
            buffer.mergeMetadata(providerMetadata);
            emit(TextDeltaPart(
              id,
              delta,
              providerMetadata: providerMetadata,
            ));
          case provider.TextEnd(:final id, :final providerMetadata):
            // 闭合并从 textBuffers 移除:使 textBuffers 仅保留「未闭合」的文本块,
            // 便于中途报错(ErrorPart)时冲刷尚未闭合的部分文本,且不会重复计入
            // 已闭合的块。TextEnd 的 providerMetadata 非空时覆盖之前累积的值
            // (v7 语义:最新非空值胜出),再落成 TextContent。
            final buffer = textBuffers.remove(id)!
              ..mergeMetadata(providerMetadata);
            content.add(provider.TextContent(
              buffer.toString(),
              providerMetadata: buffer.providerMetadata,
            ));
            emit(TextEndPart(id, providerMetadata: providerMetadata));
          case provider.ReasoningStart(:final id, :final providerMetadata):
            // 推理块与文本块同构缓冲。公开流转发 reasoning 事件,同时累积
            // content 供 steps/responseMessages/下一步 prompt 使用。
            reasoningBuffers[id] = _StreamContentBuffer(providerMetadata);
            emit(ReasoningStartPart(id, providerMetadata: providerMetadata));
          case provider.ReasoningDelta(
              :final id,
              :final delta,
              :final providerMetadata
            ):
            if (delta.isNotEmpty) {
              recordOutputChunk();
            }
            final buffer = reasoningBuffers[id]!;
            buffer.write(delta);
            buffer.mergeMetadata(providerMetadata);
            emit(ReasoningDeltaPart(
              id,
              delta,
              providerMetadata: providerMetadata,
            ));
          case provider.ReasoningEnd(:final id, :final providerMetadata):
            // ReasoningEnd 的 providerMetadata 非空时覆盖之前累积的值(同
            // TextEnd 语义;OpenAI Responses 侧 encrypted_content 就落在 End)。
            final buffer = reasoningBuffers.remove(id)!
              ..mergeMetadata(providerMetadata);
            content.add(provider.ReasoningContent(
              buffer.toString(),
              providerMetadata: buffer.providerMetadata,
            ));
            emit(ReasoningEndPart(id, providerMetadata: providerMetadata));
          case provider.ToolCall():
            recordOutputChunk();
            var toolCall = part;
            if (repairToolCall != null && part.providerExecuted != true) {
              final originalTool = stepTools?[part.toolName];
              if (originalTool == null ||
                  (originalTool.execute != null &&
                      !toolApprovalMayBlockBeforeInput(
                        toolApproval: toolApproval,
                        toolCall: part,
                      ))) {
                var repairReturnedNull = false;
                var repairReturnedNonNull = false;
                try {
                  final parsedCall = await parseOrRepairToolCall(
                    toolCall: part,
                    tools: stepTools,
                    repairToolCall: (options) async {
                      final repaired = await repairToolCall(options);
                      if (repaired == null) {
                        repairReturnedNull = true;
                      } else {
                        repairReturnedNonNull = true;
                      }
                      return repaired;
                    },
                    instructions: instructions,
                    messages: stepMessages,
                  );
                  toolCall = parsedCall.toolCall;
                  parsedToolCallsById[toolCall.toolCallId] = parsedCall;
                } on NoSuchToolError catch (error) {
                  if (repairReturnedNonNull) {
                    deferredToolCallFailuresById[part.toolCallId] = error;
                  } else if (!repairReturnedNull) {
                    rethrow;
                  }
                  // repair 返回 null 时保留未知工具原 blocking 语义。
                } on ToolCallRepairFailure catch (error) {
                  deferredToolCallFailuresById[part.toolCallId] = error;
                }
              }
            }
            content.add(toolCall);
            emit(ToolCallStreamPart(toolCall));
          case provider.ToolResult(:final toolCallId):
            // 去重保留最新:同一 toolCallId 可能先收到一个 preliminary(可替换)
            // 结果、后收到最终结果——累积的 content(继而 StepResult/
            // responseMessages)只应保留最新一条,避免下一步模型提示里出现
            // 同一 toolCallId 的重复结果。每条 ToolResult 仍会实时转发为
            // ToolResultStreamPart 事件,不受这里的去重影响。
            final existingIndex = content.indexWhere(
              (item) =>
                  item is provider.ToolResult && item.toolCallId == toolCallId,
            );
            if (existingIndex == -1) {
              content.add(part);
            } else {
              content[existingIndex] = part;
            }
            emit(ToolResultStreamPart(part));
          case provider.ToolInputStart(:final id, :final toolName):
            emit(ToolInputStartPart(id, toolName));
          case provider.ToolInputDelta(:final id, :final delta):
            if (delta.isNotEmpty) {
              recordOutputChunk();
            }
            emit(ToolInputDeltaPart(id, delta));
          case provider.ToolInputEnd(:final id):
            emit(ToolInputEndPart(id));
          case provider.ResponseMetadata(
              id: final id,
              timestamp: final timestamp,
              modelId: final modelId
            ):
            // 仅记录流式分块携带的响应元数据(id/timestamp/modelId),逐字段
            // 覆盖(分块提供的非空字段优先于已有值);headers/body 只可能来自
            // `streamResult.response`,留到循环结束后再合并,避免二者互相
            // 覆盖丢失信息。
            hasResponseMetadata = true;
            metadataId = id ?? metadataId;
            metadataTimestamp = timestamp ?? metadataTimestamp;
            metadataModelId = modelId ?? metadataModelId;
          case provider.FinishPart(
              usage: final partUsage,
              finishReason: final partFinishReason,
              providerMetadata: final partProviderMetadata
            ):
            usage = partUsage;
            finishReason = partFinishReason;
            stepProviderMetadata = partProviderMetadata;
          case provider.ErrorPart(:final error):
            // provider 在本步中途报错:先把已累积的部分内容(如已完成的文本块)
            // 固化为一步「error」StepResult 并捕获,避免 result.text/steps 丢失
            // 错误前的产出(与 v7 一致:error 步带部分内容、finishReason=error 记入
            // steps)。本步已报错,不执行工具、也不发 FinishStepPart;随后发出终端
            // ErrorPart 结束(error-as-terminal:其后不再追加 FinishPart)。
            //
            // 冲刷尚未闭合的文本块:provider 可能发了 TextStart/TextDelta 却在
            // TextEnd 之前就报错,此时部分文本还在 textBuffers 里、未进 content。
            // 按插入顺序补成 TextContent,避免这类「未闭合就报错」丢失已投递文本。
            for (final buffer in textBuffers.values) {
              content.add(provider.TextContent(
                buffer.toString(),
                providerMetadata: buffer.providerMetadata,
              ));
            }
            // 未闭合的推理块同样冲刷(理由同上,与文本块对称)。
            for (final buffer in reasoningBuffers.values) {
              content.add(provider.ReasoningContent(
                buffer.toString(),
                providerMetadata: buffer.providerMetadata,
              ));
            }
            final errorTime = stepStopwatch.elapsed;
            final erroredStep = StepResult(
              content: content,
              finishReason: const provider.LanguageModelFinishReason(
                provider.FinishReasonType.error,
              ),
              usage: usage,
              response: buildResponse(),
              providerMetadata: stepProviderMetadata,
              executedToolResults: const [],
              warnings: stepWarnings,
              runtimeContext: currentRuntimeContext,
              toolsContext: currentToolsContext,
              performance: buildStepPerformance(
                usage: usage,
                responseTime: errorTime,
                stepTime: errorTime,
                timeToFirstOutput: timeToFirstOutput,
                timeBetweenOutputChunks: calculateOutputChunkTimingStats(
                  outputChunkTimes,
                ),
              ),
            );
            steps.add(erroredStep);
            onStepEnd(
              erroredStep,
              _stepResponseMessages(erroredStep).toList(growable: false),
            );
            onError?.call(error);
            // site ①(provider ErrorPart,终端 return true,不进外层 catch):
            // 补派 modelCallEnd(finishReason=error,已冲刷 content + 当前 usage +
            // buildResponse())使 callStart 恒配对,再 stepEnd,再自派一次 error。
            if (dispatcher.isActive) {
              await dispatcher
                  .dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
                callId: telemetryCallId,
                providerId: stepModel.provider,
                modelId: stepModel.modelId,
                stepNumber: steps.length - 1,
                content: content,
                usage: usage,
                finishReason: const provider.LanguageModelFinishReason(
                  provider.FinishReasonType.error,
                ),
                warnings: stepWarnings,
                response: buildResponse(),
                responseTime: errorTime,
              ));
              await dispatcher.dispatchStepEnd(erroredStep);
              await dispatcher.dispatchError(error);
            }
            emit(ErrorPart(error));
            return true;
          case provider.RawPart(:final rawValue):
            // 仅在 provider 侧开启 includeRawChunks 时出现;原样转发,保持
            // 分块到达的先后顺序。
            emit(RawStreamPart(rawValue));
          case final provider.ToolApprovalRequest request:
            content.add(request);
            emit(ToolApprovalRequestStreamPart(request));
          case final provider.LanguageModelContent contentPart:
            recordOutputChunk();
            // 其余「内容型」流分块(SourceContent/FileContent/ReasoningFileContent/
            // CustomContentBlock —— 均同时实现 LanguageModelContent 与
            // LanguageModelStreamPart)累积进 content,与
            // 非流式路径(doGenerate 的 result.content)一致,避免 steps/
            // responseMessages 静默丢失引用/文件等。ToolCall/ToolResult/
            // ToolApprovalRequest 已在上方专门处理,不会落到此分支。
            content.add(contentPart);
        }
      }
    } catch (error) {
      // C4:模型流在产出 provider ErrorPart 之外「直接抛异常」终止时(如传输层
      // 断连),补派 lmEnd 使每个 lmStart 恒配对一个 lmEnd(finishReason 保留已见
      // 值,否则 error);随后 rethrow 交外层 catch(site ③)统一派 onError,不给
      // callId 留孤儿 in-flight。ErrorPart 分支走 `return true`(不经此 catch)。
      if (dispatcher.isActive) {
        // 与 ErrorPart 分支一致:冲刷未闭合的文本/推理缓冲(TextStart/Delta 后
        // 断连时,部分文本已投递到公开流但尚未落入 content),使 telemetry lmEnd
        // 不丢错误前的部分输出(partial 保真)。写入局部列表,不改 content 本身。
        final flushedContent = <provider.LanguageModelContent>[
          ...content,
          for (final buffer in textBuffers.values)
            provider.TextContent(
              buffer.toString(),
              providerMetadata: buffer.providerMetadata,
            ),
          for (final buffer in reasoningBuffers.values)
            provider.ReasoningContent(
              buffer.toString(),
              providerMetadata: buffer.providerMetadata,
            ),
        ];
        await dispatcher.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
          callId: telemetryCallId,
          providerId: stepModel.provider,
          modelId: stepModel.modelId,
          stepNumber: steps.length,
          content: flushedContent,
          usage: usage,
          finishReason: finishReason ??
              const provider.LanguageModelFinishReason(
                provider.FinishReasonType.error,
              ),
          warnings: stepWarnings,
          response: buildResponse(),
          responseTime: stepStopwatch.elapsed,
        ));
      }
      rethrow;
    }

    final responseTime = stepStopwatch.elapsed;

    // 合并两个来源:headers/body 只能来自 `streamResult.response`(doStream
    // 返回值携带);id/timestamp/modelId 若流分块给出了 `ResponseMetadata`,
    // 以其为准(覆盖 `streamResult.response` 的同名字段),否则回落到
    // `streamResult.response` 的对应字段。任一来源为 `null` 都不应导致另一侧
    // 信息被丢弃。
    final response = buildResponse();

    final resolvedFinishReason = finishReason ??
        const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        );

    // C4:模型侧流已读完(拿到 usage/finishReason/content/response),工具执行之前
    // 派 modelCallEnd。使工具执行错误(rethrow)路径上该 callEnd 已先配对好;
    // 每个 callStart 恒配对一个 callEnd(此处正常路径,error 路径见 ErrorPart 分支)。
    if (dispatcher.isActive) {
      await dispatcher.dispatchLanguageModelCallEnd(LanguageModelCallEndEvent(
        callId: telemetryCallId,
        providerId: stepModel.provider,
        modelId: stepModel.modelId,
        stepNumber: steps.length,
        content: content,
        usage: usage,
        finishReason: resolvedFinishReason,
        warnings: stepWarnings,
        response: response,
        responseTime: responseTime,
      ));
    }

    final executableCalls = <ParsedToolCall>[];
    final blockingCalls = <provider.ToolCall>[];
    final toolResults = <provider.ToolResult>[];
    final toolResultOutputs = <provider.ToolResultOutput>[];
    final toolApprovalResponses = <provider.ToolApprovalResponsePart>[];
    final providerApprovalRequestsByToolCallId =
        <String, provider.ToolApprovalRequest>{
      for (final item in content)
        if (item is provider.ToolApprovalRequest) item.toolCallId: item,
    };
    try {
      for (final item in List<provider.LanguageModelContent>.of(content)) {
        if (item is provider.ToolCall) {
          final deferredFailure = deferredToolCallFailuresById[item.toolCallId];
          if (deferredFailure != null) {
            throw deferredFailure;
          }

          final providerApprovalRequest =
              providerApprovalRequestsByToolCallId[item.toolCallId];
          // provider 已侧执行(`providerExecuted == true`)的调用会由 provider 自带
          // 结果,本地循环不得再跑同名 `execute`(否则副作用工具被重复执行、
          // 且会产出一条重复的本地结果)。
          if (item.providerExecuted == true) {
            if (providerApprovalRequest != null) {
              final approval = await resolveToolApproval(
                toolApproval: toolApproval,
                toolCall: item,
                messages: stepMessages,
                tools: stepTools,
              );
              switch (approval.type) {
                case ToolApprovalStatusType.approved:
                  final response = provider.ToolApprovalResponsePart(
                    approvalId: providerApprovalRequest.approvalId,
                    approved: true,
                    reason: approval.reason,
                    providerOptions: providerApprovalRequest.providerMetadata,
                  );
                  toolApprovalResponses.add(response);
                  emit(ToolApprovalResponseStreamPart(response));
                case ToolApprovalStatusType.denied:
                  final response = provider.ToolApprovalResponsePart(
                    approvalId: providerApprovalRequest.approvalId,
                    approved: false,
                    reason: approval.reason,
                    providerOptions: providerApprovalRequest.providerMetadata,
                  );
                  toolApprovalResponses.add(response);
                  emit(ToolApprovalResponseStreamPart(response));
                case ToolApprovalStatusType.notApplicable:
                case ToolApprovalStatusType.userApproval:
                  blockingCalls.add(item);
              }
            }
            continue;
          }
          final tool = stepTools?[item.toolName];
          if (tool == null || tool.execute == null) {
            blockingCalls.add(item);
            continue;
          }

          Future<ParsedToolCall> parseForExecution({
            required bool allowIdentityChange,
          }) async {
            final deferredFailure =
                deferredToolCallFailuresById[item.toolCallId];
            if (deferredFailure != null) {
              throw deferredFailure;
            }
            final existing = parsedToolCallsById[item.toolCallId];
            if (existing != null) {
              return existing;
            }
            if (repairToolCall != null) {
              final parsedCall = await parseOrRepairToolCall(
                toolCall: item,
                tools: stepTools,
                repairToolCall: repairToolCall,
                instructions: instructions,
                messages: stepMessages,
              );
              final repairedToolCall = parsedCall.toolCall;
              if (!allowIdentityChange &&
                  (repairedToolCall.toolName != item.toolName ||
                      repairedToolCall.toolCallId != item.toolCallId)) {
                throw StateError(
                  'repairToolCall cannot change toolName or toolCallId after '
                  'tool approval has been resolved.',
                );
              }
              final contentIndex = content.indexWhere(
                (contentItem) => contentItem == item,
              );
              if (contentIndex != -1) {
                content[contentIndex] = repairedToolCall;
              }
              parsedToolCallsById[item.toolCallId] = parsedCall;
              return parsedCall;
            }
            final parsedCall = parseToolCall(toolCall: item, tools: stepTools);
            final parsedToolCall = parsedCall.toolCall;
            if (parsedToolCall != item) {
              final contentIndex = content.indexWhere(
                (contentItem) => contentItem == item,
              );
              if (contentIndex != -1) {
                content[contentIndex] = parsedToolCall;
              }
            }
            parsedToolCallsById[item.toolCallId] = parsedCall;
            return parsedCall;
          }

          if (toolApprovalRequiresInput(
            toolApproval: toolApproval,
            toolCall: item,
          )) {
            final parsedCall =
                await parseForExecution(allowIdentityChange: true);
            final repairedTool = stepTools?[parsedCall.toolCall.toolName];
            if (repairedTool == null || repairedTool.execute == null) {
              blockingCalls.add(parsedCall.toolCall);
              continue;
            }
          }

          final approvalToolCall =
              parsedToolCallsById[item.toolCallId]?.toolCall ?? item;
          final approval = await resolveToolApproval(
            toolApproval: toolApproval,
            toolCall: approvalToolCall,
            messages: stepMessages,
            tools: stepTools,
          );

          switch (approval.type) {
            case ToolApprovalStatusType.notApplicable:
              if (providerApprovalRequestsByToolCallId
                  .containsKey(approvalToolCall.toolCallId)) {
                blockingCalls.add(approvalToolCall);
              } else {
                executableCalls.add(
                  await parseForExecution(allowIdentityChange: false),
                );
              }
            case ToolApprovalStatusType.approved:
              final request = providerApprovalRequestsByToolCallId[
                      approvalToolCall.toolCallId] ??
                  provider.ToolApprovalRequest(
                    approvalId: generateApprovalId(),
                    toolCallId: approvalToolCall.toolCallId,
                  );
              final response = provider.ToolApprovalResponsePart(
                approvalId: request.approvalId,
                approved: true,
                reason: approval.reason,
                providerOptions: request.providerMetadata,
              );
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(approvalToolCall.toolCallId)) {
                content.add(request);
                emit(ToolApprovalRequestStreamPart(request));
              }
              toolApprovalResponses.add(response);
              emit(ToolApprovalResponseStreamPart(response));
              executableCalls.add(
                await parseForExecution(allowIdentityChange: false),
              );
            case ToolApprovalStatusType.denied:
              final request = providerApprovalRequestsByToolCallId[
                      approvalToolCall.toolCallId] ??
                  provider.ToolApprovalRequest(
                    approvalId: generateApprovalId(),
                    toolCallId: approvalToolCall.toolCallId,
                  );
              final response = provider.ToolApprovalResponsePart(
                approvalId: request.approvalId,
                approved: false,
                reason: approval.reason,
                providerOptions: request.providerMetadata,
              );
              final resultOutput = provider.ToolResultExecutionDenied(
                reason: approval.reason,
              );
              final toolResult = provider.ToolResult(
                toolCallId: approvalToolCall.toolCallId,
                toolName: approvalToolCall.toolName,
                result: _toolResultOutputValue(resultOutput),
              );
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(approvalToolCall.toolCallId)) {
                content.add(request);
                emit(ToolApprovalRequestStreamPart(request));
              }
              toolApprovalResponses.add(response);
              toolResultOutputs.add(resultOutput);
              toolResults.add(toolResult);
              emit(ToolApprovalResponseStreamPart(response));
              emit(ToolResultStreamPart(toolResult));
            case ToolApprovalStatusType.userApproval:
              final request = providerApprovalRequestsByToolCallId[
                      approvalToolCall.toolCallId] ??
                  provider.ToolApprovalRequest(
                    approvalId: generateApprovalId(),
                    toolCallId: approvalToolCall.toolCallId,
                  );
              if (!providerApprovalRequestsByToolCallId
                  .containsKey(approvalToolCall.toolCallId)) {
                content.add(request);
                emit(ToolApprovalRequestStreamPart(request));
              }
              blockingCalls.add(approvalToolCall);
          }
        }
      }

      for (final parsedCall in executableCalls) {
        final call = parsedCall.toolCall;
        final tool = stepTools![call.toolName]!;
        final input = parsedCall.input;
        // 在 telemetry start 之前完成 context 校验,保证 start/end 恒配对:
        // 校验失败则不派 start(工具从未执行),错误照旧向上传播。
        final toolContext = _validateToolContext(
          toolName: call.toolName,
          tool: tool,
          toolsContext: currentToolsContext,
        );
        if (dispatcher.isActive) {
          await dispatcher.dispatchToolExecutionStart(ToolExecutionStartEvent(
            callId: call.toolCallId,
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            input: input,
            toolContext: toolContext,
          ));
        }
        final toolStopwatch = Stopwatch()..start();
        final Object? output;
        try {
          output = await tool.execute!(
            input,
            ToolExecuteOptions(
              toolCallId: call.toolCallId,
              // 过滤 system 的不可变副本(理由同 tool_loop.dart)。
              messages: List<provider.LanguageModelMessage>.unmodifiable(
                stepMessages.where((m) => m is! provider.SystemMessage),
              ),
              context: toolContext,
              cancellation: cancellation,
            ),
          );
        } catch (error) {
          // per-tool error 变体(与 step 级 onError 不同粒度,不重复);记时后 rethrow
          // 交内部工具 catch(site ②)→ 外层 catch(site ③)派 step 级 onError。
          toolExecutionTimes[call.toolCallId] = toolStopwatch.elapsed;
          if (dispatcher.isActive) {
            await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndError(
              callId: call.toolCallId,
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              error: error,
              toolExecutionMs: toolStopwatch.elapsed.inMilliseconds,
            ));
          }
          rethrow;
        }
        toolExecutionTimes[call.toolCallId] = toolStopwatch.elapsed;
        if (dispatcher.isActive) {
          await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndSuccess(
            callId: call.toolCallId,
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            output: output,
            toolExecutionMs: toolStopwatch.elapsed.inMilliseconds,
          ));
        }
        final resultOutput = tool.toModelOutput != null
            ? tool.toModelOutput!(input, output)
            : _defaultToModelOutput(output);
        final toolResult = provider.ToolResult(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          result: _toolResultOutputValue(resultOutput),
          isError: _isErrorOutput(resultOutput) ? true : null,
        );
        toolResults.add(toolResult);
        toolResultOutputs.add(resultOutput);
        emit(ToolResultStreamPart(toolResult));
      }
    } catch (error) {
      // 工具执行(或入参解析 / toModelOutput)抛错:provider 回合本身
      // 已完整、其内容已投递到公开流——先把它(含已成功的工具结果)固化为
      // 一步 error StepResult 并经 onStepEnd 捕获,使 result.steps/text/
      // responseMessages 与 provider ErrorPart 路径一致地保留错误前进度;
      // 再重抛交外层 catch 发终端 ErrorPart(error-as-terminal)。
      final erroredStep = StepResult(
        content: content,
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.error,
        ),
        usage: usage,
        response: response,
        providerMetadata: stepProviderMetadata,
        executedToolResults: toolResults,
        toolResultOutputs: toolResultOutputs,
        toolApprovalResponses: toolApprovalResponses,
        warnings: stepWarnings,
        runtimeContext: currentRuntimeContext,
        toolsContext: currentToolsContext,
        performance: buildStepPerformance(
          usage: usage,
          responseTime: responseTime,
          stepTime: stepStopwatch.elapsed,
          toolExecutionTimes: toolExecutionTimes,
          timeToFirstOutput: timeToFirstOutput,
          timeBetweenOutputChunks: calculateOutputChunkTimingStats(
            outputChunkTimes,
          ),
        ),
      );
      steps.add(erroredStep);
      onStepEnd(
        erroredStep,
        _stepResponseMessages(erroredStep).toList(growable: false),
      );
      // site ②(内部工具 catch):仅派 stepEnd,不派 error——error 由 rethrow 到
      // 外层 catch(site ③)统一派一次,避免 ②③ 双重派发。
      if (dispatcher.isActive) {
        await dispatcher.dispatchStepEnd(erroredStep);
      }
      rethrow;
    }

    final step = StepResult(
      content: content,
      finishReason: resolvedFinishReason,
      usage: usage,
      response: response,
      providerMetadata: stepProviderMetadata,
      executedToolResults: toolResults,
      toolResultOutputs: toolResultOutputs,
      toolApprovalResponses: toolApprovalResponses,
      warnings: stepWarnings,
      runtimeContext: currentRuntimeContext,
      toolsContext: currentToolsContext,
      performance: buildStepPerformance(
        usage: usage,
        responseTime: responseTime,
        stepTime: stepStopwatch.elapsed,
        toolExecutionTimes: toolExecutionTimes,
        timeToFirstOutput: timeToFirstOutput,
        timeBetweenOutputChunks: calculateOutputChunkTimingStats(
          outputChunkTimes,
        ),
      ),
    );
    steps.add(step);
    emit(FinishStepPart(
      usage: usage,
      finishReason: resolvedFinishReason,
      response: response,
    ));
    onStepEnd(step, _stepResponseMessages(step).toList(growable: false));
    // 正常 step 收尾:并联 telemetry stepEnd(与用户 onStepEnd 同处触发)。
    if (dispatcher.isActive) {
      await dispatcher.dispatchStepEnd(step);
    }

    // 追踪(:2237-2271):本步 providerExecuted 且 deferred-capable 的调用,
    // 同响应无配对 tool-result → 记入 pending。判定读用户 ToolSet 快照
    // (toolSet,非 wire 列表、非 activeTools 过滤集)。
    for (final item in step.content.whereType<provider.ToolCall>()) {
      if (item.providerExecuted != true) {
        continue;
      }
      if (toolSet?[item.toolName]?.providerTool?.supportsDeferredResults !=
          true) {
        continue;
      }
      final hasResultInResponse = step.content.any(
        (part) =>
            part is provider.ToolResult && part.toolCallId == item.toolCallId,
      );
      if (!hasResultInResponse) {
        pendingDeferredToolCalls[item.toolCallId] = item.toolName;
      }
    }
    // 解销(:2262-2271):对本响应全部 tool-result 无条件 remove(不限定
    // deferred 工具、不看 isError)——跨步到达的 deferred 结果在此闭环。
    for (final item in step.content.whereType<provider.ToolResult>()) {
      pendingDeferredToolCalls.remove(item.toolCallId);
    }

    final hasToolContentForNextStep =
        toolResults.isNotEmpty || toolApprovalResponses.isNotEmpty;
    final hasBlockingCalls = blockingCalls.isNotEmpty;
    final isToolCallsFinish =
        step.finishReason.unified == provider.FinishReasonType.toolCalls;
    final hasStopConditions = stopConditions.isNotEmpty;
    final stopWhenSatisfied =
        await _anyStopConditionTrue(stopConditions, steps);

    // 无 stopWhen 时恒为单步(v7 行为):即便本步命中工具调用,也不发起第二次
    // 模型调用。pending 支与 client-complete 支平级 OR(:2277-2291),不受
    // isToolCallsFinish/hasToolContentForNextStep/blocking 闸门约束(deferred
    // 悬置步的 finishReason 未必是 toolCalls;审批悬置不阻塞 deferred 闭环)。
    final clientComplete =
        isToolCallsFinish && hasToolContentForNextStep && !hasBlockingCalls;
    final shouldContinue =
        (clientComplete || pendingDeferredToolCalls.isNotEmpty) &&
            hasStopConditions &&
            !stopWhenSatisfied;

    if (!shouldContinue) {
      return false;
    }

    final assistantMessage = _toAssistantMessage(content);
    responseMessages.add(assistantMessage);
    messagesForNextStep = List<provider.LanguageModelMessage>.of(stepMessages)
      ..add(assistantMessage);
    // pending-only 续接(本步无本地工具输出/审批回复)只追加 assistant 消息,
    // 禁止产生空 tool role 消息(对齐 :1325 与 :208-216:tool 消息仅当存在
    // client 工具输出/审批回复才构造)。responseMessages 公开面同受此约束。
    if (hasToolContentForNextStep) {
      final toolMessage = provider.ToolMessage(
        // 内容列表冻结,理由同上。
        List<provider.ToolContentPart>.unmodifiable([
          ...step.toolApprovalResponses,
          for (var i = 0; i < toolResults.length; i++)
            provider.ToolResultPart(
              toolCallId: toolResults[i].toolCallId,
              toolName: toolResults[i].toolName,
              output: toolResultOutputs[i],
            ),
        ]),
      );
      responseMessages.add(toolMessage);
      messagesForNextStep.add(toolMessage);
    }
  }
}

/// 把 `stopWhen`(单个或列表)归一为 `List<StopCondition>`;`null` → 空列表。
List<StopCondition> _normalizeStopWhen(Object? stopWhen) {
  if (stopWhen == null) {
    return const [];
  }
  if (stopWhen is StopCondition) {
    return [stopWhen];
  }
  if (stopWhen is List<StopCondition>) {
    // 拍不可变副本(理由同 streamText 内的 stopWhenSnapshot / tool_loop.dart)。
    return List<StopCondition>.unmodifiable(stopWhen);
  }
  throw ArgumentError.value(
    stopWhen,
    'stopWhen',
    'must be a StopCondition or List<StopCondition>',
  );
}

/// 任一条件为真即算命中(短路)。
Future<bool> _anyStopConditionTrue(
  List<StopCondition> conditions,
  List<StepResult> steps,
) async {
  // 传只读快照给用户谓词:防止 stopWhen 实现改动循环内部的 steps 累加器
  // (steps.clear()/增删),否则会污染最终结果与续/停判定。谓词只需读取,故
  // List.unmodifiable 足够(不深拷贝 StepResult 值对象)。
  final snapshot = List<StepResult>.unmodifiable(steps);
  for (final condition in conditions) {
    if (await condition(snapshot)) {
      return true;
    }
  }
  return false;
}

Future<provider.ToolMessage?> _executeResumedToolApprovals({
  required List<provider.LanguageModelMessage> messages,
  required ToolSet? tools,
  required ToolsContext toolsContext,
  required Object? toolApproval,
  required ToolCallRepairFunction? repairToolCall,
  required String? instructions,
  required provider.CancellationSignal? cancellation,
  required TelemetryDispatcher dispatcher,
}) async {
  final approvals = collectToolApprovals(messages);
  if (approvals.isEmpty) {
    return null;
  }

  final parts = <provider.ToolContentPart>[];
  for (final approval in approvals.approvedToolApprovals) {
    if (approval.toolCall.providerExecuted == true) {
      continue;
    }
    final originalToolCall = _toolCallFromApprovalPart(approval.toolCall);
    if (toolApprovalMayBlockBeforeInput(
      toolApproval: toolApproval,
      toolCall: originalToolCall,
    )) {
      final approvalStatus = await resolveToolApprovalFromInput(
        toolApproval: toolApproval,
        toolCallId: approval.toolCall.toolCallId,
        toolName: approval.toolCall.toolName,
        input: approval.toolCall.input,
        toolCall: originalToolCall,
        providerExecuted: approval.toolCall.providerExecuted,
        providerMetadata: approval.toolCall.providerOptions,
        messages: approval.messages,
        tools: tools,
      );
      if (approvalStatus.type == ToolApprovalStatusType.denied) {
        parts.add(provider.ToolResultPart(
          toolCallId: approval.toolCall.toolCallId,
          toolName: approval.toolCall.toolName,
          output: provider.ToolResultExecutionDenied(
            reason: approvalStatus.reason,
          ),
        ));
        continue;
      }
    }

    final tool = tools?[approval.toolCall.toolName];
    if (tool == null || tool.execute == null) {
      throw StateError(
        'Cannot resume approved tool call ${approval.toolCall.toolCallId} '
        'because executable tool ${approval.toolCall.toolName} is unavailable',
      );
    }
    final parsedCall = await parseOrRepairToolCall(
      toolCall: originalToolCall,
      tools: tools,
      repairToolCall: repairToolCall,
      instructions: instructions,
      messages: approval.messages,
    );
    final toolCall = parsedCall.toolCall;
    if (toolCall.toolName != originalToolCall.toolName ||
        toolCall.toolCallId != originalToolCall.toolCallId) {
      throw StateError(
        'repairToolCall cannot change toolName or toolCallId after '
        'tool approval has been resolved.',
      );
    }
    final approvalStatus = await resolveToolApprovalFromInput(
      toolApproval: toolApproval,
      toolCallId: toolCall.toolCallId,
      toolName: toolCall.toolName,
      input: parsedCall.input,
      toolCall: toolCall,
      providerExecuted: toolCall.providerExecuted,
      providerMetadata: toolCall.providerMetadata,
      messages: approval.messages,
      tools: tools,
    );
    if (approvalStatus.type == ToolApprovalStatusType.denied) {
      parts.add(provider.ToolResultPart(
        toolCallId: approval.toolCall.toolCallId,
        toolName: approval.toolCall.toolName,
        output: provider.ToolResultExecutionDenied(
          reason: approvalStatus.reason,
        ),
      ));
      continue;
    }

    final input = parsedCall.input;
    // 在 telemetry start 之前完成 context 校验,保证 start/end 恒配对。
    final toolContext = _validateToolContext(
      toolName: toolCall.toolName,
      tool: tool,
      toolsContext: toolsContext,
    );
    if (dispatcher.isActive) {
      await dispatcher.dispatchToolExecutionStart(ToolExecutionStartEvent(
        callId: toolCall.toolCallId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: input,
        toolContext: toolContext,
      ));
    }
    // resumed-approval 无步级 toolStopwatch,就地新建计时。
    final resumedStopwatch = Stopwatch()..start();
    final Object? output;
    try {
      output = await tool.execute!(
        input,
        ToolExecuteOptions(
          toolCallId: toolCall.toolCallId,
          messages: approval.messages,
          context: toolContext,
          cancellation: cancellation,
        ),
      );
    } catch (error) {
      if (dispatcher.isActive) {
        await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndError(
          callId: toolCall.toolCallId,
          toolCallId: toolCall.toolCallId,
          toolName: toolCall.toolName,
          error: error,
          toolExecutionMs: resumedStopwatch.elapsed.inMilliseconds,
        ));
      }
      rethrow;
    }
    if (dispatcher.isActive) {
      await dispatcher.dispatchToolExecutionEnd(ToolExecutionEndSuccess(
        callId: toolCall.toolCallId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        output: output,
        toolExecutionMs: resumedStopwatch.elapsed.inMilliseconds,
      ));
    }
    final resultOutput = tool.toModelOutput != null
        ? tool.toModelOutput!(input, output)
        : _defaultToModelOutput(output);
    parts.add(provider.ToolResultPart(
      toolCallId: toolCall.toolCallId,
      toolName: toolCall.toolName,
      output: resultOutput,
    ));
  }
  for (final approval in approvals.deniedToolApprovals) {
    if (approval.toolCall.providerExecuted == true) {
      continue;
    }
    parts.add(provider.ToolResultPart(
      toolCallId: approval.toolCall.toolCallId,
      toolName: approval.toolCall.toolName,
      output: provider.ToolResultExecutionDenied(
        reason: approval.approvalResponse.reason,
      ),
    ));
  }

  if (parts.isEmpty) {
    return null;
  }
  return provider.ToolMessage(
    List<provider.ToolContentPart>.unmodifiable(parts),
  );
}

provider.ToolCall _toolCallFromApprovalPart(provider.ToolCallPart toolCall) {
  return provider.ToolCall(
    toolCallId: toolCall.toolCallId,
    toolName: toolCall.toolName,
    input: jsonEncode(toolCall.input),
    providerExecuted: toolCall.providerExecuted,
    providerMetadata: toolCall.providerOptions,
  );
}

Object? _validateToolContext({
  required String toolName,
  required Tool tool,
  required ToolsContext toolsContext,
}) {
  final context = toolsContext[toolName];
  final schema = tool.contextSchema;
  if (schema == null) {
    return context;
  }
  return validateTypes(context, JsonSchemaValidator.fromContract(schema));
}

/// 默认结果→模型输出映射:`String` → 文本结果,其余 → JSON 结果。
provider.ToolResultOutput _defaultToModelOutput(Object? output) {
  if (output is String) {
    return provider.ToolResultText(output);
  }
  return provider.ToolResultJson(output);
}

/// 把 `ToolResultOutput` 拆箱为 `provider.ToolResult.result` 的 JSON 值
/// (可为 `null`:工具合法返回 null 时原样保留,不规范化为 `{}`——否则
/// `toolResults` 与 `responseMessages` 观察到的结果会不一致)。
///
/// `ToolResultText`/`ToolResultJson` 是脊柱当前默认/自定义输出的主路径;
/// 其余审批/错误/多媒体变体(§1 非目标,暂不深度建模)在此做兜底映射,
/// 保证 `Tool.toModelOutput` 返回任意合法 `ToolResultOutput` 都不会让循环抛异常。
Object? _toolResultOutputValue(provider.ToolResultOutput output) {
  return switch (output) {
    provider.ToolResultText(:final value) => value,
    provider.ToolResultJson(:final value) => value,
    provider.ToolResultErrorText(:final value) => value,
    provider.ToolResultExecutionDenied(:final reason) =>
      reason ?? 'Tool execution denied',
    provider.ToolResultErrorJson(:final value) => value,
    provider.ToolResultContentOutput(:final items) => <String, Object?>{
        'items': [
          for (final item in items)
            switch (item) {
              provider.ToolResultTextItem(:final text) => <String, Object?>{
                  'type': 'text',
                  'text': text,
                },
              provider.ToolResultFileItem(
                :final data,
                :final mediaType,
                :final filename,
              ) =>
                <String, Object?>{
                  'type': 'file',
                  'mediaType': mediaType,
                  if (filename != null) 'filename': filename,
                  // 保留文件数据载荷(FileData:bytes/base64/url/reference),供
                  // 消费者从 toolResults.result 取回文件内容;此前仅取
                  // mediaType/filename 会丢失 data(§1 多媒体为非目标,但不应丢数据)。
                  'data': data,
                },
              provider.ToolResultCustomItem() => <String, Object?>{
                  'type': 'custom',
                },
            },
        ],
      },
  };
}

/// 判断 `ToolResultOutput` 是否为错误变体(`ToolResultErrorText`/
/// `ToolResultErrorJson`),供构造结果 API `provider.ToolResult.isError` 使用。
bool _isErrorOutput(provider.ToolResultOutput output) {
  return switch (output) {
    provider.ToolResultErrorText() => true,
    provider.ToolResultErrorJson() => true,
    _ => false,
  };
}

/// 把本步 `LanguageModelContent` 重建为一条 `provider.AssistantMessage`,
/// 追加进消息历史供下一步续接:text/reasoning/file/reasoning-file/custom 等可
/// 表示内容项 + tool-call + tool-approval-request + provider 侧已执行的
/// tool-result 均参与重建,避免多步工具流丢失模型上一步产出的
/// 文件/推理/自定义内容;SourceContent 暂无对应 assistant part,略过。
///
/// provider 已侧执行(`providerExecuted == true`)的调用会随一条自带的
/// `provider.ToolResult` 一起出现在本步内容里;若不将其重建进历史,
/// 下一步模型请求会丢失该结果,导致模型看不到 provider 侧已执行的产出。
provider.AssistantMessage _toAssistantMessage(
  List<provider.LanguageModelContent> content,
) {
  final parts = <provider.AssistantContentPart>[];
  for (final item in content) {
    if (item is provider.TextContent) {
      parts.add(provider.TextPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningContent) {
      parts.add(provider.ReasoningPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.FileContent) {
      parts.add(provider.FilePart(
        data: item.data,
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningFileContent) {
      parts.add(provider.ReasoningFilePart(
        data: item.data,
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.CustomContentBlock) {
      parts.add(provider.CustomPart(
        item.kind,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolCall) {
      parts.add(provider.ToolCallPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        input: jsonDecode(item.input),
        providerExecuted: item.providerExecuted,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolApprovalRequest) {
      parts.add(provider.ToolApprovalRequestPart(
        approvalId: item.approvalId,
        toolCallId: item.toolCallId,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolResult) {
      parts.add(provider.ToolResultPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        output: item.isError == true
            ? provider.ToolResultErrorJson(item.result)
            : provider.ToolResultJson(item.result),
        providerOptions: item.providerMetadata,
      ));
    }
  }
  // 内容列表冻结:该消息进入跨步复用的 prompt,provider/中间件的原地改动
  // 不得污染循环历史(理由同 convertToLanguageModelPrompt 的构造处冻结)。
  return provider.AssistantMessage(
    List<provider.AssistantContentPart>.unmodifiable(parts),
  );
}

/// 把输出侧 `provider.OutputFileData`(bytes/base64/url)还原为用户面
/// [DataContent],供 `responseMessages` 续接往返(转换层正向映射的对偶)。
DataContent _toDataContent(provider.OutputFileData data) {
  return switch (data) {
    provider.FileDataBytes(:final bytes) => DataBytes(bytes),
    provider.FileDataBase64(:final base64) => DataBase64(base64),
    provider.FileDataUrl(:final url) => DataUrl(url),
  };
}

/// 把一步 [StepResult] 还原为供下一轮续接的 pigcode_ai 用户面消息:
/// 先是一条携带该步文本/推理/文件/推理文件/自定义内容/工具调用/provider 侧
/// 已执行工具结果/审批请求的 [AssistantModelMessage](若有内容),再是(若有
/// 自动审批回复或本地执行的工具结果)一条 [ToolModelMessage]。SourceContent
/// 暂无对应用户面 part,略过。
///
/// provider 已侧执行(`providerExecuted == true`)的调用会随一条自带的
/// `provider.ToolResult` 一起出现在本步内容里;若不将其重建进
/// [AssistantModelMessage],调用方把 `responseMessages` 续接进下一轮请求时
/// 会丢失该结果(与本文件/`generate_text/tool_loop.dart` 的 `_toAssistantMessage`
/// 保持一致)。
Iterable<ModelMessage> _stepResponseMessages(StepResult step) sync* {
  final assistantParts = <AssistantContentPart>[];
  for (final item in step.content) {
    if (item is provider.TextContent) {
      assistantParts.add(TextPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningContent) {
      assistantParts.add(ReasoningPart(
        item.text,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.FileContent) {
      assistantParts.add(FilePart(
        data: _toDataContent(item.data),
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ReasoningFileContent) {
      assistantParts.add(ReasoningFilePart(
        data: _toDataContent(item.data),
        mediaType: item.mediaType,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.CustomContentBlock) {
      assistantParts.add(CustomPart(
        item.kind,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolCall) {
      try {
        assistantParts.add(ToolCallPart(
          toolCallId: item.toolCallId,
          toolName: item.toolName,
          input: jsonDecode(item.input) as provider.JsonValue,
          providerExecuted: item.providerExecuted,
          providerOptions: item.providerMetadata,
        ));
      } on FormatException {
        // 非法 tool-call input 仍保留在 StepResult.content;这里无法忠实重建
        // 需要已解析 JSON 的 ToolCallPart,因此不让续接消息转换覆盖原始错误。
      }
    } else if (item is provider.ToolApprovalRequest) {
      assistantParts.add(ToolApprovalRequestPart(
        approvalId: item.approvalId,
        toolCallId: item.toolCallId,
        providerOptions: item.providerMetadata,
      ));
    } else if (item is provider.ToolResult) {
      assistantParts.add(ToolResultPart(
        toolCallId: item.toolCallId,
        toolName: item.toolName,
        output: item.isError == true
            ? provider.ToolResultErrorJson(item.result)
            : provider.ToolResultJson(item.result),
        providerOptions: item.providerMetadata,
      ));
    }
  }
  if (assistantParts.isNotEmpty) {
    yield AssistantModelMessage(assistantParts);
  }

  if (step.toolResults.isNotEmpty || step.toolApprovalResponses.isNotEmpty) {
    yield ToolModelMessage(
      <ToolContentPart>[
        for (final response in step.toolApprovalResponses)
          ToolApprovalResponsePart(
            approvalId: response.approvalId,
            approved: response.approved,
            reason: response.reason,
            providerOptions: response.providerOptions,
          ),
        for (var i = 0; i < step.toolResults.length; i++)
          ToolResultPart(
            toolCallId: step.toolResults[i].toolCallId,
            toolName: step.toolResults[i].toolName,
            output: step.toolResultOutputs[i],
          ),
      ],
    );
  }
}

ToolModelMessage _toModelToolMessage(provider.ToolMessage message) {
  return ToolModelMessage(<ToolContentPart>[
    for (final part in message.content)
      if (part is provider.ToolApprovalResponsePart)
        ToolApprovalResponsePart(
          approvalId: part.approvalId,
          approved: part.approved,
          reason: part.reason,
          providerOptions: part.providerOptions,
        )
      else if (part is provider.ToolResultPart)
        ToolResultPart(
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output: part.output,
          providerOptions: part.providerOptions,
        ),
  ]);
}
