import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;

import '../internal/error_structure.dart';
import '../utils/metadata_extractor.dart';
import 'chat_options.dart';
import 'convert_messages.dart';
import 'convert_usage.dart';
import 'map_finish_reason.dart';
import 'prepare_tools.dart';
import 'response_metadata.dart';

/// `OpenAiCompatibleChatLanguageModel` 的运行时配置:全部字段均为可插拔
/// 扩展点(除 `providerName`/`url`/`headers` 三个必填项),`null` 时退化到
/// 各自的默认行为。逐字对照 raw `OpenAICompatibleChatConfig`
/// (`raw/compatible__openai-compatible-chat-language-model.ts` ~61-94 行)。
final class OpenAiCompatibleChatConfig {
  /// 用给定字段构造一份配置。
  const OpenAiCompatibleChatConfig({
    required this.providerName,
    required this.url,
    required this.headers,
    this.client,
    this.includeUsage = false,
    this.supportsStructuredOutputs = false,
    this.errorStructure,
    this.metadataExtractor,
    this.supportedUrls,
    this.transformRequestBody,
    this.convertUsage,
  });

  /// provider 标识(纯 name,不含 `.chat` 后缀;`provider` getter 在此基础上
  /// 拼接)。同时也是 providerOptions 的解析 key(单一路径,无 azure 式
  /// 多路径派生——spec §6 已裁决,本包无历史包袱)。
  final String providerName;

  /// 由请求路径(如 `'/chat/completions'`)构造完整请求 URL 的闭包;
  /// queryParams 的拼接已在工厂构造该闭包时完成,本文件不关心。
  final Uri Function(String path) url;

  /// 每次请求求值一次的 header 构造函数。
  final Map<String, String> Function() headers;

  /// 可选注入的 HTTP client。
  final http.Client? client;

  /// 是否在流式请求体中带上 `stream_options: {include_usage: true}`。
  /// 默认 `false`——与 pigcode_ai_openai chat 硬编码 `true` 相反(spec 对照表)。
  final bool includeUsage;

  /// 该模型是否支持 `response_format: {type: 'json_schema', ...}` 结构化
  /// 输出。默认 `false`;为 `false` 时 JSON 响应格式退化为
  /// `{type: 'json_object'}`。
  final bool supportsStructuredOutputs;

  /// 错误体结构(校验器 + 消息提取器 + 可选可重试判定);`null` 时用
  /// [defaultOpenAiCompatibleErrorStructure]。
  final ProviderErrorStructure? errorStructure;

  /// provider 元数据提取钩子;`null` 时不提取任何额外元数据。
  final MetadataExtractor? metadataExtractor;

  /// 支持原生透传(不下载)的 URL 模式;`null` 时退化为空表。
  final Map<String, List<RegExp>> Function()? supportedUrls;

  /// 请求体编码前的最终变换钩子;`null` 时恒等函数。**doGenerate/doStream
  /// 均在参数组装完毕、即将发起 HTTP 请求前的最后一步各自独立调用一次**,
  /// 入参是即将发送的完整请求体(doStream 侧含 `stream`/`stream_options`),
  /// 对齐 raw doGenerate ~332-333 / doStream ~437-445 的应用时机。
  final JsonObject Function(JsonObject args)? transformRequestBody;

  /// usage 转换覆盖;`null` 时用 [convertOpenAiCompatibleChatUsage]。
  final LanguageModelUsage Function(JsonObject usage)? convertUsage;
}

/// OpenAI 兼容 Chat Completions(`/chat/completions`)的 [LanguageModel]
/// 实现;全部行为围绕 [OpenAiCompatibleChatConfig] 的可插拔扩展点展开,
/// wire 语义在扩展点未被覆盖时逐字对照 raw
/// `raw/compatible__openai-compatible-chat-language-model.ts`。
final class OpenAiCompatibleChatLanguageModel implements LanguageModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 chat 模型实例。
  OpenAiCompatibleChatLanguageModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 本模型实例的运行时配置(可插拔扩展点的唯一来源)。
  final OpenAiCompatibleChatConfig config;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => '${config.providerName}.chat';
  // v7 的 config.provider 是完整 '<name>.chat' 字符串,providerOptionsName
  // 用 split('.')[0] 反推;pigcode 模式(同 pigcode_ai_openai)存纯 name,
  // provider getter 拼接后缀,providerOptionsName 直接等于 config.providerName
  // ——两种存法语义等价,此处是实现差异而非行为差异,详见计划骨架跨任务
  // 接口契约的对应注记。

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls =>
      config.supportedUrls?.call() ?? const {};

  /// [OpenAiCompatibleChatConfig.errorStructure] 缺省时的错误体结构;按需
  /// 求值,构造函数不做任何计算以保持配置对象轻量。
  ProviderErrorStructure get _errorStructure =>
      config.errorStructure ?? defaultOpenAiCompatibleErrorStructure;

  FailedResponseHandler get _failedResponseHandler =>
      openAiCompatibleFailedResponseHandler(_errorStructure);

  /// chat 请求体构造:`doGenerate`/`doStream` 共用,`doStream` 只在此基础上
  /// 追加 `stream`/`stream_options`(Task 5)。
  ///
  /// wire 语义逐字对照 raw `getArgs`
  /// (`raw/compatible__openai-compatible-chat-language-model.ts` ~172-325
  /// 行)。
  ({JsonObject args, List<Warning> warnings}) _buildArgs(
    LanguageModelCallOptions options,
  ) {
    final warnings = <Warning>[];

    final compatibleOptions =
        OpenAiCompatibleChatProviderOptions.fromProviderOptions(
      options.providerOptions,
      providerOptionsName: config.providerName,
    );

    if (options.topK != null) {
      warnings.add(const UnsupportedWarning('topK'));
    }

    final responseFormat = options.responseFormat;
    if (responseFormat is ResponseFormatJson &&
        responseFormat.schema != null &&
        !config.supportsStructuredOutputs) {
      // warning 只在「带 schema 却不支持结构化输出」时追加;下方 wire 值的
      // json_object 退化路径与该 warning 相互独立(对齐 raw ~237-248)。
      warnings.add(const UnsupportedWarning(
        'responseFormat',
        details:
            'JSON response format schema is only supported with structuredOutputs',
      ));
    }

    final strictJsonSchema = compatibleOptions.strictJsonSchema ?? true;
    final Object? responseFormatWire = switch (responseFormat) {
      null || ResponseFormatText() => null,
      ResponseFormatJson(:final schema, :final name, :final description) =>
        (config.supportsStructuredOutputs && schema != null)
            ? {
                'type': 'json_schema',
                'json_schema': {
                  'schema': schema.value,
                  'strict': strictJsonSchema,
                  'name': name ?? 'response',
                  if (description != null) 'description': description,
                },
              }
            : {'type': 'json_object'},
    };

    final messagesResult = convertToOpenAiCompatibleChatMessages(
      prompt: options.prompt,
      providerOptionsName: config.providerName,
    );
    warnings.addAll(messagesResult.warnings);

    final toolsResult = prepareOpenAiCompatibleTools(
      tools: options.tools,
      toolChoice: options.toolChoice,
    );
    warnings.addAll(toolsResult.warnings);

    // 标准字段(无推理模型裁剪表——本包一律透传,与 pigcode_ai_openai chat 的
    // 最大差异面,见 spec 对照表)。null 只在这个子 map 上清理——JS 侧
    // `undefined` 字段在 `JSON.stringify` 时天然被跳过,这里用 removeWhere
    // 模拟同一效果,且**只清理标准字段**,不牵连下方透传键的显式 null
    // (Fix 3:透传键的 null 语义与标准字段的「未设置」不同,见下)。
    final standardFields = <String, Object?>{
      'model': modelId,
      'user': compatibleOptions.user,
      'max_tokens': options.maxOutputTokens,
      'temperature': options.temperature,
      'top_p': options.topP,
      'frequency_penalty': options.frequencyPenalty,
      'presence_penalty': options.presencePenalty,
      'response_format': responseFormatWire,
      'stop': options.stopSequences,
      'seed': options.seed,
    }..removeWhere((_, value) => value == null);

    final args = <String, Object?>{...standardFields};

    // 未知 providerOptions 键透传:整体覆盖式合并(Map.addAll 语义对齐
    // JS 展开的「后写覆盖前写」),展开位置对齐 raw ~296-307——发生在标准
    // 字段之后、reasoning_effort/verbosity/messages/tools 之前,即透传键
    // 可覆盖标准字段,但会被下方 reasoning_effort/verbosity/messages/
    // tools/tool_choice 的覆盖赋值反过来覆盖掉。
    //
    // Fix 3:透传键的显式 null 必须原样保留,不能被后续 removeWhere 误删
    // ——raw 对 providerOptions 展开值是 JS 对象展开,`{'logit_bias': null}`
    // 这类显式 null 会被 `JSON.stringify` 序列化为 wire `"logit_bias":
    // null`(用于覆盖代理端默认值),与「标准字段未设置故不发送该键」是两种
    // 不同语义,不可混为一谈。故此处不再对整个 `args` 统一 removeWhere,
    // 只有标准字段子 map(上方)与下方 reasoning_effort/verbosity 的写入
    // 才做「null 则不写入该键」处理。
    args.addAll(extractPassthroughProviderOptions(
      options.providerOptions,
      providerOptionsName: config.providerName,
    ));

    // ReasoningEffort.providerDefault/none 均按「未设置」处理,不发送该
    // 字段——对齐 raw ~309-313 `isCustomReasoning(reasoning) && reasoning
    // !== 'none'` 的排除范围(providerDefault 不是合法 wire 值;none 被
    // 显式排除),并对照 pigcode_ai_openai chat 既定模式处理 providerDefault
    // 哨兵的方式。
    final reasoning = options.reasoning;
    final resolvedReasoningEffort = compatibleOptions.reasoningEffort ??
        ((reasoning == null ||
                reasoning == ReasoningEffort.providerDefault ||
                reasoning == ReasoningEffort.none)
            ? null
            : reasoning.wireValue);

    // reasoning_effort/verbosity/tools/tool_choice 仅在非 null 时写入
    // （而非写入 null 再统一 removeWhere——写入 null 会覆盖同名透传键的
    // 显式 null,语义有别于「未设置」)。messages 恒为数组(可能为空),
    // 无此顾虑,直接写入。
    if (resolvedReasoningEffort != null) {
      args['reasoning_effort'] = resolvedReasoningEffort;
    }
    if (compatibleOptions.textVerbosity != null) {
      args['verbosity'] = compatibleOptions.textVerbosity;
    }
    args['messages'] = messagesResult.messages;
    if (toolsResult.tools != null) {
      args['tools'] = toolsResult.tools;
    }
    if (toolsResult.toolChoice != null) {
      args['tool_choice'] = toolsResult.toolChoice;
    }

    return (args: args, warnings: warnings);
  }

  Uri get _requestUrl => config.url('/chat/completions');

  JsonObject _applyTransform(JsonObject body) =>
      config.transformRequestBody?.call(body) ?? body;

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options);
    final body = _applyTransform(built.args);

    // `jsonResponseHandler` 只产出解码后的业务值,响应头需要在 `decode`
    // 之外单独从 `ResponseContext` 捕获——用局部可变变量在 `successHandler`
    // 闭包内旁路写入,`postJsonToApi` 保证 `successHandler` 在返回前已
    // 完整执行完毕,不存在竞态(与 pigcode_ai_openai chat 同款处理)。
    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: _failedResponseHandler,
      client: config.client,
      cancellation: options.cancellation,
    );

    final providerOptionsName = config.providerName;

    // raw 对 `choices[0]` 是无条件下标访问(zod schema 在 `choices` 缺失时
    // 已先校验失败);本包宽松 schema 策略下无该前置校验,`choices` 缺失或
    // 为空视为「顶层结构不符合 chat completions 响应形状」,抛显式契约错误
    // (计划推荐取舍:显式 InvalidResponseDataError 优于裸露的
    // StateError/TypeError 运行时异常,便于下游按类型捕获)。
    final choices = response['choices'] as List<Object?>?;
    if (choices == null || choices.isEmpty) {
      throw InvalidResponseDataError(
        data: response,
        message: 'Expected at least one choice in the response',
      );
    }
    final choice = choices.first! as JsonObject;
    final message = choice['message']! as JsonObject;

    final content = <LanguageModelContent>[];

    final text = message['content'] as String?;
    if (text != null && text.isNotEmpty) {
      content.add(TextContent(text));
    } else {
      // raw compatible 未处理 refusal 字段(`raw/compatible__openai-
      // compatible-chat-language-model.ts` 无匹配)——这是相对 raw 的**超
      // 上游主动扩展**,对照 `pigcode_ai_openai` chat 的既有实现
      // (`packages/openai/lib/src/chat/chat_language_model.dart`
      // ~309-323 行)移植:兼容端点在安全拒绝场景下 `message.content` 为
      // null、拒绝文本改放 `message.refusal`。契约无专门 refusal 类型,
      // 对调用方而言这仍是模型的文本回复,故映射为 TextContent 并在
      // providerMetadata 标记来源,避免语义丢失。
      final refusal = message['refusal'] as String?;
      if (refusal != null && refusal.isNotEmpty) {
        content.add(TextContent(
          refusal,
          providerMetadata: {
            providerOptionsName: {'refusal': true},
          },
        ));
      }
    }

    // reasoning 双读:多数 openai-compatible provider 用
    // `reasoning_content`,部分(如服务 gpt-oss 的厂商)用 `reasoning`
    // (raw ~364-365 行注释 "See #7866")。
    final reasoning =
        (message['reasoning_content'] ?? message['reasoning']) as String?;
    if (reasoning != null && reasoning.isNotEmpty) {
      content.add(ReasoningContent(reasoning));
    }

    final toolCalls = message['tool_calls'] as List<Object?>?;
    if (toolCalls != null) {
      for (final raw in toolCalls) {
        final toolCall = raw! as JsonObject;
        final function = toolCall['function']! as JsonObject;
        // Google Gemini thought signature 回读(经 OpenAI 兼容层暴露的
        // `extra_content.google.thought_signature`):非空时写进该 ToolCall
        // 自身的 providerMetadata,逐字对照 raw ~376-389 行。`isNotEmpty`
        // 对齐 raw 的 JS truthiness(`thoughtSignature ? ... : {}`)——空串
        // 在 JS 中为 falsy,应视同「未提供」而跳过,不是「非 null 即有效」
        // (Fix 4)。
        final thoughtSignature =
            ((toolCall['extra_content'] as JsonObject?)?['google']
                as JsonObject?)?['thought_signature'] as String?;
        content.add(ToolCall(
          toolCallId: (toolCall['id'] as String?) ?? generateId(),
          toolName: function['name']! as String,
          input: function['arguments']! as String,
          providerMetadata: thoughtSignature != null &&
                  thoughtSignature.isNotEmpty
              ? {
                  providerOptionsName: {'thoughtSignature': thoughtSignature},
                }
              : null,
        ));
      }
    }
    // 注(相对 raw 的既定偏离,计划裁决):本包不声明/不回读 annotations、
    // logprobs(spec 对照表——宽松 schema 策略的一部分)。

    // provider metadata:恒带一个空壳 {providerOptionsName: {}}(与 raw
    // ~395 一致,保证 providerMetadata 至少有该 key 存在),
    // metadataExtractor 的结果覆盖式合并在其后(raw ~397-399:展开语义,
    // extractor 返回的 key 若与空壳同名会整体覆盖)。
    final extracted = await config.metadataExtractor?.extractMetadata(response);
    final providerMetadata = <String, JsonObject>{
      providerOptionsName: const <String, Object?>{},
      ...?extracted,
    };
    // accepted/rejected prediction tokens 回读:逐字对照 raw ~401-410 行。
    // raw 的写入方式是对已合并出的 `providerMetadata[metadataKey]` 做属性
    // 赋值(原地追加),而不是重新整体覆盖该子对象——即便 metadataExtractor
    // 也写了 providerOptionsName 键,这两个字段仍会叠加在其结果之上。
    // Dart 侧用「取出已有子 map、追加新键、整体替换回同一个键」的方式复现
    // 同一叠加语义。
    final completionTokenDetails = (response['usage']
        as JsonObject?)?['completion_tokens_details'] as JsonObject?;
    final acceptedPredictionTokens =
        completionTokenDetails?['accepted_prediction_tokens'];
    final rejectedPredictionTokens =
        completionTokenDetails?['rejected_prediction_tokens'];
    if (acceptedPredictionTokens != null || rejectedPredictionTokens != null) {
      providerMetadata[providerOptionsName] = {
        ...providerMetadata[providerOptionsName]!,
        if (acceptedPredictionTokens != null)
          'acceptedPredictionTokens': acceptedPredictionTokens,
        if (rejectedPredictionTokens != null)
          'rejectedPredictionTokens': rejectedPredictionTokens,
      };
    }

    final finishReason =
        mapOpenAiCompatibleFinishReason(choice['finish_reason'] as String?);

    // usage 为 null 时不调用 config.convertUsage(其契约签名接收非空
    // JsonObject,不把 null 兜底成假 `{}` 传给用户函数),直接落到默认
    // 转换函数的 null 分支;非空时才允许 convertUsage 覆盖默认行为。
    final usage = response['usage'] as JsonObject?;
    final convertedUsage = usage != null
        ? (config.convertUsage?.call(usage) ??
            convertOpenAiCompatibleChatUsage(usage))
        : convertOpenAiCompatibleChatUsage(null);

    final metadata = getOpenAiCompatibleResponseMetadata(response);

    return LanguageModelGenerateResult(
      content: content,
      finishReason: finishReason,
      usage: convertedUsage,
      warnings: built.warnings,
      providerMetadata: providerMetadata,
      request: RequestInfo(body: body),
      response: ResponseInfo(
        id: metadata.id,
        timestamp: metadata.timestamp,
        modelId: metadata.modelId,
        headers: responseHeaders,
        body: response,
      ),
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options);
    // `stream_options` 只在 `includeUsage == true` 时出现该键(条件展开进
    // Map 字面量,而非三元 + null 值再删除——`streamArgs` 在 `_buildArgs`
    // 结果之上二次构造,不会再走一次 `removeWhere`)。对齐 raw doStream
    // ~437-445 的请求体形状。
    final streamArgs = <String, Object?>{
      ...built.args,
      'stream': true,
      if (config.includeUsage) 'stream_options': {'include_usage': true},
    };
    final body = _applyTransform(streamArgs);

    // 每次 doStream 调用各自新建独立的流级提取器,不跨调用共享状态。
    final streamExtractor = config.metadataExtractor?.createStreamExtractor();

    // 响应头捕获:与 doGenerate 同款旁路写入模式。
    Map<String, String>? responseHeaders;
    final rawEvents = await postJsonStreamToApi<JsonValue>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return eventSourceResponseHandler<JsonValue>(
          decode: (json) => json,
        )(ctx);
      },
      failureHandler: _failedResponseHandler,
      client: config.client,
      cancellation: options.cancellation,
    );

    // 与 pigcode_ai_openai chat 的主动差异(计划裁决,显式声明):本包**没有**
    // `throwIfStreamErrorBeforeOutput` 式 pre-output probe——错误处理是
    // 单一流内路径:错误帧(无论到达时机是否在首个输出 chunk 之前)一律在
    // 流状态机内转成 ErrorPart 终态事件,本方法返回的 Future 不会因输出前
    // 错误帧而 throw ApiCallError。理由:raw compatible 包本就没有 probe
    // 机制,error-as-terminal-event 语义在无 probe 时天然自洽,不额外引入。
    final stream = _toStreamParts(
      rawEvents,
      warnings: built.warnings,
      includeRawChunks: options.includeRawChunks ?? false,
      providerOptionsName: config.providerName,
      streamExtractor: streamExtractor,
    );

    return LanguageModelStreamResult(
      stream: stream,
      request: RequestInfo(body: body),
      response: ResponseInfo(headers: responseHeaders),
    );
  }

  /// 把 SSE 解析结果流转换为契约流事件(doStream 的流状态机)。
  ///
  /// wire 语义逐字对照 raw doStream 的 `TransformStream`
  /// (`raw/compatible__openai-compatible-chat-language-model.ts`
  /// ~540-730 行);与 raw 的既定偏离均在对应分支注释声明。
  Stream<LanguageModelStreamPart> _toStreamParts(
    Stream<ParseResult<JsonValue>> events, {
    required List<Warning> warnings,
    required bool includeRawChunks,
    required String providerOptionsName,
    required StreamMetadataExtractor? streamExtractor,
  }) async* {
    yield StreamStart(warnings);

    final tracker = StreamingToolCallTracker();
    final pendingToolCalls = <int, _PendingToolCall>{};
    // index → 该 index 已转发调用的最终 id;双重职责——既是「该 index 是否已
    // 转发过」的判定(containsKey),也是续片(缺 id 但带 index)据以归桶
    // thought signature 的原始 id 来源(见下方直通路径分流注释)。
    final forwardedToolCallIds = <int, String>{};
    // Google Gemini thought signature 按工具调用 id 索引的暂存表:
    // 见 [_captureToolCallThoughtSignature] 文档。
    final toolCallThoughtSignatures = <String, String>{};

    var finishReason = const LanguageModelFinishReason(FinishReasonType.other);
    JsonObject? usage;
    var isFirstChunk = true;
    var isActiveReasoning = false;
    var isActiveText = false;
    // 本次文本流是否最终由 refusal 分支驱动(即 effectiveDelta 取自
    // refusalDelta 而非 textDelta)。收尾 TextEnd 据此条件性带上
    // providerMetadata 标记,与非流式 doGenerate 的 refusal 标记对称——超
    // 上游扩展,移植自 `pigcode_ai_openai` chat 的既有实现(见
    // `packages/openai/lib/src/chat/chat_language_model.dart` ~493-497/
    // 653-661 行)。
    var isRefusalText = false;

    // usage 为 null 时不调用 config.convertUsage(其契约签名接收非空
    // JsonObject,不把 null 兜底成假 `{}` 传给用户函数),与 doGenerate 的
    // 既定语义一致(计划交接风险点注记认可的桥接方式)。
    LanguageModelUsage convertUsage(JsonObject? value) => value != null
        ? (config.convertUsage?.call(value) ??
            convertOpenAiCompatibleChatUsage(value))
        : convertOpenAiCompatibleChatUsage(null);

    try {
      await for (final event in events) {
        if (includeRawChunks) {
          yield RawPart(switch (event) {
            ParseSuccess<JsonValue>(:final rawValue) => rawValue,
            ParseFailure<JsonValue>(:final rawValue) => rawValue,
          });
        }

        if (event is ParseFailure<JsonValue>) {
          // 帧级解析失败:ErrorPart 即终态,不再补发收尾事件——与 wire
          // 错误信封同一 error-as-terminal-event 语义。
          yield ErrorPart(event.error);
          return;
        }

        final rawValue = (event as ParseSuccess<JsonValue>).value;

        // metadataExtractor 对每个成功解析的 chunk 调用一次,顺序在错误帧
        // 判定之前(对齐 raw ~578:先 processChunk 再判 error)。
        streamExtractor?.processChunk(rawValue);

        // 错误帧检测:走可插拔 errorStructure 的 validator,而非硬编码
        // `value['error'] != null`(errorStructure 可自定义错误体形状,
        // 必须经 validator 才能正确识别;相对 raw `'error' in chunk.value`
        // 的主动泛化,计划裁决)。命中即 ErrorPart 终态,不再补发
        // TextEnd/FinishPart——与 pigcode_ai_openai chat 一致的终态语义;
        // finishReason 赋值仅为对齐 raw 的内部记录,实际不会再被读取。
        final errorValidation = _errorStructure.validator.validate(rawValue);
        if (errorValidation is ValidationSuccess) {
          finishReason =
              const LanguageModelFinishReason(FinishReasonType.error);
          yield ErrorPart(
            _errorStructure.errorToMessage(errorValidation.value),
          );
          return;
        }

        if (rawValue is! JsonObject) {
          // 非对象顶层值(理论上不应出现,wire 协议保证 chunk 恒为对象):
          // 跳过本帧,不中断流——防御性分支,当前不可达。
          continue;
        }
        final value = rawValue;

        // 响应元数据仅按 chunk 序号触发,不检查内容:第一个成功解析的
        // chunk 到达即无条件产出一次(即使 id/model/created 全空)——与
        // pigcode_ai_openai chat「任一字段非空才产出」不同,对齐 raw ~594-601。
        if (isFirstChunk) {
          isFirstChunk = false;
          final metadata = getOpenAiCompatibleResponseMetadata(value);
          yield ResponseMetadata(
            id: metadata.id,
            timestamp: metadata.timestamp,
            modelId: metadata.modelId,
          );
        }

        // usage 覆盖式写入(每次覆盖为最新值,不累积合并字段;通常只有
        // 收尾帧携带完整 usage)。
        final usageValue = value['usage'] as JsonObject?;
        if (usageValue != null) {
          usage = usageValue;
        }

        final choices = value['choices'] as List<Object?>? ?? const [];
        final choice = choices.isNotEmpty ? choices.first as JsonObject? : null;

        final rawFinishReason = choice?['finish_reason'] as String?;
        if (rawFinishReason != null) {
          finishReason = mapOpenAiCompatibleFinishReason(rawFinishReason);
        }

        final delta = choice?['delta'] as JsonObject?;
        if (delta == null) {
          continue;
        }
        // delta.role 可能为空字符串(raw zod schema `z.enum(['assistant',
        // ''])` 声明的方言容忍):本状态机根本不读取该字段(只关心
        // content/reasoning_content/reasoning/tool_calls/finish_reason/
        // usage),空串是「天然容忍」而非主动处理——此处没有读取 role 的
        // 代码不是遗漏。

        // 推理 delta 先于文本 delta 入队(对齐 raw ~622-660 顺序);
        // `reasoning_content` 与 `reasoning` 双读同 doGenerate。
        final reasoningContent =
            (delta['reasoning_content'] ?? delta['reasoning']) as String?;
        if (reasoningContent != null && reasoningContent.isNotEmpty) {
          if (!isActiveReasoning) {
            yield const ReasoningStart('reasoning-0');
            isActiveReasoning = true;
          }
          yield ReasoningDelta('reasoning-0', reasoningContent);
        }

        // raw compatible 未处理 refusal delta(`raw/compatible__openai-
        // compatible-chat-language-model.ts` 无匹配)——超上游扩展,移植自
        // `pigcode_ai_openai` chat 的既有实现(`chat_language_model.dart`
        // ~585-604 行)。官方 Chat Completions API:流式拒绝回复通过
        // `delta.refusal` 逐字增量下发,与 `delta.content` 互斥(同一时刻
        // 只会出现其一)。两者复用同一惰性 text-start/text-delta 逻辑与块
        // id `'txt-0'`;若同一帧异常地同时给出两者,按 content 优先——
        // content 是正常回复的权威字段,content 非空即说明这不是纯拒绝帧。
        final textDelta = delta['content'] as String?;
        final refusalDelta = delta['refusal'] as String?;
        final usingRefusal = textDelta == null || textDelta.isEmpty;
        final effectiveDelta = usingRefusal ? refusalDelta : textDelta;
        if (effectiveDelta != null && effectiveDelta.isNotEmpty) {
          // 文本开始前先关闭活跃的推理块(raw ~640-648)。
          if (isActiveReasoning) {
            yield const ReasoningEnd('reasoning-0');
            isActiveReasoning = false;
          }
          if (!isActiveText) {
            yield const TextStart('txt-0');
            isActiveText = true;
          }
          if (usingRefusal) {
            isRefusalText = true;
          }
          yield TextDelta('txt-0', effectiveDelta);
        }

        final toolCallDeltas = delta['tool_calls'] as List<Object?>?;
        if (toolCallDeltas != null) {
          // 工具调用开始前同样先关闭活跃的推理块(raw ~662-670)。
          if (isActiveReasoning) {
            yield const ReasoningEnd('reasoning-0');
            isActiveReasoning = false;
          }
          for (final raw in toolCallDeltas) {
            final events = _processToolCallDelta(
              raw! as JsonObject,
              pendingToolCalls,
              forwardedToolCallIds,
              tracker,
              toolCallThoughtSignatures,
            );
            for (final part in _attachToolCallThoughtSignatures(
              events,
              toolCallThoughtSignatures,
              providerOptionsName,
            )) {
              yield part;
            }
          }
        }
      }
    } catch (error) {
      // 连接级 Stream error(SSE 中途断连等):与帧级错误同一终态处理,
      // 职责切分同 pigcode_ai_openai chat(`eventSourceResponseHandler` 把
      // 连接失败作为 Stream.error 转发,由本层捕获转 ErrorPart)。
      yield ErrorPart(error);
      return;
    }

    if (isActiveReasoning) {
      yield const ReasoningEnd('reasoning-0');
    }
    if (isActiveText) {
      yield TextEnd(
        'txt-0',
        providerMetadata: isRefusalText
            ? {
                providerOptionsName: {'refusal': true},
              }
            : null,
      );
    }

    // flush:强制转发所有仍缺 name 的挂起工具调用,让 tracker 按其自身的
    // `name == null` 校验抛出 InvalidResponseDataError,保留「响应数据不
    // 符合预期」的原始语义(对齐 raw flush ~690-697)。
    //
    // 关于异常传播的实现选择(计划要求保留本注释,供下游读者理解为何这里
    // 的错误路径与主循环不同):本循环故意放在 `try { await for } catch`
    // 块**之外**——Dart `async*` 生成器函数体中,`try/catch` 只覆盖其词法
    // 范围内的异常;flush 发生在主循环正常耗尽之后的收尾段,若也塞进同一个
    // `try` 块,tracker 抛出的 InvalidResponseDataError 会被 catch 捕获并
    // 温柔地包装成普通终态 ErrorPart 数据,与 raw 语义(该异常是「响应流
    // 不合法」的强错误,理应让 Stream 本身以 error 事件结束)存在分歧。
    // 故此处不捕获:异常穿透 async* 函数体,按 Dart 的「生成器体内未捕获
    // 异常 → 转为 Stream.error」语义传给消费者。
    for (final entry in pendingToolCalls.entries) {
      tracker.addDelta(
        index: entry.key,
        id: entry.value.id,
        argumentsDelta: entry.value.arguments,
      );
    }
    pendingToolCalls.clear();

    // 对齐 raw flush ~699 的 `toolCallTracker.flush()`:对所有已转发但
    // 尚未定稿的调用(如 arguments 恒为空的无参工具,「可解析即定稿」探测
    // 永不触发)补发 ToolInputEnd + ToolCall。计划的 doStream 参考代码
    // 遗漏了这一步,此处按 raw 语义补齐(主动偏离计划代码、对齐 raw)。
    for (final part in _attachToolCallThoughtSignatures(
      tracker.finishAll(),
      toolCallThoughtSignatures,
      providerOptionsName,
    )) {
      yield part;
    }

    // providerMetadata 合并方向与 doGenerate 完全一致:空壳
    // {providerOptionsName: {}} 打底,streamExtractor.buildMetadata() 的
    // 返回值覆盖式合并在其后(展开语义)。accepted/rejected prediction
    // tokens 的叠加时机与 doGenerate 对齐(raw flush ~705-718 行同一
    // 「先展开 extractor,再原地追加」语义):在 streamExtractor 结果合并
    // 之后,把这两个字段追加进同一个 providerOptionsName 子对象。
    final providerMetadata = <String, JsonObject>{
      providerOptionsName: const <String, Object?>{},
      ...?streamExtractor?.buildMetadata(),
    };
    final completionTokenDetails =
        usage?['completion_tokens_details'] as JsonObject?;
    final acceptedPredictionTokens =
        completionTokenDetails?['accepted_prediction_tokens'];
    final rejectedPredictionTokens =
        completionTokenDetails?['rejected_prediction_tokens'];
    if (acceptedPredictionTokens != null || rejectedPredictionTokens != null) {
      providerMetadata[providerOptionsName] = {
        ...providerMetadata[providerOptionsName]!,
        if (acceptedPredictionTokens != null)
          'acceptedPredictionTokens': acceptedPredictionTokens,
        if (rejectedPredictionTokens != null)
          'rejectedPredictionTokens': rejectedPredictionTokens,
      };
    }

    yield FinishPart(
      usage: convertUsage(usage),
      finishReason: finishReason,
      providerMetadata: providerMetadata,
    );
  }
}

/// 处理单个 `delta.tool_calls` 数组元素,返回应立即转发的契约流事件。
///
/// [forwardedToolCallIds] 身兼双职:
/// 1. 「该 index 是否已转发过」的判定(`containsKey`)——决定走续片直通
///    路径还是新调用路径(含缓冲)。
/// 2. 续片据以归桶 thought signature 的原始 id 来源——续片可能缺 id,
///    绝不能为其合成新 id(见下方「续片直通」分支注释,Fix 1)。
///
/// 对照 raw `processToolCallDelta`(~475-522):
/// - 该 index 已转发过(续片):直通给 [tracker],统一使用
///   `forwardedToolCallIds[index]`(转发时敲定的原始 id),不合成新 id
///   ——tracker 的 `_continueCall` 分支本就忽略传入 id、只认原始 id,
///   若此处为缺 id 的续片合成一个新 id,thought signature 会按这个新 id
///   归桶,而最终 [ToolCall] 仍以原始 id 发出,两者对不上导致签名丢失
///   (Fix 1 修复的问题)。
/// - `index` 缺失(注释对照 raw "google does not send index"):跳过
///   缓冲,直接转发给 [tracker],依赖其 `_nextIndex` 顺序计数/「继续已有
///   调用」分支兜底——与上游 tracker 的 `index ?? this.toolCalls.length`
///   (`streaming-tool-call-tracker.ts` ~109)语义等价。该语义支持的是
///   google 式「无 index、单片完整调用」形态;**连续多片都缺 index(参数
///   拆片)时第二片会被当成新调用**,上游同样如此(第二片在其 tracker
///   ~147-155 撞缺 id/name 抛错),不是本包走样。**若某 provider 既不发
///   index 又不在首片给 name,本包不提供缓冲保护**,这是 raw 的明确设计
///   取舍(`Map<number, PendingToolCall>` 无法用 null 作 key),不是遗漏。
///   此路径下 `id` 缺失时用 `generateId()` 合成兜底:**主动偏离上游流式
///   行为**——上游 tracker 对新调用的 null id 直接抛
///   `Expected 'id' to be a string.`(~147-152),但其 chunk schema 声明
///   `id: z.string().nullish()`(~814)、构造时注入 `generateId` 选项、
///   非流式 doGenerate 又做 `?? generateId()` 兜底(raw ~380),四处
///   自相矛盾(schema 与注入暗示可空,实际路径抛错)。按「不照抄疑似
///   bug」先例与本包宽松容错定位,流式与非流式对称合成;合成 id 只在
///   「新调用」路径产生,不影响续片直通路径的原始 id 归桶。
/// - 首次拿到 `name` 时把缓冲的 id + 累积 arguments 一次性喂给 tracker:
///   沙盒验证确认 Dart 版 [StreamingToolCallTracker.addDelta] 是「整片
///   一把喂」语义(与 raw `processDelta` 的多次流式调用不同),一次调用
///   即可让 tracker 完成 start + delta(+ 可能的提前 finish)全套事件
///   产出,不需要模拟 raw 那种「先发不带 arguments 的 name 片、再补
///   arguments 片」的两阶段转发——这是本函数与 raw 分叉的唯一结构性原因。
///   转发后登记 `forwardedToolCallIds[index] = pending.id!`,供后续续片
///   查表归桶签名。
///
/// Google Gemini thought signature 回读(逐字对照 raw `extractMetadata`/
/// `buildToolCallProviderMetadata`,~551-559 行):pigcode 的
/// [StreamingToolCallTracker] 没有 raw 共享 tracker 那层「按 delta 提取
/// 元数据、随 [ToolCall] 一并产出」的钩子(该类型定义在 provider_utils
/// 包,本次任务范围不含跨包改动),故在本函数就地捕获每个 index/id 对应的
/// thought signature 并写入 [toolCallThoughtSignatures](按 id 索引,因为
/// tracker 产出的 [ToolCall] 只带 id 不带 index),再由调用方
/// (`_toStreamParts`)在收到 [ToolCall] 事件时据此重建出带 providerMetadata
/// 的版本。
void _captureToolCallThoughtSignature(
  JsonObject toolCallDelta,
  String? id,
  Map<String, String> toolCallThoughtSignatures,
) {
  // isNotEmpty 对齐 raw 的 JS truthiness(空串视同未提供,Fix 4)。
  final thoughtSignature =
      ((toolCallDelta['extra_content'] as JsonObject?)?['google']
          as JsonObject?)?['thought_signature'] as String?;
  if (thoughtSignature != null && thoughtSignature.isNotEmpty && id != null) {
    toolCallThoughtSignatures.putIfAbsent(id, () => thoughtSignature);
  }
}

/// 把 [events] 中的 [ToolCall] 事件按 `toolCallId` 查表重建出带
/// `providerMetadata` 的版本(其余事件原样透传);无对应 thought signature
/// 的 [ToolCall] 保持不变。
///
/// [StreamingToolCallTracker] 产出的 [ToolCall] 本身不带
/// providerMetadata(见其源码 `_finishCall`),这里在 provider 层重建一份
/// 新实例补上——[ToolCall] 各字段均为 `final`,无 `copyWith`,故显式列出
/// 全部字段构造新实例。
List<LanguageModelStreamPart> _attachToolCallThoughtSignatures(
  List<LanguageModelStreamPart> events,
  Map<String, String> toolCallThoughtSignatures,
  String providerOptionsName,
) {
  if (toolCallThoughtSignatures.isEmpty) {
    return events;
  }
  return [
    for (final event in events)
      if (event is ToolCall &&
          toolCallThoughtSignatures.containsKey(event.toolCallId))
        ToolCall(
          toolCallId: event.toolCallId,
          toolName: event.toolName,
          input: event.input,
          providerExecuted: event.providerExecuted,
          isDynamic: event.isDynamic,
          providerMetadata: {
            providerOptionsName: {
              'thoughtSignature': toolCallThoughtSignatures[event.toolCallId],
            },
          },
        )
      else
        event,
  ];
}

List<LanguageModelStreamPart> _processToolCallDelta(
  JsonObject toolCallDelta,
  Map<int, _PendingToolCall> pendingToolCalls,
  Map<int, String> forwardedToolCallIds,
  StreamingToolCallTracker tracker,
  Map<String, String> toolCallThoughtSignatures,
) {
  final index = (toolCallDelta['index'] as num?)?.toInt();
  final id = toolCallDelta['id'] as String?;
  final function = toolCallDelta['function'] as JsonObject?;
  final name = function?['name'] as String?;
  final argumentsDelta = function?['arguments'] as String?;

  if (index != null && forwardedToolCallIds.containsKey(index)) {
    // 续片(该 index 已转发过):tracker 的 `_continueCall` 分支忽略传入的
    // id、只认该调用首次转发时敲定的原始 id——续片本身可能缺 id(只带
    // index + 增量 arguments/thought_signature),此时绝不能用 `id ??
    // generateId()` 合成一个新 id 喂给 tracker:tracker 会原样忽略它,但
    // thought signature 若按这个合成新 id 归桶,就再也查不到与
    // [ToolCall](按其原始 id 发出)对应的签名(Fix 1 修复的核心问题)。
    // 故此处签名捕获与 tracker.addDelta 都统一使用
    // `forwardedToolCallIds[index]`(原始 id),不合成新 id。
    final originalId = forwardedToolCallIds[index]!;
    _captureToolCallThoughtSignature(
      toolCallDelta,
      originalId,
      toolCallThoughtSignatures,
    );
    return tracker.addDelta(
      index: index,
      id: originalId,
      name: name,
      argumentsDelta: argumentsDelta,
    );
  }

  if (index == null) {
    // index 缺失(注释对照 raw "google does not send index"):跳过缓冲,
    // 直接转发给 tracker,依赖其 `_nextIndex` 顺序计数/「继续已有调用」
    // 分支兜底——这是「新调用」而非「续片」,故仍需 id 兜底合成。
    //
    // id 兜底:tracker 对「新调用」的 null id 会抛 InvalidResponseDataError
    // （对齐 raw chunk schema `id: z.string().nullish()` 与非流式 doGenerate
    // 的 `?? generateId()` 兜底,~L303)。
    //
    // 先定稿再两用:合成 id 必须在捕获 thought signature 之前敲定,且捕获
    // 与 tracker.addDelta 用同一个值,避免两者用到不同的合成 id 导致签名
    // 归错桶(与续片分支同一防御逻辑,但此处 index 恒为 null,无处登记
    // forwardedToolCallIds)。
    final resolvedId = id ?? generateId();
    _captureToolCallThoughtSignature(
      toolCallDelta,
      resolvedId,
      toolCallThoughtSignatures,
    );
    return tracker.addDelta(
      index: null,
      id: resolvedId,
      name: name,
      argumentsDelta: argumentsDelta,
    );
  }

  final pending = pendingToolCalls.putIfAbsent(
    index,
    () => _PendingToolCall(id: id),
  );
  pending.id ??= id;
  final thoughtSignature =
      ((toolCallDelta['extra_content'] as JsonObject?)?['google']
          as JsonObject?)?['thought_signature'] as String?;
  // isNotEmpty 对齐 raw 的 JS truthiness(空串视同未提供),与
  // [_captureToolCallThoughtSignature]/非流式路径同一语义——此前空串会
  // 经 `??=` 占位并最终进 ToolCall.providerMetadata,跨轮重放时发出空
  // `thought_signature` 而非省略;顺带空串不再占位,后到的非空签名仍可
  // 写入。
  if (thoughtSignature != null && thoughtSignature.isNotEmpty) {
    pending.thoughtSignature ??= thoughtSignature;
  }
  if (argumentsDelta != null) {
    pending.arguments += argumentsDelta;
  }

  if (name == null) {
    // 仍未拿到 name:继续缓冲,不产出任何事件。
    return const <LanguageModelStreamPart>[];
  }

  // id 兜底:缓冲期间自始至终未收到 id 时在此合成,先落回 pending.id 再喂给
  // tracker,确保下方 thoughtSignature 按 id 索引与实际转发给 tracker 的 id
  // 保持同一个值(对齐 raw chunk schema `id: z.string().nullish()` 与非流式
  // doGenerate 的 `?? generateId()` 兜底)。
  pending.id ??= generateId();

  if (pending.thoughtSignature != null) {
    toolCallThoughtSignatures.putIfAbsent(
      pending.id!,
      () => pending.thoughtSignature!,
    );
  }

  final events = tracker.addDelta(
    index: index,
    id: pending.id,
    name: name,
    argumentsDelta: pending.arguments,
  );
  pendingToolCalls.remove(index);
  // 登记该 index 已转发,并记住最终 id——后续续片据此归桶 thought
  // signature(Fix 1),不再各自合成新 id。
  forwardedToolCallIds[index] = pending.id!;
  return events;
}

/// 单个工具调用分片在等待 `function.name` 到达前的缓冲状态。
///
/// 逐字对齐 raw `PendingToolCall`(`raw/compatible__openai-compatible-
/// chat-language-model.ts` ~96-100 行);部分 openai-compatible provider
/// 的首个 tool-call delta 不带 `function.name`(该字段被
/// [StreamingToolCallTracker] 要求在新 index 首次出现时必须非空),故在
/// 喂给 tracker 前先在本层缓冲,直到某一片带上 name 才一次性转发。
final class _PendingToolCall {
  _PendingToolCall({this.id});

  /// 已知的调用 id(可能在带 name 的那一片之前就已出现)。
  String? id;

  /// 已知的 Google Gemini thought signature(`extra_content.google.
  /// thought_signature`);一旦捕获到非空值就不再被后续分片覆盖——逐字对齐
  /// raw `pending.extraContent == null && toolCallDelta.extra_content !=
  /// null` 的「只在缺失时补上」合并策略(~496-501 行)。
  String? thoughtSignature;

  /// 累积的 arguments 增量(等到 name 出现时整体作为一次 `addDelta`
  /// 调用的 `argumentsDelta` 参数喂入)。缓冲期恒从空串开始拼接,故不
  /// 提供构造参数(raw 的 `bufferedArguments: ''` 初始化同义)。
  String arguments = '';
}
