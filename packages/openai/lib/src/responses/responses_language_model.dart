import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/capabilities.dart';
import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import '../internal/stream_error_probe.dart';
import 'convert_input.dart';
import 'convert_usage.dart';
import 'map_finish_reason.dart';
import 'prepare_tools.dart';
import 'responses_options.dart';

const _openAiMcpListToolsKind = 'openai.mcp_list_tools';

/// OpenAI 官方 API Responses(`/responses`)wire 的 [LanguageModel] 实现。
///
/// `doGenerate`/`doStream` 共用 [_buildArgs] 构造请求体;覆盖
/// message(text)/function_call/reasoning 与 provider-executed
/// code_interpreter/web/file search/mcp output item 映射。其他内置工具 item
/// 仍安全跳过,不影响其余 item 的正常映射。
final class OpenAiResponsesLanguageModel implements LanguageModel {
  /// 用给定的 [modelId] 与 [config] 构造一个 responses 语言模型。
  OpenAiResponsesLanguageModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client 等)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => '${config.providerName}.responses';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => {
        'image/*': [RegExp(r'^https?://.*$')],
        'application/pdf': [RegExp(r'^https?://.*$')],
      };

  ({
    JsonObject args,
    List<Warning> warnings,
    bool store,
    String providerOptionsName,
    bool logprobsRequested,
    String? codeInterpreterToolName,
    String? fileSearchToolName,
    String? imageGenerationToolName,
    String? webSearchToolName,
    String? applyPatchToolName,
    String? toolSearchToolName,
    String? shellToolName,
    bool shellProviderExecuted,
  }) _buildArgs(
    LanguageModelCallOptions options,
  ) {
    final warnings = <Warning>[];
    final capabilities = getOpenAiLanguageModelCapabilities(modelId);
    final providerOptionsName =
        resolveOpenAiProviderOptionsName(config.providerName);

    if (options.topK != null) {
      warnings.add(const UnsupportedWarning('topK'));
    }
    if (options.seed != null) {
      warnings.add(const UnsupportedWarning('seed'));
    }
    if (options.presencePenalty != null) {
      warnings.add(const UnsupportedWarning('presencePenalty'));
    }
    if (options.frequencyPenalty != null) {
      warnings.add(const UnsupportedWarning('frequencyPenalty'));
    }
    if (options.stopSequences != null) {
      warnings.add(const UnsupportedWarning('stopSequences'));
    }

    final openaiOptions = OpenAiResponsesProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
        config.providerName,
        options.providerOptions,
      ),
    );

    final bothContinuationFieldsSet = openaiOptions.conversation != null &&
        openaiOptions.previousResponseId != null;
    if (bothContinuationFieldsSet) {
      warnings.add(
        const UnsupportedWarning(
          'conversation',
          details:
              'conversation and previousResponseId cannot be used together',
        ),
      );
    }

    // v7(`raw/openai-responses-language-model.ts`)在两者同时设置时只发
    // Warning,请求体仍会把两个互斥字段一并发给 OpenAI(必被拒绝)——
    // 未见任何"丢弃其一"的先例可逐字对齐。契约层没有更明确的取舍依据,
    // 故取更保守的一侧:保留 [OpenAiResponsesProviderOptions.conversation]
    // (续接会话的规范字段),丢弃 [previousResponseId](旧字段,官方文档
    // 已建议迁移到 conversation),避免明知冲突仍下发必被拒绝的请求体。
    final effectivePreviousResponseId =
        bothContinuationFieldsSet ? null : openaiOptions.previousResponseId;

    final isReasoningModel =
        openaiOptions.forceReasoning ?? capabilities.isReasoningModel;

    // 契约 [ReasoningEffort.providerDefault] 语义是「显式要求使用服务端
    // 默认值」,不是一个合法的 wire effort 取值(OpenAI 只接受
    // none/minimal/low/medium/high/xhigh)——按「未设置」处理,不发
    // `reasoning.effort` 字段,让服务端使用其默认值。
    final standardReasoningIsProviderDefault =
        options.reasoning == ReasoningEffort.providerDefault;
    final resolvedReasoningEffort = openaiOptions.reasoningEffort ??
        (standardReasoningIsProviderDefault
            ? null
            : options.reasoning?.wireValue);
    final resolvedReasoningSummary = openaiOptions.reasoningSummary ??
        ((resolvedReasoningEffort != null && resolvedReasoningEffort != 'none')
            ? 'detailed'
            : null);

    final systemMessageMode = openaiOptions.systemMessageMode ??
        (isReasoningModel
            ? SystemMessageMode.developer
            : capabilities.systemMessageMode);

    final inputResult = convertToOpenAiResponsesInput(
      prompt: options.prompt,
      systemMessageMode: systemMessageMode,
      store: openaiOptions.store ?? true,
      tools: options.tools,
      // conversation 恒生效(两续接字段冲突时消解丢弃的是
      // previousResponseId 一侧,conversation 不受影响):对齐上游
      // `hasConversation: openaiOptions?.conversation != null`。
      hasConversation: openaiOptions.conversation != null,
      // 用冲突消解后的 [effectivePreviousResponseId](而非原始
      // `openaiOptions.previousResponseId`):两字段同时设置时请求体已
      // 丢弃 previousResponseId,此时不是真正的续接模式,不应跳过任何
      // stored item。
      hasPreviousResponseId: effectivePreviousResponseId != null,
      providerOptionsName: providerOptionsName,
    );
    warnings.addAll(inputResult.warnings);

    final toolsResult = prepareOpenAiResponsesTools(
      tools: options.tools,
      toolChoice: options.toolChoice,
    );
    warnings.addAll(toolsResult.warnings);
    final codeInterpreterToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.code_interpreter',
    );
    final fileSearchToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.file_search',
    );
    final imageGenerationToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.image_generation',
    );
    final webSearchToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.web_search',
    );
    final applyPatchToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.apply_patch',
    );
    final toolSearchToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.tool_search',
    );
    final shellToolName = _providerToolName(
      tools: options.tools,
      id: 'openai.shell',
    );
    final shellProviderExecuted = _isOpenAiShellProviderExecuted(options.tools);

    final responseFormat = options.responseFormat;
    final strictJsonSchema = openaiOptions.strictJsonSchema ?? true;

    // include 派生:从调用方显式给的列表出发按条件追加,已含则不重复。
    var include = openaiOptions.include;
    void addInclude(String key) {
      final current = include;
      if (current == null) {
        include = <String>[key];
      } else if (!current.contains(key)) {
        include = <String>[...current, key];
      }
    }

    // logprobs 被请求时自动 include(raw ~293-303;`true` 对应上游
    // TOP_LOGPROBS_MAX,`0` 与上游 falsy 判定一致不触发 include)。
    final topLogprobs = switch (openaiOptions.logprobs) {
      true => 20,
      final int n => n,
      _ => null,
    };
    if (topLogprobs != null && topLogprobs != 0) {
      addInclude('message.output_text.logprobs');
    }

    if (webSearchToolName != null) {
      addInclude('web_search_call.action.sources');
    }

    if (codeInterpreterToolName != null) {
      addInclude('code_interpreter_call.outputs');
    }

    // store 在 OpenAI responses API 默认 true,故精确判 false(raw
    // ~324-329):非存储模式下推理内容只能靠 encrypted_content 续接,
    // 不主动请求该字段则响应不携带,下一轮输入转换器会把无
    // encrypted_content 的 reasoning part 整体过滤(见 convert_input.dart
    // 的 store==false 过滤),非存储多轮推理链断裂。
    if (openaiOptions.store == false && isReasoningModel) {
      addInclude('reasoning.encrypted_content');
    }

    final body = <String, Object?>{
      'model': modelId,
      'input': inputResult.input,
      'temperature': options.temperature,
      'top_p': options.topP,
      'max_output_tokens': options.maxOutputTokens,
      if (responseFormat is ResponseFormatJson ||
          openaiOptions.textVerbosity != null)
        'text': <String, Object?>{
          if (responseFormat is ResponseFormatJson)
            'format': responseFormat.schema != null
                ? <String, Object?>{
                    'type': 'json_schema',
                    'strict': strictJsonSchema,
                    'name': responseFormat.name ?? 'response',
                    if (responseFormat.description != null)
                      'description': responseFormat.description,
                    'schema': responseFormat.schema!.value,
                  }
                : <String, Object?>{'type': 'json_object'},
          if (openaiOptions.textVerbosity != null)
            'verbosity': openaiOptions.textVerbosity,
        },
      'conversation': openaiOptions.conversation,
      'max_tool_calls': openaiOptions.maxToolCalls,
      'metadata': openaiOptions.metadata,
      'parallel_tool_calls': openaiOptions.parallelToolCalls,
      'previous_response_id': effectivePreviousResponseId,
      'store': openaiOptions.store,
      'user': openaiOptions.user,
      'instructions': openaiOptions.instructions,
      'service_tier': openaiOptions.serviceTier,
      'include': include,
      'prompt_cache_key': openaiOptions.promptCacheKey,
      'prompt_cache_retention': openaiOptions.promptCacheRetention,
      'safety_identifier': openaiOptions.safetyIdentifier,
      'top_logprobs': topLogprobs,
      'truncation': openaiOptions.truncation,
      if (isReasoningModel &&
          (resolvedReasoningEffort != null || resolvedReasoningSummary != null))
        'reasoning': <String, Object?>{
          if (resolvedReasoningEffort != null)
            'effort': resolvedReasoningEffort,
          if (resolvedReasoningSummary != null)
            'summary': resolvedReasoningSummary,
        },
      'tools': toolsResult.tools,
      'tool_choice': toolsResult.toolChoice,
    };

    if (isReasoningModel) {
      // reasoningEffort 为 'none' 时,gpt-5.1+ 系列模型仍允许
      // temperature/topP(见
      // https://platform.openai.com/docs/guides/latest-model#gpt-5-1-parameter-compatibility),
      // 与 chat 侧(`chat_language_model.dart` `_buildArgs`)同一判定条件。
      if (resolvedReasoningEffort != 'none' ||
          !capabilities.supportsNonReasoningParameters) {
        if (body['temperature'] != null) {
          body['temperature'] = null;
          warnings.add(
            const UnsupportedWarning(
              'temperature',
              details: 'temperature is not supported for reasoning models',
            ),
          );
        }
        if (body['top_p'] != null) {
          body['top_p'] = null;
          warnings.add(
            const UnsupportedWarning(
              'topP',
              details: 'topP is not supported for reasoning models',
            ),
          );
        }
      }
    } else {
      // 与 chat 侧(`chat_language_model.dart` `_buildArgs`)取齐:检查
      // 合并后的 [resolvedReasoningEffort](覆盖 provider-specific
      // reasoningEffort 与标准 options.reasoning 两种来源),而非只检查
      // provider-specific 字段——标准 reasoning(如 medium)在非推理模型
      // 上被静默丢弃时同样需要告警。[providerDefault] 已在上方按「未设置」
      // 处理(见 [standardReasoningIsProviderDefault]),故它本就不会
      // 落入这条 warning。
      if (resolvedReasoningEffort != null) {
        warnings.add(
          const UnsupportedWarning(
            'reasoningEffort',
            details:
                'reasoningEffort is not supported for non-reasoning models',
          ),
        );
      }
      if (openaiOptions.reasoningSummary != null) {
        warnings.add(
          const UnsupportedWarning(
            'reasoningSummary',
            details:
                'reasoningSummary is not supported for non-reasoning models',
          ),
        );
      }
    }

    // 校验 service_tier flex/priority 处理能力,与 chat 侧
    // (`chat_language_model.dart` `_buildArgs`)取齐:同一能力表字段、同一
    // Warning 文案。
    if (openaiOptions.serviceTier == 'flex' &&
        !capabilities.supportsFlexProcessing) {
      warnings.add(const UnsupportedWarning(
        'serviceTier',
        details:
            'flex processing is only available for o3, o4-mini, and gpt-5 models',
      ));
      body['service_tier'] = null;
    }

    if (openaiOptions.serviceTier == 'priority' &&
        !capabilities.supportsPriorityProcessing) {
      warnings.add(const UnsupportedWarning(
        'serviceTier',
        details:
            'priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported',
      ));
      body['service_tier'] = null;
    }

    body.removeWhere((_, value) => value == null);

    return (
      args: body,
      warnings: warnings,
      store: openaiOptions.store ?? true,
      providerOptionsName: providerOptionsName,
      // gate 对齐 raw ~711 行 `options.providerOptions?.[providerOptionsName]
      // ?.logprobs`(真值判定):`0` 是合法的 top_logprobs 数量,故显式排除
      // null/false,其余值(含数值 0)均视为「已请求」。
      logprobsRequested:
          openaiOptions.logprobs != null && openaiOptions.logprobs != false,
      codeInterpreterToolName: codeInterpreterToolName,
      fileSearchToolName: fileSearchToolName,
      imageGenerationToolName: imageGenerationToolName,
      webSearchToolName: webSearchToolName,
      applyPatchToolName: applyPatchToolName,
      toolSearchToolName: toolSearchToolName,
      shellToolName: shellToolName,
      shellProviderExecuted: shellProviderExecuted,
    );
  }

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final built = _buildArgs(options);
    final url = Uri.parse('${config.baseUrl}/responses');

    // 包装 success handler 以捕获响应头(request id/rate-limit 等),与
    // chat 侧 `doGenerate` 及上游 `postJsonToApi` 返回 `responseHeaders`
    // 的语义取齐——`jsonResponseHandler` 本身只解码 body。
    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: url,
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

    if (response['error'] != null) {
      final error = response['error']! as JsonObject;
      throw ApiCallError(
        message: error['message'] as String? ?? 'Unknown error',
        url: url.toString(),
        requestBody: built.args,
        statusCode: 400,
        isRetryable: false,
      );
    }

    if (response['output'] is! List) {
      // 2xx 响应但 body 缺合法 `output` 数组(如误配 baseUrl 打到了
      // Chat Completions 端点,拿到 `{"choices": [...]}` 形状的响应):
      // 不再静默 fallback 成空 content + `finishReason: stop`,而是显式
      // 报错,避免调用方误以为模型正常返回了空结果。
      throw InvalidResponseDataError(
        data: response,
        message:
            "response is not a valid Responses API payload (missing 'output' array)",
      );
    }

    final content = <LanguageModelContent>[];
    var hasFunctionCall = false;
    final output = response['output']! as List<Object?>;
    final mcpApprovalToolCallIds = <String, String>{};
    // 收集各 output_text content part 的 logprobs(gate:调用方设置了
    // logprobs 选项 && 该 part 携带非空 logprobs),逐字对照 raw
    // ~708-715 行;非空时并入顶层 providerMetadata(~1042-1050 行)。
    final logprobs = <Object?>[];

    for (final rawItem in output) {
      final item = rawItem! as JsonObject;
      switch (item['type']) {
        case 'message':
          for (final rawPart in item['content']! as List<Object?>) {
            final part = rawPart! as JsonObject;
            switch (part['type']) {
              case 'output_text':
                final partLogprobs = part['logprobs'];
                if (built.logprobsRequested && partLogprobs != null) {
                  logprobs.add(partLogprobs);
                }
                final annotations = part['annotations'] as List<Object?>?;
                content.add(
                  TextContent(
                    part['text']! as String,
                    providerMetadata: {
                      built.providerOptionsName: {
                        'itemId': item['id'],
                        if (annotations != null && annotations.isNotEmpty)
                          'annotations': annotations,
                      },
                    },
                  ),
                );
                // 已知 annotation 类型映射为 SourceContent,顺序紧随
                // 其所属的 TextContent 之后;未知类型安全跳过、不告警。
                if (annotations != null) {
                  for (final rawAnnotation in annotations) {
                    final annotation = rawAnnotation! as JsonObject;
                    final source = _sourceContentFromAnnotation(
                      annotation,
                      built.providerOptionsName,
                    );
                    if (source != null) {
                      content.add(source);
                    }
                  }
                }

              case 'refusal':
                // v7 未处理 refusal content part(`raw/openai-responses-
                // language-model.ts` 无匹配)。官方 responses API 文档:
                // message content part 的 refusal 变体用 `refusal` 字段
                // 携带拒绝文本(与 `output_text` 变体的 `text` 字段并列)。
                // 契约无专门 refusal 类型,对调用方而言仍是模型的文本
                // 回复,故映射为 TextContent 并在 providerMetadata 标记
                // 来源,避免语义丢失。
                content.add(
                  TextContent(
                    part['refusal']! as String,
                    providerMetadata: {
                      built.providerOptionsName: {
                        'itemId': item['id'],
                        'refusal': true,
                      },
                    },
                  ),
                );

              default:
                // 未知 content part 类型:安全跳过,不再无条件 cast
                // part['text'](该 cast 对 refusal part 会抛异常)。
                built.warnings.add(
                  OtherWarning(
                    'unsupported response message content part type '
                    '"${part['type']}"; skipping',
                  ),
                );
            }
          }

        case 'function_call':
          hasFunctionCall = true;
          content.add(
            ToolCall(
              toolCallId: item['call_id']! as String,
              toolName: item['name']! as String,
              input: item['arguments']! as String,
              providerMetadata: {
                built.providerOptionsName: {'itemId': item['id']},
              },
            ),
          );

        case 'file_search_call':
          final toolName = built.fileSearchToolName ?? 'file_search';
          final itemId = item['id']! as String;
          content
            ..add(
              ToolCall(
                toolCallId: itemId,
                toolName: toolName,
                input: '{}',
                providerExecuted: true,
              ),
            )
            ..add(
              ToolResult(
                toolCallId: itemId,
                toolName: toolName,
                result: _mapFileSearchOutput(item),
              ),
            );

        case 'code_interpreter_call':
          final toolName = built.codeInterpreterToolName ?? 'code_interpreter';
          final itemId = item['id']! as String;
          content
            ..add(
              ToolCall(
                toolCallId: itemId,
                toolName: toolName,
                input: jsonEncode({
                  'code': item['code'],
                  'containerId': item['container_id'],
                }),
                providerExecuted: true,
              ),
            )
            ..add(
              ToolResult(
                toolCallId: itemId,
                toolName: toolName,
                result: <String, Object?>{
                  'outputs': item['outputs'],
                },
              ),
            );

        case 'image_generation_call':
          final toolName = built.imageGenerationToolName ?? 'image_generation';
          final itemId = item['id']! as String;
          content
            ..add(
              ToolCall(
                toolCallId: itemId,
                toolName: toolName,
                input: '{}',
                providerExecuted: true,
              ),
            )
            ..add(
              ToolResult(
                toolCallId: itemId,
                toolName: toolName,
                result: <String, Object?>{
                  'result': item['result'],
                },
              ),
            );

        case 'web_search_call':
          final toolName = built.webSearchToolName ?? 'web_search';
          final itemId = item['id']! as String;
          content
            ..add(
              ToolCall(
                toolCallId: itemId,
                toolName: toolName,
                input: '{}',
                providerExecuted: true,
              ),
            )
            ..add(
              ToolResult(
                toolCallId: itemId,
                toolName: toolName,
                result: _mapWebSearchOutput(item['action'] as JsonObject?),
              ),
            );

        case 'apply_patch_call':
          final call = _mapApplyPatchToolCall(
            item,
            built.providerOptionsName,
            built.applyPatchToolName,
          );
          hasFunctionCall = true;
          content.add(call);

        case 'custom_tool_call':
          hasFunctionCall = true;
          content.add(
            _mapCustomToolCall(item, built.providerOptionsName),
          );

        case 'shell_call':
          final call = _mapShellToolCall(
            item,
            built.providerOptionsName,
            built.shellToolName,
            built.shellProviderExecuted,
          );
          if (call.providerExecuted != true) {
            hasFunctionCall = true;
          }
          content.add(call);

        case 'shell_call_output':
          content.add(
            _mapShellToolResult(
              item,
              built.providerOptionsName,
              built.shellToolName,
            ),
          );

        case 'tool_search_call':
          final call = _mapToolSearchToolCall(
            item,
            built.providerOptionsName,
            built.toolSearchToolName,
          );
          if (call.providerExecuted != true) {
            hasFunctionCall = true;
          }
          content.add(call);

        case 'tool_search_output':
          content.add(
            _mapToolSearchToolResult(
              item,
              built.providerOptionsName,
              built.toolSearchToolName,
            ),
          );

        case 'mcp_call':
          final itemId = item['id']! as String;
          final approvalRequestId = item['approval_request_id'] as String?;
          final toolCallId = approvalRequestId == null
              ? itemId
              : mcpApprovalToolCallIds[approvalRequestId] ?? itemId;
          final toolName = _mcpToolName(item);
          content
            ..add(
              ToolCall(
                toolCallId: toolCallId,
                toolName: toolName,
                input: item['arguments']! as String,
                providerExecuted: true,
                isDynamic: true,
                providerMetadata: {
                  built.providerOptionsName: {'itemId': itemId, 'item': item},
                },
              ),
            )
            ..add(
              ToolResult(
                toolCallId: toolCallId,
                toolName: toolName,
                result: _mapMcpCallOutput(item),
                isError: item['error'] == null ? null : true,
                providerMetadata: {
                  built.providerOptionsName: {'itemId': itemId, 'item': item},
                },
              ),
            );

        case 'mcp_list_tools':
          content.add(
            CustomContentBlock(
              _openAiMcpListToolsKind,
              providerMetadata: {
                built.providerOptionsName: {'item': item},
              },
            ),
          );

        case 'mcp_approval_request':
          hasFunctionCall = true;
          final approvalId = _mcpApprovalId(item);
          final toolCallId = generateId();
          mcpApprovalToolCallIds[approvalId] = toolCallId;
          final toolName = _mcpToolName(item);
          content
            ..add(
              ToolCall(
                toolCallId: toolCallId,
                toolName: toolName,
                input: item['arguments']! as String,
                providerExecuted: true,
                isDynamic: true,
                providerMetadata: {
                  built.providerOptionsName: {
                    'itemId': item['id'],
                    'item': item,
                  },
                },
              ),
            )
            ..add(
              ToolApprovalRequest(
                approvalId: approvalId,
                toolCallId: toolCallId,
                providerMetadata: {
                  built.providerOptionsName: {
                    'itemId': item['id'],
                    'item': item,
                  },
                },
              ),
            );

        case 'reasoning':
          final summary = (item['summary'] as List<Object?>?) ?? const [];
          final encryptedContent = item['encrypted_content'] as String?;
          if (summary.isEmpty) {
            content.add(
              ReasoningContent(
                '',
                providerMetadata: {
                  built.providerOptionsName: {
                    'itemId': item['id'],
                    'reasoningEncryptedContent': encryptedContent,
                  },
                },
              ),
            );
          } else {
            for (final rawSummary in summary) {
              final summaryItem = rawSummary! as JsonObject;
              content.add(
                ReasoningContent(
                  summaryItem['text']! as String,
                  providerMetadata: {
                    built.providerOptionsName: {
                      'itemId': item['id'],
                      'reasoningEncryptedContent': encryptedContent,
                    },
                  },
                ),
              );
            }
          }

        default:
          built.warnings.add(
            OtherWarning(
              'unsupported response output item type '
              '"${item['type']}"; skipping',
            ),
          );
      }
    }

    final incompleteDetails = response['incomplete_details'] as JsonObject?;
    final incompleteReason = incompleteDetails?['reason'] as String?;

    return LanguageModelGenerateResult(
      content: content,
      finishReason: mapOpenAiResponsesFinishReason(
        incompleteReason: incompleteReason,
        hasFunctionCall: hasFunctionCall,
      ),
      usage: convertOpenAiResponsesUsage(response['usage'] as JsonObject?),
      warnings: built.warnings,
      providerMetadata: {
        built.providerOptionsName: {
          'responseId': response['id'],
          if (logprobs.isNotEmpty) 'logprobs': logprobs,
          if (response['service_tier'] is String)
            'serviceTier': response['service_tier'],
        },
      },
      request: RequestInfo(body: built.args),
      response: ResponseInfo(
        id: response['id'] as String?,
        timestamp: response['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (response['created_at']! as int) * 1000,
              )
            : null,
        modelId: response['model'] as String?,
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
    final url = Uri.parse('${config.baseUrl}/responses');
    final streamBody = <String, Object?>{...built.args, 'stream': true};

    // `postJsonStreamToApi`/`eventSourceResponseHandler` 用 `JsonValue`
    // 泛型实例化(而非 `JsonObject`),使 `rawStream` 的类型与
    // `throwIfStreamErrorBeforeOutput` 的签名
    // (`Stream<ParseResult<JsonValue>>`)精确匹配——`JsonObject` 是
    // `Map<String, Object?>` 的别名而 `JsonValue` 是 `Object?` 的别名,
    // `ParseResult<T>` 对 `T` 不变(invariant),两者不能直接互相赋值,
    // 需要统一到共享契约要求的 `JsonValue` 层再在下方按需转换为
    // `JsonObject`(与 Task 9 chat `doStream` 的处理方式一致)。
    // 包装 success handler 以捕获响应头,与 chat 侧 `doStream` 及上游
    // 流式路径返回 `responseHeaders` 的语义取齐。
    Map<String, String>? responseHeaders;
    final rawStream = await postJsonStreamToApi<JsonValue>(
      url: url,
      headers: combineHeaders([config.headers(), options.headers]),
      body: streamBody,
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

    final checkedStream = await throwIfStreamErrorBeforeOutput(
      rawStream,
      url: url,
      requestBody: streamBody,
      // 对照 raw `getError: chunk => isErrorChunk(chunk) ||
      // (isResponseFailedChunk(chunk) && chunk.response.error != null) ?
      // chunk : undefined`(`raw/openai-responses-language-model.ts`
      // ~1112-1116 行)——注意返回的是**整个事件**(而非解包后的 error
      // 字段),交给 [_parseStreamError] 按 `type` 统一解析。
      getError: (value) {
        if (value is! JsonObject) {
          return null;
        }
        final isErrorChunk = value['type'] == 'error';
        final isResponseFailedWithError = value['type'] == 'response.failed' &&
            (value['response'] is JsonObject) &&
            (value['response']! as JsonObject)['error'] != null;
        return (isErrorChunk || isResponseFailedWithError) ? value : null;
      },
      isOutputChunk: _isResponsesOutputChunk,
    );

    return LanguageModelStreamResult(
      stream: _streamParts(
        checkedStream.map(_toJsonObjectParseResult),
        built.warnings,
        store: built.store,
        includeRawChunks: options.includeRawChunks ?? false,
        providerOptionsName: built.providerOptionsName,
        logprobsRequested: built.logprobsRequested,
        codeInterpreterToolName: built.codeInterpreterToolName,
        fileSearchToolName: built.fileSearchToolName,
        imageGenerationToolName: built.imageGenerationToolName,
        webSearchToolName: built.webSearchToolName,
        applyPatchToolName: built.applyPatchToolName,
        toolSearchToolName: built.toolSearchToolName,
        shellToolName: built.shellToolName,
        shellProviderExecuted: built.shellProviderExecuted,
      ),
      request: RequestInfo(body: streamBody),
      response: ResponseInfo(headers: responseHeaders),
    );
  }

  /// 把 [throwIfStreamErrorBeforeOutput] 返回的 `ParseResult<JsonValue>`
  /// 转为 `_streamParts` 所需的 `ParseResult<JsonObject>`。
  ///
  /// responses SSE 事件解析成功时其值恒为 JSON 对象(wire 协议保证),故
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

  Stream<LanguageModelStreamPart> _streamParts(
    Stream<ParseResult<JsonObject>> events,
    List<Warning> warnings, {
    required bool store,
    required bool includeRawChunks,
    required String providerOptionsName,
    required bool logprobsRequested,
    required String? codeInterpreterToolName,
    required String? fileSearchToolName,
    required String? imageGenerationToolName,
    required String? webSearchToolName,
    required String? applyPatchToolName,
    required String? toolSearchToolName,
    required String? shellToolName,
    required bool shellProviderExecuted,
  }) async* {
    yield StreamStart(warnings);

    final state = _ResponsesStreamState();
    var encounteredStreamError = false;

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
          // 帧级解析/校验失败:直接终止流,不再走 finishReason 映射
          // (`encounteredStreamError=true` 会跳过收尾的 `FinishPart`,
          // 故此处不必、也不应设置 `state.finishReason`——error-as-
          // terminal-event,`ErrorPart` 即终态)。
          yield ErrorPart(event.error);
          encounteredStreamError = true;
          break;
        }

        final value = (event as ParseSuccess<JsonObject>).value;
        final type = value['type'] as String?;

        switch (type) {
          case 'response.created':
            final response = value['response']! as JsonObject;
            state.responseId = response['id'] as String?;
            yield ResponseMetadata(
              id: response['id'] as String?,
              timestamp: response['created_at'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (response['created_at']! as int) * 1000,
                    )
                  : null,
              modelId: response['model'] as String?,
            );

          case 'response.output_item.added':
            for (final part in _handleOutputItemAdded(
              value,
              state,
              providerOptionsName,
              codeInterpreterToolName,
              fileSearchToolName,
              imageGenerationToolName,
              webSearchToolName,
            )) {
              yield part;
            }

          case 'response.output_item.done':
            for (final part in _handleOutputItemDone(
              value,
              state,
              providerOptionsName,
              codeInterpreterToolName,
              fileSearchToolName,
              imageGenerationToolName,
              webSearchToolName,
              applyPatchToolName,
              toolSearchToolName,
              shellToolName,
              shellProviderExecuted,
            )) {
              yield part;
            }

          case 'response.output_text.delta':
            // logprobs 收集(gate:调用方设置了 logprobs 选项 && 该事件
            // 携带非空 logprobs),逐字对照 raw ~2015-2020 行;非空时并入
            // 收尾 FinishPart 的 providerMetadata(~2216-2222 行)。
            final deltaLogprobs = value['logprobs'];
            if (logprobsRequested && deltaLogprobs != null) {
              state.logprobs.add(deltaLogprobs);
            }
            yield TextDelta(
              value['item_id']! as String,
              value['delta']! as String,
            );

          case 'response.output_text.annotation.added':
            // 已知 annotation 类型映射为 SourceContent,原样累积到
            // `state.ongoingAnnotations`(随所属 message item 的
            // output_item.done 并入 TextEnd.providerMetadata)。未知类型
            // 与 doGenerate 侧一致地安全跳过,不 yield 任何分块。
            final annotation = value['annotation']! as JsonObject;
            state.ongoingAnnotations.add(annotation);
            final source = _sourceContentFromAnnotation(
              annotation,
              providerOptionsName,
            );
            if (source != null) {
              yield source;
            }

          case 'response.refusal.delta':
            // v7 未处理 refusal 流事件(`raw/openai-responses-language-
            // model.ts` 无匹配)。官方 responses API 文档:流式拒绝回复
            // 通过 `response.refusal.delta` 逐字增量下发,`item_id`/
            // `content_index` 语义与 `response.output_text.delta` 一致,
            // 复用同一 TextDelta 映射,块边界仍由 output_item.added/done
            // 驱动(与 output_text 系列一致,此处不单独处理 start/end)。
            // 登记该 item 由 refusal 驱动,收尾 TextEnd 据此带 refusal
            // 标记(见 [_ResponsesStreamState.refusalItemIds])。
            state.refusalItemIds.add(value['item_id']! as String);
            yield TextDelta(
              value['item_id']! as String,
              value['delta']! as String,
            );

          case 'response.refusal.done':
            // 与 `response.output_text.done`(本状态机同样未监听、块结束
            // 完全由 output_item.done 驱动)对齐:仅靠 delta 累积文本,
            // 此收尾事件不携带增量信息,安全忽略。
            break;

          case 'response.function_call_arguments.delta':
            final outputIndex = value['output_index']! as int;
            final call = state.ongoingFunctionCalls[outputIndex];
            if (call != null) {
              yield ToolInputDelta(
                call.toolCallId,
                value['delta']! as String,
              );
            }

          case 'response.code_interpreter_call_code.delta':
            final outputIndex = value['output_index']! as int;
            final call = state.ongoingCodeInterpreterCalls[outputIndex];
            if (call != null) {
              yield ToolInputDelta(
                call.toolCallId,
                _jsonStringFragment(value['delta']! as String),
              );
            }

          case 'response.code_interpreter_call_code.done':
            final outputIndex = value['output_index']! as int;
            final call = state.ongoingCodeInterpreterCalls[outputIndex];
            if (call != null) {
              yield ToolInputDelta(call.toolCallId, '"}');
              yield ToolInputEnd(call.toolCallId);
              yield ToolCall(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                input: jsonEncode({
                  'code': value['code'],
                  'containerId': call.containerId,
                }),
                providerExecuted: true,
              );
            }

          case 'response.image_generation_call.partial_image':
            yield ToolResult(
              toolCallId: value['item_id']! as String,
              toolName: imageGenerationToolName ?? 'image_generation',
              result: <String, Object?>{
                'result': value['partial_image_b64'],
              },
              preliminary: true,
            );

          case 'response.reasoning_summary_part.added':
            for (final part in _handleReasoningSummaryPartAdded(
              value,
              state,
              providerOptionsName,
            )) {
              yield part;
            }

          case 'response.reasoning_summary_text.delta':
            yield ReasoningDelta(
              '${value['item_id']}:${value['summary_index']}',
              value['delta']! as String,
            );

          case 'response.reasoning_summary_part.done':
            for (final part in _handleReasoningSummaryPartDone(
              value,
              state,
              providerOptionsName,
              store: store,
            )) {
              yield part;
            }

          case 'response.completed':
          case 'response.incomplete':
            final response = value['response']! as JsonObject;
            final incompleteDetails =
                response['incomplete_details'] as JsonObject?;
            state.finishReason = mapOpenAiResponsesFinishReason(
              incompleteReason: incompleteDetails?['reason'] as String?,
              hasFunctionCall: state.hasFunctionCall,
            );
            state.usage = response['usage'] as JsonObject?;
            final serviceTier = response['service_tier'];
            if (serviceTier is String) {
              state.serviceTier = serviceTier;
            }

          case 'response.failed':
            final response = value['response']! as JsonObject;
            final incompleteDetails =
                response['incomplete_details'] as JsonObject?;
            final incompleteReason = incompleteDetails?['reason'] as String?;
            state.finishReason = incompleteReason != null
                ? mapOpenAiResponsesFinishReason(
                    incompleteReason: incompleteReason,
                    hasFunctionCall: state.hasFunctionCall,
                  )
                : const LanguageModelFinishReason(
                    FinishReasonType.error,
                    raw: 'error',
                  );
            state.usage = response['usage'] as JsonObject?;
            final error = response['error'];
            if (!encounteredStreamError && error != null) {
              encounteredStreamError = true;
              yield ErrorPart(<String, Object?>{
                'type': 'response.failed',
                'response': <String, Object?>{'error': error},
              });
            }

          case 'error':
            encounteredStreamError = true;
            state.finishReason = const LanguageModelFinishReason(
              FinishReasonType.error,
              raw: 'error',
            );
            yield ErrorPart(value);

          default:
            // 未识别事件类型(含上游新增的 30+ 内置工具专属事件与
            // `unknown_chunk` 兜底):安全忽略,不中断流,对齐 raw
            // `openaiResponsesChunkSchema` 的 fallback discriminant 分支。
            break;
        }

        if (encounteredStreamError) {
          break;
        }
      }
    } catch (error) {
      // 连接级 Stream error(如 SSE 中途断连):`eventSourceResponseHandler`
      // 按设计把这类失败作为 Dart `Stream.error` 转发(职责切分见
      // `packages/provider_utils` 设计:由 provider 层负责转 ErrorPart)。
      // 与上方帧级/wire 错误同一终态处理:设置 `encounteredStreamError`
      // 复用下方既有的收尾守卫,跳过 `FinishPart`。
      yield ErrorPart(error);
      encounteredStreamError = true;
    }

    if (!encounteredStreamError) {
      yield FinishPart(
        usage: convertOpenAiResponsesUsage(state.usage),
        finishReason: state.finishReason,
        providerMetadata: {
          providerOptionsName: {
            'responseId': state.responseId,
            if (state.logprobs.isNotEmpty) 'logprobs': state.logprobs,
            if (state.serviceTier != null) 'serviceTier': state.serviceTier,
          },
        },
      );
    }
  }
}

/// `doStream` 状态机的可变局部状态(仅 `_streamParts` 内部使用)。
final class _ResponsesStreamState {
  LanguageModelFinishReason finishReason = const LanguageModelFinishReason(
    FinishReasonType.other,
  );
  JsonObject? usage;
  String? responseId;
  String? serviceTier;
  bool hasFunctionCall = false;

  /// `response.output_text.delta` 事件累积的 logprobs(仅在调用方设置了
  /// logprobs 选项时收集,见 [OpenAiResponsesLanguageModel._streamParts]
  /// 的 `logprobsRequested` gate)。
  final List<Object?> logprobs = <Object?>[];

  /// 当前 message item 累积的 `response.output_text.annotation.added`
  /// 原始 annotation 对象,随 message 的 `output_item.added` 清空、
  /// 随该 item 的 `output_item.done` 并入 `TextEnd.providerMetadata`。
  final List<Object?> ongoingAnnotations = <Object?>[];

  /// 收到过 `response.refusal.delta` 的 message itemId 集合:该 item 的
  /// 收尾 `TextEnd.providerMetadata` 据此带上 `refusal: true` 标记,与
  /// 非流式 refusal content part 及 chat 双路的标记对称(refusal 是本包
  /// 超上游特性,上游无对照;不标记则 streamText 聚合后拒绝回复与普通
  /// 文本不可区分)。
  final Set<String> refusalItemIds = <String>{};

  /// outputIndex → 进行中的 function_call 工具调用。
  final Map<int, ({String toolCallId, String toolName})> ongoingFunctionCalls =
      {};

  /// outputIndex → 进行中的 code_interpreter_call 工具调用。
  final Map<int, ({String toolCallId, String toolName, String containerId})>
      ongoingCodeInterpreterCalls = {};

  /// approval_request_id → 本地生成的 MCP toolCallId。
  final Map<String, String> mcpApprovalToolCallIds = {};

  /// reasoning itemId → 该 item 的状态(encryptedContent + 各 summary
  /// index 的三态机状态)。
  final Map<String, _ReasoningItemState> activeReasoning = {};
}

/// 单个 reasoning item 的可变状态:encrypted_content + summary 三态机。
final class _ReasoningItemState {
  String? encryptedContent;

  /// summaryIndex → 'active' | 'can-conclude' | 'concluded'。
  final Map<int, String> summaryStates = {0: 'active'};
}

String? _providerToolName({
  required List<LanguageModelTool>? tools,
  required String id,
}) {
  for (final tool in tools ?? const <LanguageModelTool>[]) {
    if (tool case ProviderTool(id: final toolId, name: final name)
        when toolId == id) {
      return name;
    }
  }
  return null;
}

bool _isOpenAiShellProviderExecuted(List<LanguageModelTool>? tools) {
  for (final tool in tools ?? const <LanguageModelTool>[]) {
    if (tool case ProviderTool(id: 'openai.shell', args: final args)) {
      final environment = args['environment'];
      if (environment is JsonObject) {
        final type = environment['type'];
        return type == 'containerAuto' || type == 'containerReference';
      }
    }
  }
  return false;
}

ProviderMetadata _providerItemMetadata(
  String providerOptionsName,
  JsonObject item,
) {
  final metadata = <String, Object?>{'item': item};
  final itemId = item['id'];
  if (itemId is String) {
    metadata['itemId'] = itemId;
  }
  return <String, Map<String, Object?>>{
    providerOptionsName: metadata,
  };
}

ToolCall _mapApplyPatchToolCall(
  JsonObject item,
  String providerOptionsName,
  String? applyPatchToolName,
) {
  return ToolCall(
    toolCallId: item['call_id']! as String,
    toolName: applyPatchToolName ?? 'apply_patch',
    input: jsonEncode({
      'callId': item['call_id'],
      'operation': item['operation'],
    }),
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

ToolCall _mapCustomToolCall(
  JsonObject item,
  String providerOptionsName,
) {
  return ToolCall(
    toolCallId: item['call_id']! as String,
    toolName: item['name']! as String,
    input: jsonEncode(item['input']),
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

ToolCall _mapShellToolCall(
  JsonObject item,
  String providerOptionsName,
  String? shellToolName,
  bool shellProviderExecuted,
) {
  final action = item['action']! as JsonObject;
  return ToolCall(
    toolCallId: item['call_id']! as String,
    toolName: shellToolName ?? 'shell',
    input: jsonEncode({
      'action': <String, Object?>{
        'commands': action['commands'],
        'timeoutMs': action['timeout_ms'],
        'maxOutputLength': action['max_output_length'],
      }..removeWhere((_, value) => value == null),
    }),
    providerExecuted: shellProviderExecuted ? true : null,
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

ToolResult _mapShellToolResult(
  JsonObject item,
  String providerOptionsName,
  String? shellToolName,
) {
  final output = item['output']! as List<Object?>;
  return ToolResult(
    toolCallId: item['call_id']! as String,
    toolName: shellToolName ?? 'shell',
    result: <String, Object?>{
      if (item.containsKey('max_output_length'))
        'maxOutputLength': item['max_output_length'],
      'output': output.map((entry) {
        final object = entry! as JsonObject;
        return <String, Object?>{
          'stdout': object['stdout'],
          'stderr': object['stderr'],
          'outcome': _mapShellOutcome(object['outcome']! as JsonObject),
        };
      }).toList(),
    },
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

JsonObject _mapShellOutcome(JsonObject outcome) {
  if (outcome['type'] == 'exit') {
    return <String, Object?>{
      'type': 'exit',
      'exitCode': outcome['exit_code'],
    };
  }
  return <String, Object?>{'type': 'timeout'};
}

ToolCall _mapToolSearchToolCall(
  JsonObject item,
  String providerOptionsName,
  String? toolSearchToolName,
) {
  final execution = item['execution'] as String?;
  final callId = (item['call_id'] as String?) ?? item['id']! as String;
  final isHosted = execution == 'server';
  return ToolCall(
    toolCallId: callId,
    toolName: toolSearchToolName ?? 'tool_search',
    input: jsonEncode({
      'arguments': item['arguments'],
      'call_id': isHosted ? null : callId,
    }),
    providerExecuted: isHosted ? true : null,
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

ToolResult _mapToolSearchToolResult(
  JsonObject item,
  String providerOptionsName,
  String? toolSearchToolName,
) {
  final callId = (item['call_id'] as String?) ?? item['id']! as String;
  return ToolResult(
    toolCallId: callId,
    toolName: toolSearchToolName ?? 'tool_search',
    result: <String, Object?>{'tools': item['tools']},
    providerMetadata: _providerItemMetadata(providerOptionsName, item),
  );
}

JsonObject _mapFileSearchOutput(JsonObject item) {
  final results = item['results'] as List<Object?>?;
  return <String, Object?>{
    'queries': item['queries'],
    'results': results?.map((result) {
      final object = result! as JsonObject;
      return <String, Object?>{
        'attributes': object['attributes'],
        'fileId': object['file_id'],
        'filename': object['filename'],
        'score': object['score'],
        'text': object['text'],
      };
    }).toList(),
  };
}

JsonObject _mapWebSearchOutput(JsonObject? action) {
  if (action == null) {
    return const <String, Object?>{};
  }

  return switch (action['type']) {
    'search' => <String, Object?>{
        'action': <String, Object?>{
          'type': 'search',
          'query': action['query'],
          'queries': action['queries'],
        }..removeWhere((_, value) => value == null),
        'sources': action['sources'],
      }..removeWhere((_, value) => value == null),
    'open_page' => <String, Object?>{
        'action': <String, Object?>{
          'type': 'openPage',
          'url': action['url'],
        },
      },
    'find_in_page' => <String, Object?>{
        'action': <String, Object?>{
          'type': 'findInPage',
          'url': action['url'],
          'pattern': action['pattern'],
        },
      },
    _ => <String, Object?>{'action': action},
  };
}

String _mcpToolName(JsonObject item) => 'mcp.${item['name']! as String}';

String _mcpApprovalId(JsonObject item) =>
    (item['approval_request_id'] as String?) ?? item['id']! as String;

JsonObject _mapMcpCallOutput(JsonObject item) {
  return <String, Object?>{
    'type': 'call',
    'serverLabel': item['server_label'],
    'name': item['name'],
    'arguments': item['arguments'],
    'output': item['output'],
    'error': item['error'],
  }..removeWhere((_, value) => value == null);
}

SourceContent? _sourceContentFromAnnotation(
  JsonObject annotation,
  String providerOptionsName,
) {
  switch (annotation['type']) {
    case 'url_citation':
      return SourceContent.url(
        id: generateId(),
        url: annotation['url']! as String,
        title: annotation['title'] as String?,
      );

    case 'file_citation':
      return SourceContent.document(
        id: generateId(),
        mediaType: 'text/plain',
        title: annotation['filename']! as String,
        filename: annotation['filename'] as String?,
        providerMetadata: {
          providerOptionsName: {
            'type': 'file_citation',
            'fileId': annotation['file_id'],
            'index': annotation['index'],
          },
        },
      );

    case 'container_file_citation':
      return SourceContent.document(
        id: generateId(),
        mediaType: 'text/plain',
        title: annotation['filename']! as String,
        filename: annotation['filename'] as String?,
        providerMetadata: {
          providerOptionsName: {
            'type': 'container_file_citation',
            'containerId': annotation['container_id'],
            'fileId': annotation['file_id'],
            'filename': annotation['filename'],
            'index': annotation['index'],
            'startIndex': annotation['start_index'],
            'endIndex': annotation['end_index'],
          }..removeWhere((_, value) => value == null),
        },
      );
  }
  return null;
}

String _jsonStringFragment(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

List<LanguageModelStreamPart> _handleOutputItemAdded(
  JsonObject value,
  _ResponsesStreamState state,
  String providerOptionsName,
  String? codeInterpreterToolName,
  String? fileSearchToolName,
  String? imageGenerationToolName,
  String? webSearchToolName,
) {
  final outputIndex = value['output_index']! as int;
  final item = value['item']! as JsonObject;

  switch (item['type']) {
    case 'function_call':
      final toolCallId = item['call_id']! as String;
      final toolName = item['name']! as String;
      state.ongoingFunctionCalls[outputIndex] =
          (toolCallId: toolCallId, toolName: toolName);
      return [ToolInputStart(id: toolCallId, toolName: toolName)];

    case 'code_interpreter_call':
      final itemId = item['id']! as String;
      final toolName = codeInterpreterToolName ?? 'code_interpreter';
      final containerId = item['container_id']! as String;
      state.ongoingCodeInterpreterCalls[outputIndex] = (
        toolCallId: itemId,
        toolName: toolName,
        containerId: containerId,
      );
      return [
        ToolInputStart(
          id: itemId,
          toolName: toolName,
          providerExecuted: true,
        ),
        ToolInputDelta(
          itemId,
          '{"containerId":${jsonEncode(containerId)},"code":"',
        ),
      ];

    case 'file_search_call':
      final itemId = item['id']! as String;
      final toolName = fileSearchToolName ?? 'file_search';
      return [
        ToolCall(
          toolCallId: itemId,
          toolName: toolName,
          input: '{}',
          providerExecuted: true,
        ),
      ];

    case 'image_generation_call':
      final itemId = item['id']! as String;
      final toolName = imageGenerationToolName ?? 'image_generation';
      return [
        ToolCall(
          toolCallId: itemId,
          toolName: toolName,
          input: '{}',
          providerExecuted: true,
        ),
      ];

    case 'web_search_call':
      final itemId = item['id']! as String;
      final toolName = webSearchToolName ?? 'web_search';
      return [
        ToolInputStart(
          id: itemId,
          toolName: toolName,
          providerExecuted: true,
        ),
        ToolInputEnd(itemId),
        ToolCall(
          toolCallId: itemId,
          toolName: toolName,
          input: '{}',
          providerExecuted: true,
        ),
      ];

    case 'message':
      // 新消息开始:清空上一条消息遗留的 ongoingAnnotations(逐字对齐
      // 上游 `ongoingAnnotations.splice(0, ongoingAnnotations.length)`
      // 的时机——在发 TextStart 之前清空)。
      state.ongoingAnnotations.clear();
      return [
        TextStart(
          item['id']! as String,
          providerMetadata: {
            providerOptionsName: {'itemId': item['id']},
          },
        ),
      ];

    case 'reasoning':
      final itemId = item['id']! as String;
      final encryptedContent = item['encrypted_content'] as String?;
      state.activeReasoning[itemId] = _ReasoningItemState()
        ..encryptedContent = encryptedContent;
      return [
        ReasoningStart(
          '$itemId:0',
          providerMetadata: {
            providerOptionsName: {
              'itemId': itemId,
              'reasoningEncryptedContent': encryptedContent,
            },
          },
        ),
      ];

    default:
      // 范围外 item 类型(内置工具等):不发任何分块,留给
      // `output_item.done` 或直接忽略;不 throw。
      return const [];
  }
}

List<LanguageModelStreamPart> _handleOutputItemDone(
  JsonObject value,
  _ResponsesStreamState state,
  String providerOptionsName,
  String? codeInterpreterToolName,
  String? fileSearchToolName,
  String? imageGenerationToolName,
  String? webSearchToolName,
  String? applyPatchToolName,
  String? toolSearchToolName,
  String? shellToolName,
  bool shellProviderExecuted,
) {
  final outputIndex = value['output_index']! as int;
  final item = value['item']! as JsonObject;

  switch (item['type']) {
    case 'function_call':
      state.ongoingFunctionCalls.remove(outputIndex);
      state.hasFunctionCall = true;
      final toolCallId = item['call_id']! as String;
      final toolName = item['name']! as String;
      final arguments = item['arguments']! as String;
      return [
        ToolInputEnd(toolCallId),
        ToolCall(
          toolCallId: toolCallId,
          toolName: toolName,
          input: arguments,
          providerMetadata: {
            providerOptionsName: {'itemId': item['id']},
          },
        ),
      ];

    case 'code_interpreter_call':
      final itemId = item['id']! as String;
      final toolName = codeInterpreterToolName ?? 'code_interpreter';
      state.ongoingCodeInterpreterCalls.remove(outputIndex);
      return [
        ToolResult(
          toolCallId: itemId,
          toolName: toolName,
          result: <String, Object?>{
            'outputs': item['outputs'],
          },
        ),
      ];

    case 'file_search_call':
      final itemId = item['id']! as String;
      final toolName = fileSearchToolName ?? 'file_search';
      return [
        ToolResult(
          toolCallId: itemId,
          toolName: toolName,
          result: _mapFileSearchOutput(item),
        ),
      ];

    case 'image_generation_call':
      final itemId = item['id']! as String;
      final toolName = imageGenerationToolName ?? 'image_generation';
      return [
        ToolResult(
          toolCallId: itemId,
          toolName: toolName,
          result: <String, Object?>{
            'result': item['result'],
          },
        ),
      ];

    case 'web_search_call':
      final itemId = item['id']! as String;
      final toolName = webSearchToolName ?? 'web_search';
      return [
        ToolResult(
          toolCallId: itemId,
          toolName: toolName,
          result: _mapWebSearchOutput(item['action'] as JsonObject?),
        ),
      ];

    case 'apply_patch_call':
      state.hasFunctionCall = true;
      return [
        _mapApplyPatchToolCall(item, providerOptionsName, applyPatchToolName),
      ];

    case 'custom_tool_call':
      state.hasFunctionCall = true;
      return [
        _mapCustomToolCall(item, providerOptionsName),
      ];

    case 'shell_call':
      final call = _mapShellToolCall(
        item,
        providerOptionsName,
        shellToolName,
        shellProviderExecuted,
      );
      if (call.providerExecuted != true) {
        state.hasFunctionCall = true;
      }
      return [
        call,
      ];

    case 'shell_call_output':
      return [
        _mapShellToolResult(item, providerOptionsName, shellToolName),
      ];

    case 'tool_search_call':
      final call =
          _mapToolSearchToolCall(item, providerOptionsName, toolSearchToolName);
      if (call.providerExecuted != true) {
        state.hasFunctionCall = true;
      }
      return [
        call,
      ];

    case 'tool_search_output':
      return [
        _mapToolSearchToolResult(item, providerOptionsName, toolSearchToolName),
      ];

    case 'mcp_call':
      final itemId = item['id']! as String;
      final approvalRequestId = item['approval_request_id'] as String?;
      final toolCallId = approvalRequestId == null
          ? itemId
          : state.mcpApprovalToolCallIds[approvalRequestId] ?? itemId;
      final toolName = _mcpToolName(item);
      return [
        ToolCall(
          toolCallId: toolCallId,
          toolName: toolName,
          input: item['arguments']! as String,
          providerExecuted: true,
          isDynamic: true,
          providerMetadata: {
            providerOptionsName: {'itemId': itemId, 'item': item},
          },
        ),
        ToolResult(
          toolCallId: toolCallId,
          toolName: toolName,
          result: _mapMcpCallOutput(item),
          isError: item['error'] == null ? null : true,
          providerMetadata: {
            providerOptionsName: {'itemId': itemId, 'item': item},
          },
        ),
      ];

    case 'mcp_list_tools':
      return [
        CustomContentBlock(
          _openAiMcpListToolsKind,
          providerMetadata: {
            providerOptionsName: {'item': item},
          },
        ),
      ];

    case 'mcp_approval_request':
      state.hasFunctionCall = true;
      final approvalId = _mcpApprovalId(item);
      final toolCallId = generateId();
      state.mcpApprovalToolCallIds[approvalId] = toolCallId;
      final toolName = _mcpToolName(item);
      return [
        ToolCall(
          toolCallId: toolCallId,
          toolName: toolName,
          input: item['arguments']! as String,
          providerExecuted: true,
          isDynamic: true,
          providerMetadata: {
            providerOptionsName: {'itemId': item['id'], 'item': item},
          },
        ),
        ToolApprovalRequest(
          approvalId: approvalId,
          toolCallId: toolCallId,
          providerMetadata: {
            providerOptionsName: {'itemId': item['id'], 'item': item},
          },
        ),
      ];

    case 'message':
      return [
        TextEnd(
          item['id']! as String,
          providerMetadata: {
            providerOptionsName: {
              'itemId': item['id'],
              if (state.ongoingAnnotations.isNotEmpty)
                'annotations': List<Object?>.of(state.ongoingAnnotations),
              // remove 顺带清理登记,避免跨 item 残留。
              if (state.refusalItemIds.remove(item['id'])) 'refusal': true,
            },
          },
        ),
      ];

    case 'reasoning':
      final itemId = item['id']! as String;
      final encryptedContent = item['encrypted_content'] as String?;
      final reasoningState = state.activeReasoning[itemId];
      if (reasoningState == null) {
        return const [];
      }

      final parts = <LanguageModelStreamPart>[];
      final concludableIndices = reasoningState.summaryStates.entries
          .where((e) => e.value == 'active' || e.value == 'can-conclude')
          .map((e) => e.key)
          .toList();

      for (final summaryIndex in concludableIndices) {
        parts.add(
          ReasoningEnd(
            '$itemId:$summaryIndex',
            providerMetadata: {
              providerOptionsName: {
                'itemId': itemId,
                'reasoningEncryptedContent': encryptedContent,
              },
            },
          ),
        );
      }

      state.activeReasoning.remove(itemId);
      return parts;

    default:
      return const [];
  }
}

List<LanguageModelStreamPart> _handleReasoningSummaryPartAdded(
  JsonObject value,
  _ResponsesStreamState state,
  String providerOptionsName,
) {
  final summaryIndex = value['summary_index']! as int;
  // 第一个 summary(index 0)的 reasoning-start 已在
  // `_handleOutputItemAdded` 里随 reasoning item 一并发出,此处只处理
  // index > 0 的后续 summary 段落。
  if (summaryIndex <= 0) {
    return const [];
  }

  final itemId = value['item_id']! as String;
  final reasoningState = state.activeReasoning[itemId];
  if (reasoningState == null) {
    return const [];
  }

  final parts = <LanguageModelStreamPart>[];

  reasoningState.summaryStates[summaryIndex] = 'active';

  final canConcludeIndices = reasoningState.summaryStates.entries
      .where((e) => e.value == 'can-conclude')
      .map((e) => e.key)
      .toList();
  for (final concludeIndex in canConcludeIndices) {
    parts.add(
      ReasoningEnd(
        '$itemId:$concludeIndex',
        providerMetadata: {
          providerOptionsName: {'itemId': itemId},
        },
      ),
    );
    reasoningState.summaryStates[concludeIndex] = 'concluded';
  }

  parts.add(
    ReasoningStart(
      '$itemId:$summaryIndex',
      providerMetadata: {
        providerOptionsName: {
          'itemId': itemId,
          'reasoningEncryptedContent': reasoningState.encryptedContent,
        },
      },
    ),
  );

  return parts;
}

List<LanguageModelStreamPart> _handleReasoningSummaryPartDone(
  JsonObject value,
  _ResponsesStreamState state,
  String providerOptionsName, {
  required bool store,
}) {
  final itemId = value['item_id']! as String;
  final summaryIndex = value['summary_index']! as int;
  final reasoningState = state.activeReasoning[itemId];
  if (reasoningState == null) {
    return const [];
  }

  // `store` 语义(raw §5.3):`store===true` 时服务端已保存完整推理
  // 内容,收到 `summary_part.done` 可立即 conclude 并发 `reasoning-end`;
  // `store===false` 时只标记 `can-conclude`,真正的 end 推迟到下一个
  // summary part 出现或整个 reasoning item 的 `output_item.done`,因为
  // `encrypted_content` 只在 item 级别提供,必须等到确定不再更新时才
  // 写入最后一个 `reasoning-end` 的 providerMetadata。
  if (store) {
    reasoningState.summaryStates[summaryIndex] = 'concluded';
    return [
      ReasoningEnd(
        '$itemId:$summaryIndex',
        providerMetadata: {
          providerOptionsName: {'itemId': itemId},
        },
      ),
    ];
  }

  reasoningState.summaryStates[summaryIndex] = 'can-conclude';
  return const [];
}

/// 上游 responses chunk discriminated union(`raw/openai-responses-api.ts`
/// ~508-1080 行,`openaiResponsesChunkSchema` 里 fallback 到
/// `unknown_chunk` 之前)已建模的全部事件 `type` 字符串,逐字提取自各
/// `z.object({ type: z.literal(...) })`/`z.enum([...])` 成员(行号为该
/// 成员在 raw 文件中的起始行):
/// - `response.output_text.delta`(~509)
/// - `response.completed`/`response.incomplete`(~528,同一个
///   `z.enum([...])` 判别式)
/// - `response.failed`(~552)
/// - `response.created`(~585)
/// - `response.output_item.added`(~594)
/// - `response.output_item.done`(~743)
/// - `response.function_call_arguments.delta`(~989)
/// - `response.custom_tool_call_input.delta`(~995)
/// - `response.image_generation_call.partial_image`(~1001)
/// - `response.code_interpreter_call_code.delta`(~1007)
/// - `response.code_interpreter_call_code.done`(~1013)
/// - `response.output_text.annotation.added`(~1019)
/// - `response.reasoning_summary_part.added`(~1050)
/// - `response.reasoning_summary_text.delta`(~1055)
/// - `response.reasoning_summary_part.done`(~1061)
/// - `response.apply_patch_call_operation_diff.delta`(~1066)
/// - `response.apply_patch_call_operation_diff.done`(~1073)
/// - `error`(~485 与 ~499 两个错误 schema 共用同一判别值)
///
/// 集合里除 `response.created`/`response.failed`/`error` 之外的其余
/// pigcode 未实现的内置工具事件类型(如
/// `response.custom_tool_call_input.delta`、
/// `response.apply_patch_call_operation_diff.*` 等)也原样列入——它们在
/// 上游是 output chunk,窗口语义与已实现事件一致,由 `_streamParts` 的
/// `default:` 分支安全忽略而非探测窗口误判。
const _kResponsesOutputChunkTypes = <String>{
  'response.output_text.delta',
  'response.completed',
  'response.incomplete',
  'response.failed',
  'response.created',
  'response.output_item.added',
  'response.output_item.done',
  'response.function_call_arguments.delta',
  'response.custom_tool_call_input.delta',
  'response.image_generation_call.partial_image',
  'response.code_interpreter_call_code.delta',
  'response.code_interpreter_call_code.done',
  'response.output_text.annotation.added',
  'response.reasoning_summary_part.added',
  'response.reasoning_summary_text.delta',
  'response.reasoning_summary_part.done',
  'response.apply_patch_call_operation_diff.delta',
  'response.apply_patch_call_operation_diff.done',
  'error',
};

/// 判定一个已解析的 responses SSE 事件是否已构成"输出 chunk",供
/// [throwIfStreamErrorBeforeOutput] 的探测窗口判断何时停止探测。
///
/// 逐字对照 raw `isResponseOutputChunk`(`raw/openai-responses-language-
/// model.ts` ~2392-2399 行):`!(type === 'response.created' ||
/// type === 'response.failed' || type === 'error' || type ===
/// 'unknown_chunk')`。上游的 `unknown_chunk` 是 schema fallback 判别式
/// (原始 `type` 不在 [_kResponsesOutputChunkTypes] 内时产出),pigcode
/// 的 responses chunk 解析没有这层包装,直接保留原始 `type` 字符串,故
/// 用**白名单**还原同一语义:事件类型落在 [_kResponsesOutputChunkTypes]
/// 内(即上游 union 内)且不是 `response.created`/`response.failed`/
/// `error` 才算输出 chunk;不在集合内(= 上游会 fallback 成
/// `unknown_chunk`,如未建模的 `response.in_progress`)一律不算输出
/// chunk,探测窗口保持打开继续探测下一个事件。
///
/// 采用黑名单的旧实现会把 `response.created` 之后必然先到达、但不在
/// 上游 union 内的 `response.in_progress` 误判为输出 chunk,导致探测
/// 窗口在真正的错误帧(如紧随其后的 `response.failed`/`error`)到达前
/// 就已经关闭——`doStream` 返回的 `Future` 不再有机会抛出
/// [ApiCallError],错误退化为仅在流内以 [ErrorPart] 出现。
bool _isResponsesOutputChunk(JsonValue value) {
  if (value is! JsonObject) {
    return false;
  }
  final type = value['type'];
  if (type is! String || !_kResponsesOutputChunkTypes.contains(type)) {
    return false;
  }
  return type != 'response.created' &&
      type != 'response.failed' &&
      type != 'error';
}
