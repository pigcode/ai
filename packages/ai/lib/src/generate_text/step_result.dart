import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import 'context.dart';
import 'request_options_snapshot.dart';

/// 输出分块之间的时间间隔统计。
final class OutputChunkTimingStats extends Equatable {
  /// 创建输出分块间隔统计。
  const OutputChunkTimingStats({
    required this.min,
    required this.p10,
    required this.median,
    required this.average,
    required this.p90,
    required this.max,
  });

  /// 最短输出分块间隔。
  final Duration min;

  /// 第 10 百分位输出分块间隔。
  final Duration p10;

  /// 中位输出分块间隔。
  final Duration median;

  /// 平均输出分块间隔。
  final Duration average;

  /// 第 90 百分位输出分块间隔。
  final Duration p90;

  /// 最长输出分块间隔。
  final Duration max;

  @override
  List<Object?> get props => [min, p10, median, average, p90, max];
}

/// 单步生成性能指标。
final class StepResultPerformance extends Equatable {
  /// 创建单步生成性能指标。
  StepResultPerformance({
    required this.effectiveOutputTokensPerSecond,
    this.outputTokensPerSecond,
    this.inputTokensPerSecond,
    required this.effectiveTotalTokensPerSecond,
    required this.stepTime,
    required this.responseTime,
    Map<String, Duration> toolExecutionTimes = const {},
    this.timeToFirstOutput,
    this.timeBetweenOutputChunks,
  }) : toolExecutionTimes = Map<String, Duration>.unmodifiable(
          toolExecutionTimes,
        );

  /// 空性能指标,供手工构造 [StepResult] 的测试或内部值对象场景使用。
  factory StepResultPerformance.empty() => StepResultPerformance(
        effectiveOutputTokensPerSecond: 0,
        effectiveTotalTokensPerSecond: 0,
        stepTime: Duration.zero,
        responseTime: Duration.zero,
      );

  /// 整个模型响应期间的有效输出 token/s。
  final double effectiveOutputTokensPerSecond;

  /// 首个输出分块之后的输出 token/s。仅流式步骤可用。
  final double? outputTokensPerSecond;

  /// 首个输出分块之前的输入 token/s。仅流式步骤可用。
  final double? inputTokensPerSecond;

  /// 整个模型响应期间的有效总 token/s。
  final double effectiveTotalTokensPerSecond;

  /// 本步骤总耗时,包含模型响应与本地工具执行。
  final Duration stepTime;

  /// 模型响应耗时,不包含本地工具执行。
  final Duration responseTime;

  /// 本地工具执行耗时,键为 toolCallId。
  final Map<String, Duration> toolExecutionTimes;

  /// 从步骤开始到首个真实输出分块的耗时。仅流式步骤可用。
  final Duration? timeToFirstOutput;

  /// 输出分块之间的间隔统计。仅流式步骤有至少两个输出分块时可用。
  final OutputChunkTimingStats? timeBetweenOutputChunks;

  @override
  List<Object?> get props => [
        effectiveOutputTokensPerSecond,
        outputTokensPerSecond,
        inputTokensPerSecond,
        effectiveTotalTokensPerSecond,
        stepTime,
        responseTime,
        toolExecutionTimes,
        timeToFirstOutput,
        timeBetweenOutputChunks,
      ];
}

/// 单步模型调用的结果:契约输出内容项 + 终止原因 + 用量 + 响应元数据 +
/// 本步执行出的工具结果。
///
/// 派生 getter([text]/[toolCalls]/[toolResults])均由 [content]/
/// [executedToolResults] 计算得出,不单独存储。
final class StepResult extends Equatable {
  /// 创建一步结果。
  ///
  /// 列表字段（[content]/[executedToolResults]/[toolResultOutputs]/
  /// [toolApprovalResponses]）在构造时
  /// 固化为不可变视图,使 StepResult 成为真正的不可变值对象:任何消费者——
  /// 包括 stopWhen 谓词、以及拿到返回结果的调用方——都只能读取,无法改动循环
  /// 内部累加器(否则会污染最终结果与续/停判定)。因需 `List.unmodifiable`
  /// 包装,本构造函数非 const(StepResult 由运行时数据构造,本就无 const 用途)。
  StepResult({
    required List<provider.LanguageModelContent> content,
    required this.finishReason,
    required this.usage,
    required this.response,
    this.providerMetadata,
    required List<provider.ToolResult> executedToolResults,
    List<provider.ToolResultOutput> toolResultOutputs = const [],
    List<provider.ToolApprovalResponsePart> toolApprovalResponses = const [],
    List<provider.Warning> warnings = const [],
    RuntimeContext runtimeContext = const {},
    ToolsContext toolsContext = const {},
    required this.performance,
  })  : content = List<provider.LanguageModelContent>.unmodifiable(content),
        executedToolResults =
            List<provider.ToolResult>.unmodifiable(executedToolResults),
        toolResultOutputs =
            List<provider.ToolResultOutput>.unmodifiable(toolResultOutputs),
        toolApprovalResponses =
            List<provider.ToolApprovalResponsePart>.unmodifiable(
          toolApprovalResponses,
        ),
        warnings = List<provider.Warning>.unmodifiable(warnings),
        runtimeContext = snapshotRuntimeContext(runtimeContext),
        toolsContext = snapshotToolsContext(toolsContext);

  /// 契约面有序输出内容项。
  final List<provider.LanguageModelContent> content;

  /// 本步终止原因。
  final provider.LanguageModelFinishReason finishReason;

  /// 本步 token 用量。
  final provider.LanguageModelUsage usage;

  /// 本步响应侧元数据。
  final provider.ResponseInfo? response;

  /// 本步模型结果携带的 provider 私有元数据(可空):非流式来自
  /// `doGenerate` 结果的 providerMetadata,流式来自 FinishPart 的
  /// providerMetadata;缺席语义真实成立(provider 可不产出),故为可选参。
  final provider.ProviderMetadata? providerMetadata;

  /// 本步循环引擎实际执行出的工具结果(非 provider 直出的 [provider.ToolResult]
  /// 内容项,而是工具循环调用 `execute` 后产出的结果)。
  final List<provider.ToolResult> executedToolResults;

  /// 与 [executedToolResults] 一一对应、按相同顺序排列的原始
  /// [provider.ToolResultOutput] 变体(`toModelOutput` 的返回值,或
  /// 默认映射的结果)。
  ///
  /// [executedToolResults] 中的 `provider.ToolResult.result` 是拆箱后的扁平值
  /// (供结果 API 直接读取);而这里保留的是未拆箱的判别联合本身,供续接
  /// 消息(下一步喂给模型的 [provider.ToolResultPart.output]、以及
  /// `responseMessages`)保真回放错误/拒绝/多媒体等非纯文本/JSON 变体,
  /// 不经拆箱-重包这道有损往返。
  final List<provider.ToolResultOutput> toolResultOutputs;

  /// 本步自动审批产生的回复 part。需要它来重建公开 [responseMessages] 和
  /// 内部续接 prompt 的 tool 消息。
  final List<provider.ToolApprovalResponsePart> toolApprovalResponses;

  /// 本步 provider 侧告警(如某选项被忽略/降级的 [provider.UnsupportedWarning]),
  /// 对齐 v7 `StepResult.warnings`:非流式来自 `doGenerate` 结果,流式来自
  /// `StreamStart` 分块;默认为空列表。
  final List<provider.Warning> warnings;

  /// 本步使用的运行时上下文。
  final RuntimeContext runtimeContext;

  /// 本步使用的按工具名索引的工具上下文。
  final ToolsContext toolsContext;

  /// 本步模型响应与本地工具执行的性能指标。
  final StepResultPerformance performance;

  /// 拼接 [content] 中所有 [provider.TextContent] 的文本,按出现顺序连接。
  String get text =>
      content.whereType<provider.TextContent>().map((c) => c.text).join();

  /// [content] 中的推理内容项,包括文本推理与推理文件。
  List<provider.LanguageModelContent> get reasoning => content
      .where(
        (c) =>
            c is provider.ReasoningContent ||
            c is provider.ReasoningFileContent,
      )
      .toList();

  /// 拼接 [content] 中所有文本推理内容。
  ///
  /// 若本步没有文本推理,或推理文本为空字符串,返回 `null`。
  String? get reasoningText {
    final text = content
        .whereType<provider.ReasoningContent>()
        .map((c) => c.text)
        .join();
    return text.isEmpty ? null : text;
  }

  /// [content] 中的文件内容项。
  List<provider.FileContent> get files =>
      content.whereType<provider.FileContent>().toList();

  /// [content] 中的来源引用内容项。
  List<provider.SourceContent> get sources =>
      content.whereType<provider.SourceContent>().toList();

  /// [content] 中的工具调用项。
  List<provider.ToolCall> get toolCalls =>
      content.whereType<provider.ToolCall>().toList();

  /// 本步执行出的工具结果,即 [executedToolResults]。
  List<provider.ToolResult> get toolResults => executedToolResults;

  @override
  List<Object?> get props => [
        content,
        finishReason,
        usage,
        response,
        executedToolResults,
        toolResultOutputs,
        toolApprovalResponses,
        warnings,
        runtimeContext,
        toolsContext,
        performance,
        providerMetadata,
      ];
}
