import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:equatable/equatable.dart';

/// 脚本化 [lm.LanguageModel] 的一次预设回合。
///
/// 描述 [ScriptedModel.doGenerate] 一次调用应返回的内容 / 终止原因 / 用量,
/// 以及 [ScriptedModel.doStream] 应据此展开的等价分块序列。仅供测试支撑
/// (`test/support/`),不进入 `lib/` 正式产物。
final class ScriptedTurn with EquatableMixin {
  /// 创建一个脚本化回合。
  ///
  /// [content] 是本回合 doGenerate 应返回的有序内容项(文本、工具调用等);
  /// [finishReason]/[usage] 对应本回合的终止原因与用量;[warnings] 默认为空。
  /// [responseMetadata] 可空:仅 [ScriptedModel.doStream] 会在内容分块之后、
  /// [lm.FinishPart] 之前额外插入这一个 [lm.ResponseMetadata] 分块([doGenerate]
  /// 走 [lm.LanguageModelGenerateResult],无对应字段可携带,故忽略此项)。
  const ScriptedTurn({
    required this.content,
    required this.finishReason,
    required this.usage,
    this.warnings = const [],
    this.responseMetadata,
    this.providerMetadata,
  });

  /// 本回合的有序输出内容项。
  final List<lm.LanguageModelContent> content;

  /// 本回合的终止原因。
  final lm.LanguageModelFinishReason finishReason;

  /// 本回合的 token 用量。
  final lm.LanguageModelUsage usage;

  /// 本回合随 [lm.StreamStart] 一并发出的告警;默认为空列表。
  final List<lm.Warning> warnings;

  /// 仅供 [ScriptedModel.doStream] 展开的响应元数据分块(可空)。
  final lm.ResponseMetadata? responseMetadata;

  /// 本回合的结果级 provider 元数据(可空):[ScriptedModel.doGenerate] 放进
  /// [lm.LanguageModelGenerateResult.providerMetadata],[ScriptedModel.doStream]
  /// 放进末尾 [lm.FinishPart.providerMetadata]。
  final lm.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => [
        content,
        finishReason,
        usage,
        warnings,
        responseMetadata,
        providerMetadata,
      ];
}

/// 可脚本化的 fake [lm.LanguageModel],仅用于测试支撑(`test/support/`)。
///
/// 按构造时给定的 [turns] 顺序消费:每调用一次 [doGenerate] 或 [doStream]
/// 就取用下一个 [ScriptedTurn]。[doStream] 把该回合内容展开为等价的
/// [lm.LanguageModelStreamPart] 序列:[lm.StreamStart] →
/// 逐内容项(文本 → [lm.TextStart]/[lm.TextDelta]/[lm.TextEnd];
/// [lm.ToolCall] 原样发出) → [lm.FinishPart]。
///
/// 每次 [doGenerate]/[doStream] 调用都会把收到的 [lm.LanguageModelCallOptions]
/// 追加进 [receivedCallOptions],供上层测试断言透传字段(如 tools/toolChoice/
/// cancellation)。调用次数超出 [turns] 长度时抛出 [StateError](编程错误,
/// 非「错误即事件」契约覆盖的模型失败)。
final class ScriptedModel implements lm.LanguageModel {
  /// 用给定的回合序列创建一个 [ScriptedModel]。
  ///
  /// [turns] 是按调用顺序消费的脚本;[provider]/[modelId] 可选,默认分别为
  /// `'scripted'`/`'scripted-model'`。
  ScriptedModel({
    required this.turns,
    String? provider,
    String? modelId,
  })  : provider = provider ?? 'scripted',
        modelId = modelId ?? 'scripted-model';

  /// 按调用顺序消费的脚本回合序列。
  final List<ScriptedTurn> turns;

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  /// 已发生的 doGenerate/doStream 调用次数。
  int get callCount => _callCount;
  int _callCount = 0;

  /// 每次 doGenerate/doStream 收到的 [lm.LanguageModelCallOptions],
  /// 按调用顺序追加,便于断言上层透传的字段。
  final List<lm.LanguageModelCallOptions> receivedCallOptions = [];

  ScriptedTurn _nextTurn() {
    if (_callCount >= turns.length) {
      throw StateError(
          'ScriptedModel: no scripted turn left for call ${_callCount + 1}');
    }
    final turn = turns[_callCount];
    _callCount++;
    return turn;
  }

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    final turn = _nextTurn();
    return lm.LanguageModelGenerateResult(
      content: turn.content,
      finishReason: turn.finishReason,
      usage: turn.usage,
      warnings: turn.warnings,
      providerMetadata: turn.providerMetadata,
    );
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return lm.LanguageModelStreamResult(
      stream: _streamTurn(),
    );
  }

  // 惰性获取下一个 turn:调用超限时的 StateError 需在流被消费(如
  // `.stream.toList()`)时抛出,而非在 `doStream` 的 Future 上提前抛出。
  Stream<lm.LanguageModelStreamPart> _streamTurn() async* {
    final turn = _nextTurn();
    yield lm.StreamStart(turn.warnings);

    var textBlockId = 0;
    var reasoningBlockId = 0;
    for (final item in turn.content) {
      if (item is lm.TextContent) {
        final id = 'text-${textBlockId++}';
        yield lm.TextStart(id);
        yield lm.TextDelta(id, item.text);
        yield lm.TextEnd(id);
      } else if (item is lm.ReasoningContent) {
        // 推理内容与文本同构展开为 id 关联的 Reasoning* 事件序列。
        final id = 'reasoning-${reasoningBlockId++}';
        yield lm.ReasoningStart(id);
        yield lm.ReasoningDelta(id, item.text);
        yield lm.ReasoningEnd(id);
      } else if (item is lm.LanguageModelStreamPart) {
        yield item as lm.LanguageModelStreamPart;
      } else {
        throw StateError(
          'ScriptedModel: content item ${item.runtimeType} has no stream '
          'equivalent (only TextContent and stream-capable content are supported)',
        );
      }
    }

    if (turn.responseMetadata != null) {
      yield turn.responseMetadata!;
    }

    yield lm.FinishPart(
      usage: turn.usage,
      finishReason: turn.finishReason,
      providerMetadata: turn.providerMetadata,
    );
  }
}

/// 最小 fake [lm.LanguageModel]:doStream 只发 [lm.StreamStart] 后立即发一个
/// [lm.ErrorPart] 终端事件,用于验证 streamText 不在 ErrorPart 之后追加
/// FinishPart(error-as-terminal 语义)。[doGenerate] 不支持。
final class ErrorStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'err';

  @override
  String get modelId => 'err-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.ErrorPart('boom'),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:`doStream` 返回值携带非空
/// [lm.LanguageModelStreamResult.request],用于验证 `streamText` 把该请求侧
/// 调试/回放元数据转发进 `StartStepPart.request`([ScriptedModel] 无法设置
/// `LanguageModelStreamResult.request`,故需要这个专用支撑模型)。
/// [doGenerate] 不支持。
final class RequestMetadataStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'request-metadata';

  @override
  String get modelId => 'request-metadata-model';

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
        request: const lm.RequestInfo(
          body: {'model': 'request-metadata-model'},
        ),
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'hi'),
          lm.TextEnd('text-0'),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 1),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:`doStream` 在文本分块之后额外发出一个
/// [lm.RawPart],用于验证 `streamText` 把它转发为公共 `RawStreamPart`
/// ([lm.RawPart] 只实现 [lm.LanguageModelStreamPart],不实现
/// [lm.LanguageModelContent],故 [ScriptedTurn.content] 无法携带它,
/// 需要这个专用支撑模型)。[doGenerate] 不支持。
final class RawChunkStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'raw-chunk';

  @override
  String get modelId => 'raw-chunk-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'hi'),
          lm.TextEnd('text-0'),
          const lm.RawPart({'raw': 'chunk-1'}),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 1),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:同时通过两条独立通道携带响应元数据——
/// `doStream` 返回值的 [lm.LanguageModelStreamResult.response](携带
/// headers/body)与流内的 [lm.ResponseMetadata] 分块(携带 id/modelId)。
/// 用于验证 `streamText` 把二者合并进最终 `StepResult.response`,而非其中
/// 一条覆盖/丢失另一条([ScriptedModel] 无法设置
/// `LanguageModelStreamResult.response`,故需要这个专用支撑模型)。
/// [doGenerate] 不支持。
final class ResponseSplitStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'response-split';

  @override
  String get modelId => 'response-split-model';

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
        response: const lm.ResponseInfo(
          headers: {'x-request-id': 'req-abc'},
          body: {'raw': 'body'},
        ),
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'hi'),
          lm.TextEnd('text-0'),
          const lm.ResponseMetadata(id: 'resp-1', modelId: 'split-model-v2'),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 3),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:每次 [doGenerate]/[doStream] 被调用时先触发
/// [onInvoke] 回调,再返回「单条 tool-call、finishReason=toolCalls」的一个回合。
///
/// 用于在「模型运行期间」模拟 caller 改动共享的 tools map:工具循环在循环开始
/// 时先对 [ToolSet] 拍快照,再 `await` 模型;[onInvoke] 在该 await 点之后、循环
/// 拿到模型结果后按名查表之前触发(即快照之后)。据此可验证循环执行用的是
/// 快照而非实时读取——若读实时 map(已被 [onInvoke] 清空),已广告的工具会查
/// 不到而被当作 blocking,不产出结果。[provider]/[modelId] 固定。
final class ToolCallOnInvokeModel implements lm.LanguageModel {
  /// [toolCallId]/[toolName]/[input] 描述本回合唯一的工具调用;[onInvoke] 在
  /// 每次模型调用开始时触发(如清空 caller 的 tools map)。
  ToolCallOnInvokeModel({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    required this.onInvoke,
  });

  final String toolCallId;
  final String toolName;
  final String input;
  final void Function() onInvoke;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'tool-call-on-invoke';

  @override
  String get modelId => 'tool-call-on-invoke-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  static const _finishReason =
      lm.LanguageModelFinishReason(lm.FinishReasonType.toolCalls);
  static const _usage = lm.LanguageModelUsage(
    inputTokens: lm.InputTokens(total: 1),
    outputTokens: lm.OutputTokens(total: 1),
  );

  lm.ToolCall get _call =>
      lm.ToolCall(toolCallId: toolCallId, toolName: toolName, input: input);

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    onInvoke();
    return lm.LanguageModelGenerateResult(
      content: [_call],
      finishReason: _finishReason,
      usage: _usage,
      warnings: const [],
    );
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    onInvoke();
    return lm.LanguageModelStreamResult(
      stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
        lm.StreamStart(const []),
        _call,
        lm.FinishPart(usage: _usage, finishReason: _finishReason),
      ]),
    );
  }
}

/// 最小 fake [lm.LanguageModel]:doStream 故意先发一个非 [lm.StreamStart] 分块
/// (TextStart/Delta),再「迟到」发一个 [lm.StreamStart],用于验证 streamText 的
/// 兜底逻辑在已补发过 StartStepPart 后,不会因这个迟到的 StreamStart 再发一次
/// (即步骤开始框架分块不重复)。[doGenerate] 不支持。
final class LateStreamStartModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'late-stream-start';

  @override
  String get modelId => 'late-stream-start-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          // 先发非 StreamStart 分块 → 触发 streamText 兜底补发 StartStepPart。
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'hi'),
          // 迟到的 StreamStart:不应再触发第二个 StartStepPart。
          lm.StreamStart(const []),
          lm.TextEnd('text-0'),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 1),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:doStream 在 StreamStart 之后发出一个「内容型」
/// 分块([lm.SourceContent],同时实现 [lm.LanguageModelContent] 与
/// [lm.LanguageModelStreamPart]),用于验证 streamText 把未显式建模的
/// LanguageModelContent 流分块保留进 step.content(与非流式 result.content 一致),
/// 而非在 switch 的 default 分支丢弃。[doGenerate] 不支持。
final class SourceContentStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'source-content';

  @override
  String get modelId => 'source-content-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          const lm.SourceContent.url(id: 's1', url: 'https://example.com'),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 1),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:doStream 先发出一个完整文本块,再发出终端
/// [lm.ErrorPart](本步中途报错),用于验证 streamText 把 ErrorPart 之前已产出的
/// 部分文本固化进 result.text / result.steps(作为一步 error,而非因错误丢弃)。
/// [doGenerate] 不支持。
final class TextThenErrorStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'text-then-error';

  @override
  String get modelId => 'text-then-error-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'partial'),
          lm.TextEnd('text-0'),
          lm.ErrorPart('boom'),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:doStream 发出 TextStart/TextDelta 后**不发**
/// TextEnd 就直接发终端 [lm.ErrorPart](文本块未闭合就中途报错),用于验证
/// streamText 在报错时冲刷 textBuffers 里尚未闭合的部分文本,保留进 result.text /
/// result.steps。[doGenerate] 不支持。
final class OpenTextThenErrorStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'open-text-then-error';

  @override
  String get modelId => 'open-text-then-error-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.TextStart('text-0'),
          lm.TextDelta('text-0', 'partial'),
          // 无 TextEnd:文本块未闭合就报错。
          lm.ErrorPart('boom'),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:doStream 发出 ReasoningStart/ReasoningDelta 后
/// **不发** ReasoningEnd 就直接发终端 [lm.ErrorPart](推理块未闭合就中途报错),
/// 用于验证 streamText 报错时冲刷 reasoningBuffers 里尚未闭合的部分推理,
/// 保留进 error 步的 content。[doGenerate] 不支持。
final class OpenReasoningThenErrorStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'open-reasoning-then-error';

  @override
  String get modelId => 'open-reasoning-then-error-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.ReasoningStart('reasoning-0'),
          lm.ReasoningDelta('reasoning-0', 'partial-think'),
          // 无 ReasoningEnd:推理块未闭合就报错。
          lm.ErrorPart('boom'),
        ]),
      );
}

/// 最小 fake [lm.LanguageModel]:doStream 发出的 TextStart/TextEnd 与
/// ReasoningStart/ReasoningEnd 都各自携带 providerMetadata(仿 OpenAI
/// Responses 流:itemId 落在 Start,reasoningEncryptedContent 只在 End 才
/// 可用),用于验证 streamText 聚合 text/reasoning 内容项时把这些流事件的
/// providerMetadata 捕获进 [lm.TextContent]/[lm.ReasoningContent](而非
/// 恒为 `null`),且 End 的非空 metadata 覆盖 Start 的值(v7
/// `stream-text.ts` 的 `activeTextContent`/`activeReasoningContent` 合并
/// 规则:最新非空值胜出)。[doGenerate] 不支持。
final class MetadataOnStartAndEndStreamModel implements lm.LanguageModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'metadata-on-start-and-end';

  @override
  String get modelId => 'metadata-on-start-and-end-model';

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
        stream: Stream.fromIterable(<lm.LanguageModelStreamPart>[
          lm.StreamStart(const []),
          lm.ReasoningStart(
            'reasoning-0',
            providerMetadata: const {
              'openai': {'itemId': 'rs_1'},
            },
          ),
          lm.ReasoningDelta('reasoning-0', 'think'),
          lm.ReasoningEnd(
            'reasoning-0',
            providerMetadata: const {
              'openai': {'itemId': 'rs_1', 'reasoningEncryptedContent': 'enc'},
            },
          ),
          lm.TextStart(
            'text-0',
            providerMetadata: const {
              'openai': {'itemId': 'msg_1'},
            },
          ),
          lm.TextDelta('text-0', 'ok'),
          lm.TextEnd(
            'text-0',
            providerMetadata: const {
              'openai': {'itemId': 'msg_1', 'refined': true},
            },
          ),
          lm.FinishPart(
            usage: const lm.LanguageModelUsage(
              inputTokens: lm.InputTokens(total: 1),
              outputTokens: lm.OutputTokens(total: 1),
            ),
            finishReason: const lm.LanguageModelFinishReason(
              lm.FinishReasonType.stop,
            ),
          ),
        ]),
      );
}
