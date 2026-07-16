import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/capabilities.dart';
import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import '../internal/stream_error_probe.dart';
import 'chat_options.dart';
import 'convert_messages.dart';
import 'convert_usage.dart';
import 'map_finish_reason.dart';
import 'prepare_tools.dart';
import 'response_metadata.dart';

/// OpenAI Chat Completions(`/chat/completions`)的 [LanguageModel] 实现。
final class OpenAiChatLanguageModel implements LanguageModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 chat 模型实例。
  OpenAiChatLanguageModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => '${config.providerName}.chat';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => {
        'image/*': [RegExp(r'^https?://.*$')],
      };

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/chat/completions');

  /// chat 请求体构造:`doGenerate`/`doStream` 共用,`doStream` 只在此基础上
  /// 追加 `stream`/`stream_options`(见 Task 9)。
  ///
  /// wire 语义逐字对照 v7 `getArgs`(`raw/openai-chat-language-model.ts`)。
  ({JsonObject args, List<Warning> warnings}) _buildArgs(
    LanguageModelCallOptions options,
  ) {
    final warnings = <Warning>[];

    // 与 responses wire 对称:provider options 键按 provider 名派生
    // (azure fallback),而非恒读 'openai' 键——否则同一个
    // `createOpenAi(name: 'azure-x')` 实例下 chat 会静默丢弃
    // `{'azure': {...}}` 键下的选项(见 resolveOpenAiProviderOptions 文档)。
    final openaiOptions = OpenAiChatProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
        config.providerName,
        options.providerOptions,
      ),
    );
    final capabilities = getOpenAiLanguageModelCapabilities(modelId);

    // 契约 [ReasoningEffort.providerDefault] 语义是「显式要求使用服务端
    // 默认值」,不是一个合法的 wire effort 取值(OpenAI 只接受
    // none/minimal/low/medium/high/xhigh)——按「未设置」处理,不发
    // `reasoning_effort` 字段,让服务端使用其默认值。
    final resolvedReasoningEffort = openaiOptions.reasoningEffort ??
        (options.reasoning == ReasoningEffort.providerDefault
            ? null
            : options.reasoning?.wireValue);

    final isReasoningModel =
        openaiOptions.forceReasoning ?? capabilities.isReasoningModel;

    if (options.topK != null) {
      warnings.add(const UnsupportedWarning('topK'));
    }

    final systemMessageMode = openaiOptions.systemMessageMode ??
        (isReasoningModel
            ? SystemMessageMode.developer
            : capabilities.systemMessageMode);

    final messagesResult = convertToOpenAiChatMessages(
      prompt: options.prompt,
      systemMessageMode: systemMessageMode,
      // 与 call 级 options 的 azure 派生(上方 resolveOpenAiProviderOptions)
      // 及 responses 侧文件引用取齐:文件引用按同一派生 key 解析。
      providerOptionsName: resolveOpenAiProviderOptionsName(
        config.providerName,
      ),
    );
    warnings.addAll(messagesResult.warnings);

    final strictJsonSchema = openaiOptions.strictJsonSchema ?? true;

    final responseFormat = options.responseFormat;
    final Object? responseFormatWire = switch (responseFormat) {
      null || ResponseFormatText() => null,
      ResponseFormatJson(:final schema, :final name, :final description) =>
        schema != null
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

    final logprobsOption = openaiOptions.logprobs;
    final args = <String, Object?>{
      'model': modelId,
      'logit_bias': openaiOptions.logitBias,
      'logprobs':
          (logprobsOption == true || logprobsOption is int) ? true : null,
      'top_logprobs': logprobsOption is int
          ? logprobsOption
          : (logprobsOption == true ? 0 : null),
      'user': openaiOptions.user,
      'parallel_tool_calls': openaiOptions.parallelToolCalls,
      'max_tokens': options.maxOutputTokens,
      'temperature': options.temperature,
      'top_p': options.topP,
      'frequency_penalty': options.frequencyPenalty,
      'presence_penalty': options.presencePenalty,
      'response_format': responseFormatWire,
      'stop': options.stopSequences,
      'seed': options.seed,
      'verbosity': openaiOptions.textVerbosity,
      'max_completion_tokens': openaiOptions.maxCompletionTokens,
      'store': openaiOptions.store,
      'metadata': openaiOptions.metadata,
      'prediction': openaiOptions.prediction,
      'reasoning_effort': resolvedReasoningEffort,
      'service_tier': openaiOptions.serviceTier,
      'prompt_cache_key': openaiOptions.promptCacheKey,
      'prompt_cache_retention': openaiOptions.promptCacheRetention,
      'safety_identifier': openaiOptions.safetyIdentifier,
      'messages': messagesResult.messages,
    };

    // 推理模型的参数裁剪(见 https://platform.openai.com/docs/guides/reasoning#limitations)。
    if (isReasoningModel) {
      // reasoningEffort 为 'none' 时,gpt-5.1+ 系列模型仍允许
      // temperature/topP/logprobs(见
      // https://platform.openai.com/docs/guides/latest-model#gpt-5-1-parameter-compatibility)。
      if (resolvedReasoningEffort != 'none' ||
          !capabilities.supportsNonReasoningParameters) {
        if (args['temperature'] != null) {
          args['temperature'] = null;
          warnings.add(const UnsupportedWarning(
            'temperature',
            details: 'temperature is not supported for reasoning models',
          ));
        }
        if (args['top_p'] != null) {
          args['top_p'] = null;
          warnings.add(const UnsupportedWarning(
            'topP',
            details: 'topP is not supported for reasoning models',
          ));
        }
        if (args['logprobs'] != null) {
          args['logprobs'] = null;
          warnings.add(const OtherWarning(
            'logprobs is not supported for reasoning models',
          ));
        }
        // top_logprobs 与 logprobs 同属一组、同受 gpt-5.1 none 豁免——
        // 上游把本删除写在 gate 外(raw ~264-270,gate 是后来引入未同步
        // 挪动),导致 none 模式下 logprobs 保留而配套的 top_logprobs 被
        // 静默删除(top-N 概率请求降级为仅 token logprob)并发误导告警,
        // 与其引用的 gpt-5.1 参数兼容性文档自相矛盾。主动偏离,不照抄
        // 疑似 bug(先例见 convert_messages.dart 的 image data URI 说明)。
        if (args['top_logprobs'] != null) {
          args['top_logprobs'] = null;
          warnings.add(const OtherWarning(
            'topLogprobs is not supported for reasoning models',
          ));
        }
      }
      if (args['frequency_penalty'] != null) {
        args['frequency_penalty'] = null;
        warnings.add(const UnsupportedWarning(
          'frequencyPenalty',
          details: 'frequencyPenalty is not supported for reasoning models',
        ));
      }
      if (args['presence_penalty'] != null) {
        args['presence_penalty'] = null;
        warnings.add(const UnsupportedWarning(
          'presencePenalty',
          details: 'presencePenalty is not supported for reasoning models',
        ));
      }
      if (args['logit_bias'] != null) {
        args['logit_bias'] = null;
        warnings.add(const OtherWarning(
          'logitBias is not supported for reasoning models',
        ));
      }

      if (args['max_tokens'] != null) {
        args['max_completion_tokens'] ??= args['max_tokens'];
        args['max_tokens'] = null;
      }
    } else {
      // 非推理模型:reasoning_effort 对 OpenAI 而言是推理模型专属参数,
      // 无条件透传会导致 400。裁剪逻辑与 warning 文案与 responses 侧
      // `responses_language_model.dart` `_buildArgs` 的对应分支取齐。
      if (args['reasoning_effort'] != null) {
        args['reasoning_effort'] = null;
        warnings.add(const UnsupportedWarning(
          'reasoningEffort',
          details: 'reasoningEffort is not supported for non-reasoning models',
        ));
      }

      if (modelId.startsWith('gpt-4o-search-preview') ||
          modelId.startsWith('gpt-4o-mini-search-preview')) {
        if (args['temperature'] != null) {
          args['temperature'] = null;
          warnings.add(const UnsupportedWarning(
            'temperature',
            details:
                'temperature is not supported for the search preview models and has been removed.',
          ));
        }
      }
    }

    // 校验 service_tier flex/priority 处理能力。
    if (openaiOptions.serviceTier == 'flex' &&
        !capabilities.supportsFlexProcessing) {
      warnings.add(const UnsupportedWarning(
        'serviceTier',
        details:
            'flex processing is only available for o3, o4-mini, and gpt-5 models',
      ));
      args['service_tier'] = null;
    }

    if (openaiOptions.serviceTier == 'priority' &&
        !capabilities.supportsPriorityProcessing) {
      warnings.add(const UnsupportedWarning(
        'serviceTier',
        details:
            'priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported',
      ));
      args['service_tier'] = null;
    }

    final toolsResult = prepareOpenAiChatTools(
      tools: options.tools,
      toolChoice: options.toolChoice,
    );
    warnings.addAll(toolsResult.warnings);
    args['tools'] = toolsResult.tools;
    args['tool_choice'] = toolsResult.toolChoice;

    args.removeWhere((_, value) => value == null);

    return (args: args, warnings: warnings);
  }

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options);

    // `jsonResponseHandler` 只产出解码后的业务值,响应头需要在
    // `decode` 之外单独从 `ResponseContext` 捕获——用局部可变变量在
    // `successHandler` 闭包内旁路写入,`postJsonToApi` 保证
    // `successHandler` 在返回前已完整执行完毕,不存在竞态。
    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: built.args,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    // 与 `_buildArgs` 内 provider options 键派生取齐(azure 派生 key
    // 对称,见 `provider_options.dart` 文档);doGenerate 出参侧的
    // providerMetadata(refusal 标记 + 下方 prediction tokens/logprobs)
    // 统一用这份派生 key,而非上游硬编码的 'openai'。
    final providerOptionsName =
        resolveOpenAiProviderOptionsName(config.providerName);

    final choices = response['choices']! as List<Object?>;
    final choice = choices.first! as JsonObject;
    final message = choice['message']! as JsonObject;

    final content = <LanguageModelContent>[];

    final text = message['content'] as String?;
    if (text != null && text.isNotEmpty) {
      content.add(TextContent(text));
    } else {
      // v7 未处理 refusal 字段(`raw/openai-chat-language-model.ts` 无
      // 匹配)。官方 chat completions API 文档:模型拒绝回复时
      // `message.content` 为 null,拒绝文本改放 `message.refusal`。
      // 契约无专门 refusal 类型,对调用方而言这仍是模型的文本回复,故
      // 映射为 TextContent 并在 providerMetadata 标记来源,避免语义丢失。
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

    final toolCalls = message['tool_calls'] as List<Object?>?;
    if (toolCalls != null) {
      for (final raw in toolCalls) {
        final toolCall = raw! as JsonObject;
        final function = toolCall['function']! as JsonObject;
        content.add(ToolCall(
          toolCallId: (toolCall['id'] as String?) ?? generateId(),
          toolName: function['name']! as String,
          input: function['arguments']! as String,
        ));
      }
    }

    // annotations/citations(search-preview 模型):逐字对照 raw
    // `openai-chat-language-model.ts` ~384-393 行。`url_citation` 缺失或
    // 非对象时跳过该条,不 throw(wire 容错)。
    final annotations = message['annotations'] as List<Object?>?;
    if (annotations != null) {
      for (final raw in annotations) {
        final annotation = raw! as JsonObject;
        final urlCitation = annotation['url_citation'];
        if (urlCitation is! JsonObject) {
          continue;
        }
        content.add(SourceContent.url(
          id: generateId(),
          url: urlCitation['url']! as String,
          title: urlCitation['title'] as String?,
        ));
      }
    }

    final finishReason =
        mapOpenAiChatFinishReason(choice['finish_reason'] as String?);
    final usage = convertOpenAiChatUsage(response['usage'] as JsonObject?);
    final metadata = getOpenAiChatResponseMetadata(response);

    // provider metadata:accepted/rejected prediction tokens + logprobs。
    // 逐字对照 raw `openai-chat-language-model.ts` ~395-408 行;**key 决策
    // 超上游**——上游硬编码 'openai' 键,本包为与 call 级 options/文件
    // 引用/responses 全输出侧的 azure 派生 key 对称(见
    // `provider_options.dart` `resolveOpenAiProviderOptionsName` 文档),
    // 复用上方已算出的派生 key(与 ~304-310 refusal 标记同一份 key)。
    final completionTokenDetails = (response['usage']
        as JsonObject?)?['completion_tokens_details'] as JsonObject?;
    final acceptedPredictionTokens =
        completionTokenDetails?['accepted_prediction_tokens'];
    final rejectedPredictionTokens =
        completionTokenDetails?['rejected_prediction_tokens'];
    final choiceLogprobs = (choice['logprobs'] as JsonObject?)?['content'];

    return LanguageModelGenerateResult(
      content: content,
      finishReason: finishReason,
      usage: usage,
      warnings: built.warnings,
      providerMetadata: {
        providerOptionsName: {
          if (acceptedPredictionTokens != null)
            'acceptedPredictionTokens': acceptedPredictionTokens,
          if (rejectedPredictionTokens != null)
            'rejectedPredictionTokens': rejectedPredictionTokens,
          if (choiceLogprobs != null) 'logprobs': choiceLogprobs,
        },
      },
      request: RequestInfo(body: built.args),
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
    final streamArgs = <String, Object?>{
      ...built.args,
      'stream': true,
      'stream_options': {'include_usage': true},
    };

    Map<String, String>? responseHeaders;
    // `postJsonStreamToApi`/`eventSourceResponseHandler` 用 `JsonValue`
    // 泛型实例化(而非 `JsonObject`),使 `rawEvents` 的类型与 Task 3
    // `throwIfStreamErrorBeforeOutput` 的签名(`Stream<ParseResult<JsonValue>>`)
    // 精确匹配——`JsonObject` 是 `Map<String, Object?>` 的别名而
    // `JsonValue` 是 `Object?` 的别名,`ParseResult<T>` 对 `T` 不变
    // (invariant),两者不能直接互相赋值,需要统一到共享契约要求的
    // `JsonValue` 层再在下方按需转换为 `JsonObject`。
    final rawEvents = await postJsonStreamToApi<JsonValue>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: streamArgs,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return eventSourceResponseHandler<JsonValue>(
          decode: (json) => json,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    final checkedEvents = await throwIfStreamErrorBeforeOutput(
      rawEvents,
      url: _requestUrl,
      requestBody: streamArgs,
      // 对照 raw `getError: chunk => 'error' in chunk ? chunk.error :
      // undefined`(`raw/openai-chat-language-model.ts` ~460 行)。
      getError: (value) =>
          value is JsonObject && value['error'] != null ? value['error'] : null,
      isOutputChunk: _isChatOutputChunk,
    );

    final stream = _toStreamParts(
      checkedEvents.map(_toJsonObjectParseResult),
      warnings: built.warnings,
      includeRawChunks: options.includeRawChunks ?? false,
      providerOptionsName: resolveOpenAiProviderOptionsName(
        config.providerName,
      ),
    );

    return LanguageModelStreamResult(
      stream: stream,
      request: RequestInfo(body: streamArgs),
      response: ResponseInfo(headers: responseHeaders),
    );
  }

  /// 把 [throwIfStreamErrorBeforeOutput] 返回的 `ParseResult<JsonValue>`
  /// 转为 `_toStreamParts` 所需的 `ParseResult<JsonObject>`。
  ///
  /// chat SSE 事件解析成功时其值恒为 JSON 对象(wire 协议保证),故
  /// 成功分支直接 `as JsonObject`;失败分支只搬运 `error`/`rawValue`,
  /// 不涉及类型转换。
  static ParseResult<JsonObject> _toJsonObjectParseResult(
    ParseResult<JsonValue> event,
  ) {
    return switch (event) {
      ParseSuccess<JsonValue>(:final value, :final rawValue) =>
        ParseSuccess<JsonObject>(value! as JsonObject, rawValue: rawValue),
      ParseFailure<JsonValue>(:final error, :final rawValue) =>
        ParseFailure<JsonObject>(error, rawValue: rawValue),
    };
  }

  Stream<LanguageModelStreamPart> _toStreamParts(
    Stream<ParseResult<JsonObject>> events, {
    required List<Warning> warnings,
    required bool includeRawChunks,
    required String providerOptionsName,
  }) async* {
    yield StreamStart(warnings);

    final tracker = StreamingToolCallTracker();
    var finishReason = const LanguageModelFinishReason(FinishReasonType.other);
    JsonObject? usage;
    var metadataExtracted = false;
    var isActiveText = false;
    // 本次文本流是否最终由 refusal 分支驱动(即 effectiveDelta 取自
    // refusalDelta 而非 textDelta)。收尾 TextEnd 据此条件性带上
    // providerMetadata 标记,与非流式 doGenerate 的 refusal 标记对称
    // (~399-409 行)。
    var isRefusalText = false;
    // FinishPart 的 provider metadata 累积状态:逐字对照 raw
    // `openai-chat-language-model.ts` ~528-544/556-558 行——accepted/
    // rejected prediction tokens 在 usage 事件到达时写入(覆盖式,取
    // 最后一次非空值);logprobs 同样是覆盖式(每帧的 `choice.logprobs.
    // content` 若非空整体替换,不是逐 chunk 累积——上游通常只在最后一帧
    // 携带完整 logprobs 数组)。
    Object? acceptedPredictionTokens;
    Object? rejectedPredictionTokens;
    Object? choiceLogprobs;

    try {
      await for (final event in events) {
        if (includeRawChunks) {
          yield RawPart(
            event is ParseSuccess<JsonObject>
                ? event.rawValue
                : (event as ParseFailure<JsonObject>).rawValue,
          );
        }

        if (event is ParseFailure<JsonObject>) {
          // 帧级解析失败:ErrorPart 即终态,立即终止流,不再走收尾的
          // TextEnd/finishAll/FinishPart(与 responses 侧 `encounteredStreamError`
          // 语义对齐,契约 `LanguageModelStreamPart` 头文档「error 即终端事件」)。
          yield ErrorPart(event.error);
          return;
        }

        final value = (event as ParseSuccess<JsonObject>).value;

        final errorFrame = value['error'];
        if (errorFrame != null) {
          // wire 错误信封(`{"error": {...}}`):同上,ErrorPart 后立即终止流。
          yield ErrorPart(errorFrame);
          return;
        }

        if (!metadataExtracted) {
          final metadata = getOpenAiChatResponseMetadata(value);
          if (metadata.id != null ||
              metadata.modelId != null ||
              metadata.timestamp != null) {
            metadataExtracted = true;
            yield ResponseMetadata(
              id: metadata.id,
              timestamp: metadata.timestamp,
              modelId: metadata.modelId,
            );
          }
        }

        final usageValue = value['usage'] as JsonObject?;
        if (usageValue != null) {
          usage = usageValue;

          final completionTokenDetails =
              usageValue['completion_tokens_details'] as JsonObject?;
          final accepted =
              completionTokenDetails?['accepted_prediction_tokens'];
          if (accepted != null) {
            acceptedPredictionTokens = accepted;
          }
          final rejected =
              completionTokenDetails?['rejected_prediction_tokens'];
          if (rejected != null) {
            rejectedPredictionTokens = rejected;
          }
        }

        final choices = value['choices'] as List<Object?>? ?? const [];
        final choice = choices.isNotEmpty ? choices.first as JsonObject? : null;

        final rawFinishReason = choice?['finish_reason'] as String?;
        if (rawFinishReason != null) {
          finishReason = mapOpenAiChatFinishReason(rawFinishReason);
        }

        final deltaLogprobs = (choice?['logprobs'] as JsonObject?)?['content'];
        if (deltaLogprobs != null) {
          choiceLogprobs = deltaLogprobs;
        }

        final delta = choice?['delta'] as JsonObject?;
        if (delta == null) {
          continue;
        }

        // v7 未处理 refusal delta(`raw/openai-chat-language-model.ts` 无
        // 匹配)。官方 API 文档:流式拒绝回复通过 `delta.refusal` 逐字增量
        // 下发,与 `delta.content` 互斥(同一时刻只会出现其一)。两者复用
        // 同一惰性 text-start/text-delta 逻辑与块 id `'0'`;若上游异常地
        // 在同一帧同时给出两者(未在官方文档中出现的情形),按 content
        // 优先——因为 content 是正常回复的权威字段,refusal 只在拒绝场景下
        // 作为唯一文本来源出现,content 非空即说明这不是纯拒绝帧。
        final textDelta = delta['content'] as String?;
        final refusalDelta = delta['refusal'] as String?;
        final effectiveDelta = textDelta ?? refusalDelta;
        if (effectiveDelta != null) {
          if (!isActiveText) {
            yield const TextStart('0');
            isActiveText = true;
          }
          if (effectiveDelta == refusalDelta) {
            isRefusalText = true;
          }
          yield TextDelta('0', effectiveDelta);
        }

        final toolCallDeltas = delta['tool_calls'] as List<Object?>?;
        if (toolCallDeltas != null) {
          for (final raw in toolCallDeltas) {
            final toolCallDelta = raw! as JsonObject;
            final index = (toolCallDelta['index'] as num?)?.toInt();
            final function = toolCallDelta['function'] as JsonObject?;
            final events = tracker.addDelta(
              index: index,
              id: toolCallDelta['id'] as String?,
              name: function?['name'] as String?,
              argumentsDelta: function?['arguments'] as String?,
            );
            for (final part in events) {
              yield part;
            }
          }
        }

        // annotations/citations(search-preview 模型):逐字对照 raw
        // `openai-chat-language-model.ts` ~585-593 行,顺序在
        // text/tool_calls 之后。`url_citation` 缺失或非对象时跳过该条。
        final annotationDeltas = delta['annotations'] as List<Object?>?;
        if (annotationDeltas != null) {
          for (final raw in annotationDeltas) {
            final annotation = raw! as JsonObject;
            final urlCitation = annotation['url_citation'];
            if (urlCitation is! JsonObject) {
              continue;
            }
            yield SourceContent.url(
              id: generateId(),
              url: urlCitation['url']! as String,
              title: urlCitation['title'] as String?,
            );
          }
        }
      }
    } catch (error) {
      // 连接级 Stream error(如 SSE 中途断连):`eventSourceResponseHandler`
      // 按设计把这类失败作为 Dart `Stream.error` 转发(职责切分见
      // `packages/provider_utils` 设计:由 provider 层负责转 ErrorPart)。
      // 与上方帧级错误(ParseFailure/wire 错误信封)同一终态处理:
      // ErrorPart 后立即终止流,不再补发 TextEnd/FinishPart。
      yield ErrorPart(error);
      return;
    }

    if (isActiveText) {
      yield TextEnd(
        '0',
        providerMetadata: isRefusalText
            ? {
                providerOptionsName: {'refusal': true},
              }
            : null,
      );
    }
    for (final part in tracker.finishAll()) {
      yield part;
    }

    yield FinishPart(
      usage: convertOpenAiChatUsage(usage),
      finishReason: finishReason,
      providerMetadata: {
        providerOptionsName: {
          if (acceptedPredictionTokens != null)
            'acceptedPredictionTokens': acceptedPredictionTokens,
          if (rejectedPredictionTokens != null)
            'rejectedPredictionTokens': rejectedPredictionTokens,
          if (choiceLogprobs != null) 'logprobs': choiceLogprobs,
        },
      },
    );
  }
}

/// 判定一个已解析的 chat SSE 事件是否已构成"输出 chunk",供
/// [throwIfStreamErrorBeforeOutput] 的探测窗口判断何时停止探测。
///
/// 逐字对照 raw `isOpenAIChatOutputChunk`(`raw/openai-chat-language-
/// model.ts` ~623-637 行):事件是错误信封(含 `error` 键)时不算输出
/// chunk(该分支不会实际触发——错误信封总是先被 `getError` 拦截并
/// throw,但保留判定顺序与上游一致);否则任一 choice 的
/// `delta.content` 为非空字符串、`delta.refusal` 为非空字符串、
/// `delta.tool_calls` 为非空数组、或 `delta.annotations` 为非空数组,
/// 即视为输出 chunk。`choices` 缺失或不是列表(如 usage-only 收尾帧)
/// 按无匹配 choice 处理,返回 false。
bool _isChatOutputChunk(JsonValue value) {
  if (value is! JsonObject) {
    return false;
  }
  if (value['error'] != null) {
    return false;
  }

  final choices = value['choices'];
  if (choices is! List<Object?>) {
    return false;
  }

  return choices.any((rawChoice) {
    if (rawChoice is! JsonObject) {
      return false;
    }
    final delta = rawChoice['delta'];
    if (delta is! JsonObject) {
      return false;
    }
    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      return true;
    }
    // 上游 predicate(raw ~623-638)无 refusal 判定——v7 chat 根本不处理
    // refusal delta;本实现超上游把 `delta.refusal` 映射为文本输出(见
    // `_toStreamParts` 的 refusal 分支),output 判定必须自洽:否则纯
    // refusal 流在 probe 窗口内等不到 output chunk,probe 会消费到流尾
    // 才返回(丢失流式语义),且 refusal 之后的错误帧被误判为
    // before-output 从 Future 抛出。
    final refusal = delta['refusal'];
    if (refusal is String && refusal.isNotEmpty) {
      return true;
    }
    final toolCalls = delta['tool_calls'];
    if (toolCalls is List<Object?> && toolCalls.isNotEmpty) {
      return true;
    }
    final annotations = delta['annotations'];
    if (annotations is List<Object?> && annotations.isNotEmpty) {
      return true;
    }
    return false;
  });
}
