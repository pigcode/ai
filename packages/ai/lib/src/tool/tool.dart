import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

/// 一组可供模型调用的工具,键为工具名(模型可见),值为对应的 [Tool] 定义。
typedef ToolSet = Map<String, Tool>;

/// 工具执行函数:接收已解析的 JSON 入参与执行期选项,返回执行结果(可异步)。
///
/// 返回值是原始 Dart 对象(未必是 [provider.ToolResultOutput]),由
/// [Tool.toModelOutput] 或默认规则转换为契约层的工具结果。
typedef ToolExecute = FutureOr<Object?> Function(
  provider.JsonValue input,
  ToolExecuteOptions options,
);

/// Called when a tool input starts becoming available.
typedef ToolOnInputStart = FutureOr<void> Function(
  ToolInputStartOptions options,
);

/// Called after the complete tool input has been parsed and validated.
typedef ToolOnInputAvailable = FutureOr<void> Function(
  ToolInputAvailableOptions options,
);

/// Context passed to [Tool.onInputStart].
final class ToolInputStartOptions extends Equatable {
  const ToolInputStartOptions({
    required this.toolCallId,
    required this.messages,
    this.context,
    this.cancellation,
  });

  final String toolCallId;
  final List<provider.LanguageModelMessage> messages;
  final Object? context;
  final provider.CancellationSignal? cancellation;

  @override
  List<Object?> get props =>
      <Object?>[toolCallId, messages, context, cancellation];
}

/// Context passed to [Tool.onInputAvailable].
final class ToolInputAvailableOptions extends Equatable {
  const ToolInputAvailableOptions({
    required this.input,
    required this.toolCallId,
    required this.messages,
    this.context,
    this.cancellation,
  });

  final provider.JsonValue input;
  final String toolCallId;
  final List<provider.LanguageModelMessage> messages;
  final Object? context;
  final provider.CancellationSignal? cancellation;

  @override
  List<Object?> get props =>
      <Object?>[input, toolCallId, messages, context, cancellation];
}

/// 工具执行期的上下文选项。
///
/// 身份语义随调用而变(不同调用的 [toolCallId]/[messages] 不同),但字段
/// 本身是值类型,故用 equatable 做值相等,便于测试断言。
final class ToolExecuteOptions extends Equatable {
  /// 构造工具执行选项。
  const ToolExecuteOptions({
    required this.toolCallId,
    required this.messages,
    this.context,
    this.cancellation,
  });

  /// 本次工具调用的 ID(与模型返回的 tool-call 对应)。
  final String toolCallId;

  /// 触发本次工具调用之前的对话消息(不含系统提示与本步 assistant 消息)。
  ///
  /// **约定:execute 实现应把它视为不可变,不得改动其元素**(与 v7 一致——
  /// v7 亦按可变数组传递、靠此约定兜底;本列表外层已是不可变快照)。
  final List<provider.LanguageModelMessage> messages;

  /// 当前工具的调用上下文,来自 `toolsContext[toolName]`。
  final Object? context;

  /// 取消信号(可空):execute 实现应尽力响应取消。
  final provider.CancellationSignal? cancellation;

  @override
  List<Object?> get props =>
      <Object?>[toolCallId, messages, context, cancellation];
}

/// 工具定义:函数工具(inputSchema+execute)**或** provider 定义工具
/// (`Tool.provider`,承载契约 ProviderTool + 可选客户端 execute)。
///
/// 两类都可下发给模型;核心按 name 匹配工具——有 execute 的由核心执行,
/// providerExecuted 结果(如 web_search)走回流通道不本地执行,无 execute 的
/// 普通 tool_call 进入阻塞/待处理。
final class Tool {
  /// 构造一个函数工具定义。
  // 故意不用 `this.inputSchema`:字段现为可空(provider 工具恒 null),初始化
  // 形参会继承该可空类型,使 `Tool(inputSchema: null)` 编译通过并产出既非
  // provider 工具、又无 schema 的坏实例(buildLanguageModelTools 会撞
  // `inputSchema!`、parser 又误当 provider 工具跳校验)。非空位置参 + 显式
  // initializer 才能在编译期强制函数工具的 schema 非空(codex PR #62 复审)。
  const Tool({
    required provider.JsonSchema inputSchema,
    this.description,
    this.inputExamples,
    this.contextSchema,
    this.onInputStart,
    this.onInputAvailable,
    this.execute,
    this.toModelOutput,
  })  : inputSchema = inputSchema, // ignore: prefer_initializing_formals
        providerTool = null;

  /// provider 定义工具:承载契约 [provider.ProviderTool] wire 定义 +
  /// 可选客户端 [execute]。核心工具循环按 ToolSet key(= wire name)匹配执行。
  // 故意不用 `this.providerTool`:该写法会继承字段的 nullable 类型,使
  // `Tool.provider(null)` 编译通过并落入半初始化态;非空位置参 + 显式
  // initializer 才能在编译期阻止传 null(spec 定案)。
  const Tool.provider(
    provider.ProviderTool providerTool, {
    this.execute,
    this.toModelOutput,
    this.contextSchema,
    this.onInputStart,
    this.onInputAvailable,
  })  : providerTool = providerTool, // ignore: prefer_initializing_formals
        inputSchema = null,
        description = null,
        inputExamples = null;

  /// 入参 JSON Schema(复用契约 [provider.JsonSchema])。函数工具非空;
  /// provider 定义工具恒为 `null`。
  final provider.JsonSchema? inputSchema;

  /// 工具用途描述,供模型理解何时调用(可空)。
  final String? description;

  /// 工具入参示例,供模型理解如何填充 JSON 入参。
  final List<provider.JsonObject>? inputExamples;

  /// 可选的工具上下文 schema,用于校验 `toolsContext` 中该工具的上下文。
  final provider.JsonSchema? contextSchema;

  /// Invoked before the complete input is exposed.
  final ToolOnInputStart? onInputStart;

  /// Invoked after input parsing/validation and after [onInputStart].
  final ToolOnInputAvailable? onInputAvailable;

  /// provider 定义工具的契约 wire 定义(可空)。仅 [Tool.provider] 构造的
  /// 工具非空;函数工具恒为 `null`。
  final provider.ProviderTool? providerTool;

  /// 工具的执行体。为 `null` 时该工具调用会使循环暂停
  /// (结果里体现未执行的 tool-call,交由客户端/审批流程处理)。
  final ToolExecute? execute;

  /// 自定义「执行结果 → 模型可见输出」的转换函数(可空)。
  ///
  /// 未提供时,循环引擎按默认规则转换:[String] → [provider.ToolResultText]
  /// 、其余值 → [provider.ToolResultJson]。
  final provider.ToolResultOutput Function(
    provider.JsonValue input,
    Object? output,
  )? toModelOutput;
}

/// 身份函数:仅用于书写时的类型标注/未来类型推断辅助,原样返回传入的 [Tool]。
Tool tool(Tool t) => t;

/// 把 [ToolSet] 映射为契约 [provider.LanguageModelTool] 列表(函数工具 →
/// [provider.FunctionTool];provider 工具 → [provider.ProviderTool],以 ToolSet
/// key 作 wire name),供 `LanguageModelCallOptions.tools` 使用。
List<provider.LanguageModelTool> buildLanguageModelTools(ToolSet tools) =>
    <provider.LanguageModelTool>[
      for (final entry in tools.entries)
        if (entry.value.providerTool case final pt?)
          if (entry.key != pt.name)
            // fail-fast:ToolSet key 必须 = wire name,否则模型返回的 toolName
            // (= wire name)在 ToolSet 里(key=别名)查不到 execute。
            throw ArgumentError(
              'provider tool ToolSet key "${entry.key}" must equal its wire '
              'name "${pt.name}"',
            )
          else
            provider.ProviderTool(
              id: pt.id,
              name: entry.key,
              args: pt.args,
              // 重建副本保真 deferred 标记:核心续接判定读用户 ToolSet 原件,
              // 但重建结果进 callOptions.tools,漏复制会使副本与原件不等值。
              supportsDeferredResults: pt.supportsDeferredResults,
            )
        else
          provider.FunctionTool(
            name: entry.key,
            description: entry.value.description,
            inputSchema: entry.value.inputSchema!,
            inputExamples: entry.value.inputExamples,
          ),
    ];
