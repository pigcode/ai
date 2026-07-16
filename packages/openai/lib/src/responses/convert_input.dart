import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/capabilities.dart';

const _openAiMcpListToolsKind = 'openai.mcp_list_tools';

/// [convertToOpenAiResponsesInput] 的结果:input items + 告警。
final class OpenAiResponsesInputResult {
  /// 用给定的 [input] 与 [warnings] 构造一个转换结果。
  const OpenAiResponsesInputResult({
    required this.input,
    required this.warnings,
  });

  /// 转换出的 responses `input` 数组元素(每个元素是一个 wire item)。
  final List<JsonObject> input;

  /// 转换过程中产生的告警(不支持的 part/降级等)。
  final List<Warning> warnings;
}

/// 把契约 [LanguageModelPrompt] 转换为 OpenAI Responses API 的 `input` 数组。
///
/// 字段取舍逐字对照上游 `convert-to-openai-responses-input.ts`;首版覆盖
/// message(system/developer/user/assistant text)/function_call/
/// function_call_output/reasoning 四种 item 类型 + `item_reference` 硬性项
/// (见设计文档 §1:`store==true` 且已有 `itemId` 的 assistant text/
/// tool-call/reasoning 用 `{type:'item_reference', id}` 回传)。
///
/// OpenAI provider-defined 工具只在本轮 [tools] 明确包含对应
/// [ProviderTool] 时启用专属历史转换:shell/apply_patch/
/// tool_search/custom 的 call/result 会回放为 Responses 原生 item 或
/// `item_reference`。其它 `providerExecuted:true` 的 tool-call 仍跳过并
/// 追加告警,不 throw。MCP 审批响应仅在能从前序 assistant 消息或 OpenAI
/// provider metadata 确认其来源时,按 Responses API 的
/// `mcp_approval_response` 回传。
///
/// [hasPreviousResponseId] 逐字对齐上游同名参数(`convert-to-openai-
/// responses-input.ts` ~79 行):`previousResponseId` 续接模式下,OpenAI
/// 已从被续接的响应链里前置了该链上产生的 reasoning/function-call item,
/// 原样重发这些 item(哪怕是 `item_reference`)会导致 item 重复或
/// call/output 配对失败。上游只对 **reasoning** 与**非 provider-defined
/// 的 plain function-call**这两类 part 生效(见 raw ~326、~546 行);
/// text/tool-result/compaction part 不受此参数影响,仍按 `store` 走
/// `item_reference`/原样内联。
///
/// [hasConversation] 逐字对齐上游同名参数(raw ~78 行「when true, skip
/// assistant messages that already have item IDs」):`conversation` 续接
/// 模式下,会话上下文中已存在的 item 原样重发会导致 API 返回
/// "Duplicate item found"。上游对带 itemId 的 assistant text(raw ~235)、
/// tool-call(~278,不区分 `store`)与 reasoning(~546)生效;
/// provider-executed tool-result(~449)与 compaction(~646)两个落点
/// 在首版转换器里本就告警跳过,无行为差异。
///
/// [providerOptionsName] 逐字对齐上游同名参数(`convert-to-openai-
/// responses-input.ts` ~73 行):由调用方按 `resolveOpenAiProviderOptionsName`
/// (provider 名含 `'azure'` 时为 `'azure'`,否则为 `'openai'`)算出后传入,
/// 决定 part 级 `providerOptions`(itemId/reasoningEncryptedContent 等)与
/// 文件引用(`FileDataReference.reference`)读取哪个 provider key。上游对
/// 该 key 的读取**不做**回退到 `'openai'` 的兜底,本函数同样不做。
OpenAiResponsesInputResult convertToOpenAiResponsesInput({
  required LanguageModelPrompt prompt,
  required SystemMessageMode systemMessageMode,
  required bool store,
  List<LanguageModelTool>? tools,
  bool hasConversation = false,
  bool hasPreviousResponseId = false,
  String providerOptionsName = 'openai',
}) {
  final input = <JsonObject>[];
  final warnings = <Warning>[];
  final mcpApprovalIds = <String>{};
  final mcpApprovalToolCallIds = <String>{};
  final replayedMcpApprovalIds = <String>{};
  final providerTools = _OpenAiResponsesProviderTools.from(tools);

  for (final message in prompt) {
    switch (message) {
      case SystemMessage(:final content):
        switch (systemMessageMode) {
          case SystemMessageMode.system:
            input.add(<String, Object?>{
              'role': 'system',
              'content': content,
            });
          case SystemMessageMode.developer:
            input.add(<String, Object?>{
              'role': 'developer',
              'content': content,
            });
          case SystemMessageMode.remove:
            warnings.add(
              const OtherWarning(
                'system messages are removed for this model',
              ),
            );
        }

      case UserMessage(:final content):
        input.add(<String, Object?>{
          'role': 'user',
          'content':
              _convertUserContent(content, warnings, providerOptionsName),
        });

      case AssistantMessage(:final content):
        _collectMcpApprovalIds(
          content,
          mcpApprovalIds,
          mcpApprovalToolCallIds,
        );
        _convertAssistantContent(
          content,
          store,
          hasConversation,
          hasPreviousResponseId,
          providerOptionsName,
          mcpApprovalIds,
          mcpApprovalToolCallIds,
          replayedMcpApprovalIds,
          providerTools,
          input,
          warnings,
        );

      case ToolMessage(:final content):
        _convertToolContent(
          content,
          store,
          hasConversation,
          hasPreviousResponseId,
          providerOptionsName,
          mcpApprovalIds,
          replayedMcpApprovalIds,
          providerTools,
          input,
          warnings,
        );
    }
  }

  // `store==false` 时,缺 `encrypted_content` 的 reasoning item 无法被
  // API 接受为续接上下文(逐字对齐 raw ~980 行「when store is false,
  // remove reasoning parts without encrypted content」):整体过滤掉这些
  // item 并追加一条告警,而非让请求体带着无效 item 发出去。
  var filteredInput = input;
  if (!store &&
      input.any(
        (item) =>
            item['type'] == 'reasoning' && item['encrypted_content'] == null,
      )) {
    warnings.add(
      const OtherWarning(
        'Reasoning parts without encrypted content are not supported '
        'when store is false. Skipping reasoning parts.',
      ),
    );
    filteredInput = input
        .where(
          (item) =>
              item['type'] != 'reasoning' || item['encrypted_content'] != null,
        )
        .toList();
  }

  return OpenAiResponsesInputResult(input: filteredInput, warnings: warnings);
}

List<JsonObject> _convertUserContent(
  List<UserContentPart> content,
  List<Warning> warnings,
  String providerOptionsName,
) {
  final parts = <JsonObject>[];
  for (var index = 0; index < content.length; index++) {
    final part = content[index];
    switch (part) {
      case TextPart(:final text):
        parts.add(<String, Object?>{'type': 'input_text', 'text': text});
      case FilePart():
        // 完整 file part 映射(data URI/reference/pdf 等)见 11.5。
        // `index` 是该 part 在 user 消息 `content` 数组里的下标(逐字
        // 对齐上游 `content.map((part, index) => ...)`,raw ~124 行),
        // 供无文件名 PDF part 兜底命名使用。
        parts.add(
          _convertUserFilePart(part, index, warnings, providerOptionsName),
        );
    }
  }
  return parts;
}

JsonObject _convertAssistantTextItem(String text, String? id) =>
    <String, Object?>{
      'role': 'assistant',
      'content': <JsonObject>[
        <String, Object?>{'type': 'output_text', 'text': text},
      ],
      if (id != null) 'id': id,
    };

void _collectMcpApprovalIds(
  List<AssistantContentPart> content,
  Set<String> mcpApprovalIds,
  Set<String> mcpApprovalToolCallIds,
) {
  final mcpToolCallIds = <String>{};
  for (final part in content) {
    if (part
        case ToolCallPart(
          :final toolCallId,
          :final toolName,
          :final providerExecuted,
        ) when providerExecuted == true && _isMcpToolName(toolName)) {
      mcpToolCallIds.add(toolCallId);
    }
  }
  if (mcpToolCallIds.isEmpty) {
    return;
  }
  for (final part in content) {
    if (part case ToolApprovalRequestPart(:final approvalId, :final toolCallId)
        when mcpToolCallIds.contains(toolCallId)) {
      mcpApprovalIds.add(approvalId);
      mcpApprovalToolCallIds.add(toolCallId);
    }
  }
}

bool _isMcpToolName(String toolName) => toolName.startsWith('mcp.');

String? _providerItemId(
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  final itemId = providerOptions?[providerOptionsName]?['itemId'];
  return itemId is String ? itemId : null;
}

final class _OpenAiResponsesProviderTools {
  const _OpenAiResponsesProviderTools({
    required this.shellToolName,
    required this.applyPatchToolName,
    required this.toolSearchToolName,
    required this.customToolNames,
  });

  factory _OpenAiResponsesProviderTools.from(List<LanguageModelTool>? tools) {
    String? shellToolName;
    String? applyPatchToolName;
    String? toolSearchToolName;
    final customToolNames = <String>{};

    for (final tool in tools ?? const <LanguageModelTool>[]) {
      if (tool case ProviderTool(:final id, :final name)) {
        switch (id) {
          case 'openai.shell':
            shellToolName = name;
          case 'openai.apply_patch':
            applyPatchToolName = name;
          case 'openai.tool_search':
            toolSearchToolName = name;
          case 'openai.custom':
            customToolNames.add(name);
        }
      }
    }

    return _OpenAiResponsesProviderTools(
      shellToolName: shellToolName,
      applyPatchToolName: applyPatchToolName,
      toolSearchToolName: toolSearchToolName,
      customToolNames: customToolNames,
    );
  }

  final String? shellToolName;
  final String? applyPatchToolName;
  final String? toolSearchToolName;
  final Set<String> customToolNames;

  bool isToolSearch(String toolName) => toolName == toolSearchToolName;

  bool isShell(String toolName) => toolName == shellToolName;

  bool isApplyPatch(String toolName) => toolName == applyPatchToolName;

  bool isCustom(String toolName) => customToolNames.contains(toolName);

  String? callTypeForToolName(String toolName) {
    if (isToolSearch(toolName)) {
      return 'tool_search_call';
    }
    if (isShell(toolName)) {
      return 'shell_call';
    }
    if (isApplyPatch(toolName)) {
      return 'apply_patch_call';
    }
    if (isCustom(toolName)) {
      return 'custom_tool_call';
    }
    return null;
  }

  String? outputTypeForToolName(String toolName) {
    if (isToolSearch(toolName)) {
      return 'tool_search_output';
    }
    if (isShell(toolName)) {
      return 'shell_call_output';
    }
    if (isApplyPatch(toolName)) {
      return 'apply_patch_call_output';
    }
    if (isCustom(toolName)) {
      return 'custom_tool_call_output';
    }
    return null;
  }
}

JsonObject? _convertProviderDefinedToolCall(
  ToolCallPart part,
  String? itemId,
  _OpenAiResponsesProviderTools providerTools,
  List<Warning> warnings,
) {
  final input = part.input;

  if (providerTools.isToolSearch(part.toolName)) {
    final object = _jsonObjectInput(input, part.toolName, warnings);
    if (object == null) {
      return null;
    }
    final callId = object['call_id'] as String?;
    return <String, Object?>{
      'type': 'tool_search_call',
      'id': itemId ?? part.toolCallId,
      'execution': callId == null ? 'server' : 'client',
      'call_id': callId,
      'status': 'completed',
      'arguments': object['arguments'],
    };
  }

  if (providerTools.isShell(part.toolName)) {
    final object = _jsonObjectInput(input, part.toolName, warnings);
    final action = object?['action'];
    if (object == null || action is! JsonObject) {
      _addProviderToolInputWarning(part.toolName, warnings);
      return null;
    }
    return <String, Object?>{
      'type': 'shell_call',
      'id': itemId ?? part.toolCallId,
      'call_id': part.toolCallId,
      'status': 'completed',
      'action': <String, Object?>{
        'commands': action['commands'],
        'timeout_ms': action['timeoutMs'],
        'max_output_length': action['maxOutputLength'],
      }..removeWhere((_, value) => value == null),
    };
  }

  if (providerTools.isApplyPatch(part.toolName)) {
    final object = _jsonObjectInput(input, part.toolName, warnings);
    if (object == null) {
      return null;
    }
    return <String, Object?>{
      'type': 'apply_patch_call',
      'id': itemId ?? part.toolCallId,
      'call_id': object['callId'] as String? ?? part.toolCallId,
      'status': 'completed',
      'operation': object['operation'],
    };
  }

  if (providerTools.isCustom(part.toolName)) {
    return <String, Object?>{
      'type': 'custom_tool_call',
      'call_id': part.toolCallId,
      'name': part.toolName,
      'input': input is String ? input : jsonEncode(input),
      if (itemId != null) 'id': itemId,
    };
  }

  return null;
}

JsonObject? _convertProviderDefinedToolResult(
  ToolResultPart part,
  _OpenAiResponsesProviderTools providerTools,
  String providerOptionsName,
  List<Warning> warnings, {
  required bool executionFromAssistant,
}) {
  if (providerTools.isToolSearch(part.toolName)) {
    final output = _toolResultJsonObject(part.output, part.toolName, warnings);
    if (output == null) {
      return null;
    }
    final itemId = _providerItemId(part.providerOptions, providerOptionsName);
    return <String, Object?>{
      'type': 'tool_search_output',
      if (itemId != null) 'id': itemId,
      'execution': executionFromAssistant ? 'server' : 'client',
      'call_id': executionFromAssistant ? null : part.toolCallId,
      'status': 'completed',
      'tools': output['tools'],
    };
  }

  if (providerTools.isShell(part.toolName)) {
    final output = _toolResultJsonObject(part.output, part.toolName, warnings);
    final items = output?['output'];
    if (output == null || items is! List<Object?>) {
      _addProviderToolOutputWarning(part.toolName, warnings);
      return null;
    }
    final convertedItems = <JsonObject>[];
    for (final entry in items) {
      if (entry is! JsonObject) {
        _addProviderToolOutputWarning(part.toolName, warnings);
        return null;
      }
      final outcome = entry['outcome'];
      if (outcome is! JsonObject) {
        _addProviderToolOutputWarning(part.toolName, warnings);
        return null;
      }
      convertedItems.add(<String, Object?>{
        'stdout': entry['stdout'],
        'stderr': entry['stderr'],
        'outcome': outcome['type'] == 'exit'
            ? <String, Object?>{
                'type': 'exit',
                'exit_code': outcome['exitCode'],
              }
            : <String, Object?>{'type': 'timeout'},
      });
    }
    return <String, Object?>{
      'type': 'shell_call_output',
      'call_id': part.toolCallId,
      'max_output_length': output['maxOutputLength'],
      'output': convertedItems,
    }..removeWhere((_, value) => value == null);
  }

  if (providerTools.isApplyPatch(part.toolName)) {
    final output = _toolResultJsonObject(part.output, part.toolName, warnings);
    if (output == null) {
      return null;
    }
    return <String, Object?>{
      'type': 'apply_patch_call_output',
      'call_id': part.toolCallId,
      'status': output['status'],
      'output': output['output'],
    }..removeWhere((_, value) => value == null);
  }

  if (providerTools.isCustom(part.toolName)) {
    final output = _convertToolResultOutput(part.output, warnings);
    if (output == null) {
      return null;
    }
    return <String, Object?>{
      'type': 'custom_tool_call_output',
      'call_id': part.toolCallId,
      'output': output,
    };
  }

  return null;
}

JsonObject? _jsonObjectInput(
  JsonValue value,
  String toolName,
  List<Warning> warnings,
) {
  if (value is JsonObject) {
    return value;
  }
  _addProviderToolInputWarning(toolName, warnings);
  return null;
}

JsonObject? _toolResultJsonObject(
  ToolResultOutput output,
  String toolName,
  List<Warning> warnings,
) {
  final value = switch (output) {
    ToolResultJson(:final value) => value,
    ToolResultErrorJson(:final value) => value,
    _ => null,
  };
  if (value is JsonObject) {
    return value;
  }
  _addProviderToolOutputWarning(toolName, warnings);
  return null;
}

void _addProviderToolInputWarning(String toolName, List<Warning> warnings) {
  warnings.add(
    OtherWarning(
      'OpenAI provider tool $toolName input must be a JSON object; skipping',
    ),
  );
}

void _addProviderToolOutputWarning(String toolName, List<Warning> warnings) {
  warnings.add(
    OtherWarning(
      'OpenAI provider tool $toolName result must be a JSON object; skipping',
    ),
  );
}

void _convertAssistantContent(
  List<AssistantContentPart> content,
  bool store,
  bool hasConversation,
  bool hasPreviousResponseId,
  String providerOptionsName,
  Set<String> mcpApprovalIds,
  Set<String> mcpApprovalToolCallIds,
  Set<String> replayedMcpApprovalIds,
  _OpenAiResponsesProviderTools providerTools,
  List<JsonObject> input,
  List<Warning> warnings,
) {
  // itemId → 已推入 input 的 reasoning wire item(逐字对齐 raw ~220 行
  // `reasoningMessages`,per-assistant-message 作用域):同一 reasoning
  // item 的多个 summary part 共享一个 itemId,只应在 input 里产生一个
  // wire item,后续 part 原地追加 summary 并覆盖 encrypted_content(見
  // 11.7 扩展:多 summary part 合并)。
  final reasoningMessages = <String, JsonObject>{};
  final referencedProviderItemIds = <String>{};

  for (final part in content) {
    switch (part) {
      case TextPart(:final text, :final providerOptions):
        final itemId =
            providerOptions?[providerOptionsName]?['itemId'] as String?;

        // 续接 conversation 时,会话上下文中已存在的 assistant text item
        // 原样重发(哪怕是 item_reference)会导致 API 返回
        // "Duplicate item found"——逐字对齐上游 raw ~234-237 行
        // (`hasConversation && id != null` 时整项跳过)。
        if (hasConversation && itemId != null) {
          continue;
        }

        if (store && itemId != null) {
          input.add(<String, Object?>{
            'type': 'item_reference',
            'id': itemId,
          });
        } else {
          input.add(_convertAssistantTextItem(text, itemId));
        }

      case ToolCallPart(:final providerExecuted, :final providerOptions):
        final itemId = _providerItemId(providerOptions, providerOptionsName);
        final providerDefinedCallType =
            providerTools.callTypeForToolName(part.toolName);

        if (providerTools.isToolSearch(part.toolName)) {
          if (hasPreviousResponseId && store && itemId != null) {
            continue;
          }
          if (hasConversation && itemId != null) {
            continue;
          }
          if (store && itemId != null) {
            input.add(<String, Object?>{
              'type': 'item_reference',
              'id': itemId,
            });
          } else {
            final item = _convertProviderDefinedToolCall(
              part,
              itemId,
              providerTools,
              warnings,
            );
            if (item != null) {
              input.add(item);
            }
          }
          continue;
        }

        if (providerExecuted ?? false) {
          if (_isMcpToolName(part.toolName)) {
            if (mcpApprovalToolCallIds.contains(part.toolCallId)) {
              continue;
            }
            // MCP call 是 provider 拥有的 Responses output item。手动回放
            // responseMessages 时,store:true 引用已存储 item;store:false
            // 没有服务端存储可引用,必须重放 provider metadata 中保留的原始
            // mcp_call item。
            if (hasConversation || hasPreviousResponseId) {
              continue;
            }
            if (store &&
                itemId != null &&
                referencedProviderItemIds.add(itemId)) {
              input.add(<String, Object?>{
                'type': 'item_reference',
                'id': itemId,
              });
            }
            if (!store) {
              _addOpenAiProviderItem(
                input,
                referencedProviderItemIds,
                _openAiProviderItem(
                  providerOptions,
                  providerOptionsName,
                  'mcp_call',
                ),
              );
            }
            continue;
          }
          if (providerDefinedCallType != null) {
            if (hasConversation || hasPreviousResponseId) {
              continue;
            }
            if (store &&
                itemId != null &&
                referencedProviderItemIds.add(itemId)) {
              input.add(<String, Object?>{
                'type': 'item_reference',
                'id': itemId,
              });
            }
            if (!store) {
              final item = _openAiProviderItem(
                    providerOptions,
                    providerOptionsName,
                    providerDefinedCallType,
                  ) ??
                  _convertProviderDefinedToolCall(
                    part,
                    itemId,
                    providerTools,
                    warnings,
                  );
              _addOpenAiProviderItem(
                input,
                referencedProviderItemIds,
                item,
              );
            }
            continue;
          }
          warnings.add(
            const OtherWarning(
              'provider-executed tool calls are not supported yet in '
              'the responses input converter; skipping',
            ),
          );
          continue;
        }

        // 续接 conversation 时,会话上下文中已存在的 function-call item
        // 原样重发会导致 "Duplicate item found"——逐字对齐上游 raw ~278
        // 行(`hasConversation && id != null` 时整项跳过,不区分
        // `store`)。
        if (hasConversation && itemId != null) {
          continue;
        }

        // 续接 previousResponseId 时,该响应链上已产生的 function-call
        // item 已被 OpenAI 前置,原样重发会导致 API 返回
        // "No tool call found for function call output with call_id"
        // (call_id 与 item id 无法配对)——逐字对齐上游 raw ~324-328 行
        // (`hasPreviousResponseId && store && id != null` 时整项跳过,
        // 不发 item_reference,也不内联重建)。
        if (hasPreviousResponseId && store && itemId != null) {
          continue;
        }

        if (providerDefinedCallType != null) {
          if (store && itemId != null) {
            input.add(<String, Object?>{
              'type': 'item_reference',
              'id': itemId,
            });
          } else {
            final item = _convertProviderDefinedToolCall(
              part,
              itemId,
              providerTools,
              warnings,
            );
            if (item != null) {
              input.add(item);
            }
          }
          continue;
        }

        // `part.input` 为 null(如无参工具调用)时兜底为空对象,逐字对齐
        // 上游 `serializeToolCallArguments`(`convert-to-openai-responses-
        // input.ts` ~40-42 行:`input === undefined ? {} : input`)——不
        // 兜底会把 `jsonEncode(null)` 的字面量 `"null"` 当作 arguments
        // 发给 API。chat 侧 `convert_messages.dart:240` 已是同款兜底。
        input.add(<String, Object?>{
          'type': 'function_call',
          'call_id': part.toolCallId,
          'name': part.toolName,
          'arguments': jsonEncode(part.input ?? const <String, Object?>{}),
        });

      case ToolResultPart(:final providerOptions):
        final itemId = _providerItemId(providerOptions, providerOptionsName);
        final providerDefinedOutputType =
            providerTools.outputTypeForToolName(part.toolName);
        final mcpItem = _openAiProviderItem(
          providerOptions,
          providerOptionsName,
          'mcp_call',
        );
        if (_isMcpToolName(part.toolName) &&
            (itemId != null || mcpItem != null)) {
          if (hasConversation || hasPreviousResponseId) {
            continue;
          }
          if (store &&
              itemId != null &&
              referencedProviderItemIds.add(itemId)) {
            input.add(<String, Object?>{
              'type': 'item_reference',
              'id': itemId,
            });
          }
          if (!store) {
            _addOpenAiProviderItem(input, referencedProviderItemIds, mcpItem);
          }
          continue;
        }

        if (providerDefinedOutputType != null) {
          if (hasConversation || hasPreviousResponseId) {
            continue;
          }
          final providerItem = _openAiProviderItem(
            providerOptions,
            providerOptionsName,
            providerDefinedOutputType,
          );
          if (store &&
              itemId != null &&
              referencedProviderItemIds.add(itemId)) {
            input.add(<String, Object?>{
              'type': 'item_reference',
              'id': itemId,
            });
          } else if (!store) {
            final item = providerItem ??
                _convertProviderDefinedToolResult(
                  part,
                  providerTools,
                  providerOptionsName,
                  warnings,
                  executionFromAssistant: true,
                );
            _addOpenAiProviderItem(
              input,
              referencedProviderItemIds,
              item,
            );
          }
          continue;
        }

        // 首版不支持 assistant 侧通用 provider-executed tool-result 回传;
        // MCP tool-result 是同一个 provider-owned output item,上方已用
        // item_reference 覆盖并去重。
        warnings.add(
          OtherWarning(
            'Results for OpenAI tool ${part.toolName} are not sent to '
            'the API in this version',
          ),
        );

      case ToolApprovalRequestPart(:final approvalId, :final providerOptions):
        if (!mcpApprovalIds.contains(part.approvalId)) {
          warnings.add(
            const OtherWarning(
              'tool approval requests are handled locally and are not sent '
              'to the OpenAI Responses API',
            ),
          );
          continue;
        }
        if (hasConversation || hasPreviousResponseId || store) {
          continue;
        }
        final item = _openAiProviderItem(
          providerOptions,
          providerOptionsName,
          'mcp_approval_request',
        );
        if (_mcpApprovalId(item) == approvalId) {
          input.add(item!);
          replayedMcpApprovalIds.add(approvalId);
        }

      case ReasoningPart():
        // reasoning item_reference/encrypted_content 分支见 11.7。
        _convertReasoningPart(
          part,
          store,
          hasConversation,
          hasPreviousResponseId,
          providerOptionsName,
          input,
          warnings,
          reasoningMessages,
        );

      case CustomPart(:final kind, :final providerOptions):
        final item = _openAiMcpListToolsItem(
          kind,
          providerOptions,
          providerOptionsName,
        );
        if (item != null) {
          if (!hasConversation && !hasPreviousResponseId) {
            input.add(item);
          }
          continue;
        }

        // 首版 responses input 转换不支持通用 provider 自定义 part 回传;
        // 告警跳过而非静默丢弃或 throw,保留未来扩展空间(设计文档 §1
        // 非目标)。OpenAI MCP list-tools 是 provider 私有上下文缓存项,
        // 在上面的分支按原始 wire item 窄口径回放。
        warnings.add(
          const OtherWarning(
            'assistant file/custom content parts are not supported yet '
            'in the responses input converter; skipping',
          ),
        );

      case FilePart():
      case ReasoningFilePart():
        // 首版 responses input 转换不支持 assistant 侧文件/以文件承载的
        // 推理内容回传;告警跳过而非静默丢弃或 throw,保留未来扩展空间
        // (设计文档 §1 非目标)。
        warnings.add(
          const OtherWarning(
            'assistant file/custom content parts are not supported yet '
            'in the responses input converter; skipping',
          ),
        );
    }
  }
}

JsonObject? _openAiMcpListToolsItem(
  String kind,
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  if (kind != _openAiMcpListToolsKind) {
    return null;
  }

  final item = providerOptions?[providerOptionsName]?['item'];
  if (item is Map<String, Object?> && item['type'] == 'mcp_list_tools') {
    return item;
  }
  return null;
}

JsonObject? _openAiProviderItem(
  ProviderOptions? providerOptions,
  String providerOptionsName,
  String type,
) {
  final item = providerOptions?[providerOptionsName]?['item'];
  if (item is Map<String, Object?> && item['type'] == type) {
    return item;
  }
  return null;
}

void _addOpenAiProviderItem(
  List<JsonObject> input,
  Set<String> referencedItemIds,
  JsonObject? item,
) {
  if (item == null) {
    return;
  }
  final id = item['id'];
  if (id is String && !referencedItemIds.add(id)) {
    return;
  }
  input.add(item);
}

String? _mcpApprovalId(JsonObject? item) {
  final approvalRequestId = item?['approval_request_id'];
  if (approvalRequestId is String) {
    return approvalRequestId;
  }
  final id = item?['id'];
  return id is String ? id : null;
}

void _convertToolContent(
  List<ToolContentPart> content,
  bool store,
  bool hasConversation,
  bool hasPreviousResponseId,
  String providerOptionsName,
  Set<String> mcpApprovalIds,
  Set<String> replayedMcpApprovalIds,
  _OpenAiResponsesProviderTools providerTools,
  List<JsonObject> input,
  List<Warning> warnings,
) {
  for (final part in content) {
    switch (part) {
      case ToolResultPart(:final toolCallId, :final output):
        final providerDefinedOutputType =
            providerTools.outputTypeForToolName(part.toolName);
        if (providerDefinedOutputType != null) {
          final providerDefinedResult = _convertProviderDefinedToolResult(
            part,
            providerTools,
            providerOptionsName,
            warnings,
            executionFromAssistant: false,
          );
          if (providerDefinedResult != null) {
            input.add(providerDefinedResult);
          }
          continue;
        }

        final contentValue = _convertToolResultOutput(output, warnings);
        if (contentValue == null) {
          continue;
        }
        input.add(<String, Object?>{
          'type': 'function_call_output',
          'call_id': toolCallId,
          'output': contentValue,
        });

      case ToolApprovalResponsePart(
          :final approvalId,
          :final approved,
          :final reason,
          :final providerOptions,
        ):
        final hasStoredApprovalContext =
            hasConversation || hasPreviousResponseId;
        final hasReplayedApprovalContext =
            replayedMcpApprovalIds.contains(approvalId);
        final hasMcpApprovalContext = mcpApprovalIds.contains(approvalId);
        final providerItemId = _providerItemId(
          providerOptions,
          providerOptionsName,
        );
        final hasMcpApprovalMetadata = providerItemId != null;
        if (!hasMcpApprovalContext && !hasMcpApprovalMetadata) {
          warnings.add(
            const OtherWarning(
              'tool approval responses without a matching OpenAI MCP '
              'approval request are not sent to the OpenAI Responses API',
            ),
          );
          continue;
        }
        if (!store &&
            !hasStoredApprovalContext &&
            !hasReplayedApprovalContext) {
          warnings.add(
            const OtherWarning(
              'OpenAI MCP approval responses require a replayed approval '
              'request item or a server-side continuation when store is false',
            ),
          );
          continue;
        }
        if (store && !hasStoredApprovalContext) {
          input.add(<String, Object?>{
            'type': 'item_reference',
            'id': providerItemId ?? approvalId,
          });
        }
        input.add(<String, Object?>{
          'type': 'mcp_approval_response',
          'approval_request_id': approvalId,
          'approve': approved,
          'reason': reason,
        }..removeWhere((_, value) => value == null));
    }
  }
}

Object? _convertToolResultOutput(
  ToolResultOutput output,
  List<Warning> warnings,
) {
  return switch (output) {
    ToolResultText(:final value) => value,
    ToolResultErrorText(:final value) => value,
    ToolResultExecutionDenied(:final reason) =>
      reason ?? 'Tool call execution denied.',
    ToolResultJson(:final value) => jsonEncode(value),
    ToolResultErrorJson(:final value) => jsonEncode(value),
    ToolResultContentOutput(:final items) => items
        .map((item) => switch (item) {
              ToolResultTextItem(:final text) => <String, Object?>{
                  'type': 'input_text',
                  'text': text,
                },
              ToolResultFileItem() => _convertToolResultFileItem(
                  item,
                  warnings,
                ),
              ToolResultCustomItem() => null,
            })
        .whereType<JsonObject>()
        .toList(),
  };
}

String _resolveTopLevelMediaType(String mediaType) {
  final slashIndex = mediaType.indexOf('/');
  return slashIndex == -1 ? mediaType : mediaType.substring(0, slashIndex);
}

JsonObject _convertUserFilePart(
  FilePart part,
  int index,
  List<Warning> warnings,
  String providerOptionsName,
) {
  final data = part.data;

  if (data is FileDataText) {
    throw const UnsupportedFunctionalityError(
      functionality: 'text file parts',
    );
  }

  // `input_image` 的 `detail` 字段逐字对齐上游 `part.providerOptions?.
  // [providerOptionsName]?.imageDetail`(raw ~141-144 行 reference 分支、
  // ~172-175 行 data/url 分支):两个分支读取方式一致,故在此统一算出,
  // 值为 null 时不写该字段(与 `<String, Object?>{...}` 字面量省略 null
  // 值键的既有写法一致,不发送空 `detail`)。
  final imageDetail =
      part.providerOptions?[providerOptionsName]?['imageDetail'] as String?;

  if (data is FileDataReference) {
    final fileId = resolveProviderReference(
      reference: data.reference,
      provider: providerOptionsName,
    );
    return _resolveTopLevelMediaType(part.mediaType) == 'image'
        ? <String, Object?>{
            'type': 'input_image',
            'file_id': fileId,
            if (imageDetail != null) 'detail': imageDetail,
          }
        : <String, Object?>{'type': 'input_file', 'file_id': fileId};
  }

  final topLevel = _resolveTopLevelMediaType(part.mediaType);

  if (topLevel == 'image') {
    final imageUrl = switch (data) {
      FileDataUrl(:final url) => url.toString(),
      FileDataBytes(:final bytes) =>
        'data:${part.mediaType};base64,${base64Encode(bytes)}',
      FileDataBase64(:final base64) => 'data:${part.mediaType};base64,$base64',
      _ => throw StateError('unreachable: text/reference handled above'),
    };
    return <String, Object?>{
      'type': 'input_image',
      'image_url': imageUrl,
      if (imageDetail != null) 'detail': imageDetail,
    };
  }

  if (data is FileDataUrl) {
    return <String, Object?>{
      'type': 'input_file',
      'file_url': data.url.toString(),
    };
  }

  if (part.mediaType != 'application/pdf') {
    throw UnsupportedFunctionalityError(
      functionality: 'file part media type ${part.mediaType}',
    );
  }

  final base64Data = switch (data) {
    FileDataBytes(:final bytes) => base64Encode(bytes),
    FileDataBase64(:final base64) => base64,
    _ => throw StateError('unreachable: url/text/reference handled above'),
  };

  return <String, Object?>{
    'type': 'input_file',
    // 无文件名时兜底为 `part-$index.pdf`(逐字对齐上游 raw ~200-204 行
    // `part.filename ?? (fullMediaType === 'application/pdf' ?
    // \`part-${index}.pdf\` : \`part-${index}\`)`——本分支已确认
    // mediaType 恒为 `application/pdf`,故只需 pdf 分支;chat 侧
    // `convert_messages.dart:202` 已是同款 `part-$index.pdf`)。
    'filename': part.filename ?? 'part-$index.pdf',
    'file_data': 'data:${part.mediaType};base64,$base64Data',
  };
}

JsonObject? _convertToolResultFileItem(
  ToolResultFileItem item,
  List<Warning> warnings,
) {
  final topLevel = _resolveTopLevelMediaType(item.mediaType);
  final data = item.data;

  if (data is FileDataUrl) {
    return topLevel == 'image'
        ? <String, Object?>{
            'type': 'input_image',
            'image_url': data.url.toString(),
          }
        : <String, Object?>{
            'type': 'input_file',
            'file_url': data.url.toString(),
          };
  }

  String? base64Data;
  if (data is FileDataBytes) {
    base64Data = base64Encode(data.bytes);
  } else if (data is FileDataBase64) {
    base64Data = data.base64;
  }

  if (base64Data == null) {
    warnings.add(
      OtherWarning(
        'unsupported tool content part data type for ${item.mediaType}',
      ),
    );
    return null;
  }

  if (topLevel == 'image') {
    return <String, Object?>{
      'type': 'input_image',
      'image_url': 'data:${item.mediaType};base64,$base64Data',
    };
  }

  return <String, Object?>{
    'type': 'input_file',
    'filename': item.filename ?? 'data',
    'file_data': 'data:${item.mediaType};base64,$base64Data',
  };
}

void _convertReasoningPart(
  ReasoningPart part,
  bool store,
  bool hasConversation,
  bool hasPreviousResponseId,
  String providerOptionsName,
  List<JsonObject> input,
  List<Warning> warnings,
  Map<String, JsonObject> reasoningMessages,
) {
  final providerOptions = part.providerOptions?[providerOptionsName];
  final itemId = providerOptions?['itemId'] as String?;
  final encryptedContent =
      providerOptions?['reasoningEncryptedContent'] as String?;

  // 续接 conversation/previousResponseId 时,会话上下文或被续接响应链上
  // 的 reasoning item 已在服务端,原样重发(哪怕是 item_reference)会
  // 导致 item 重复——逐字对齐上游 raw ~545-550 行
  // (`(hasConversation || hasPreviousResponseId) && reasoningId != null`
  // 时整个 part 跳过,不区分 store)。
  if ((hasConversation || hasPreviousResponseId) && itemId != null) {
    return;
  }

  if (itemId != null) {
    final existing = reasoningMessages[itemId];

    if (store) {
      // 首个共享该 itemId 的 part 才推入 `item_reference` 并登记占位
      // item(标记该 id 已用);同一 itemId 的后续 summary part(逐字
      // 对齐 raw ~555-567 行)不再重复推入引用。
      if (existing == null) {
        input.add(<String, Object?>{'type': 'item_reference', 'id': itemId});
        reasoningMessages[itemId] = <String, Object?>{
          'type': 'reasoning',
          'id': itemId,
          'summary': <JsonObject>[],
        };
      }
      return;
    }

    // 用可变列表存放 summary part:即便当前 part 文本为空(常见于首个
    // reasoning part,内容随后续 part 到达),这个列表后续仍可能通过
    // `existing['summary']!.addAll(...)` 原地追加——用 `const <JsonObject>[]`
    // 会导致该 `addAll` 抛出 `UnsupportedError`(修复前的 bug:store:false
    // 且首个 part 文本为空、同 itemId 出现第二个 part 时必现)。
    final summaryParts = part.text.isEmpty
        ? <JsonObject>[]
        : <JsonObject>[
            <String, Object?>{'type': 'summary_text', 'text': part.text},
          ];

    if (existing == null) {
      // 同一 itemId 下第一个到达的 summary part:新建 wire item 并推入
      // input——后续共享该 itemId 的 part 会原地修改这个 map 引用持有的
      // 同一个对象(而非再推入新 item),使 input 里的元素与之保持同步
      // (逐字对齐 raw ~586-602 行:`input.push(reasoningMessages[id])`
      // 与后续 `reasoningMessage.summary.push(...)` 操作同一引用)。
      final reasoningItem = <String, Object?>{
        'type': 'reasoning',
        'id': itemId,
        'encrypted_content': encryptedContent,
        'summary': summaryParts,
      };
      reasoningMessages[itemId] = reasoningItem;
      input.add(reasoningItem);
    } else if (part.text.isEmpty) {
      // 已存在同 itemId 的 wire item,但当前 part 文本为空:逐字对齐上游
      // raw ~579-584 行(`else if (reasoningMessage !== undefined)` 分支)
      // ——不追加空 summary_text,只告警;`encrypted_content` 仍按下方
      // 逻辑覆盖(上游同一分支落地后仍会执行 `encrypted_content` 更新)。
      warnings.add(
        OtherWarning(
          'Cannot append empty reasoning part to existing reasoning '
          'sequence. Skipping reasoning part with text: ${part.text}',
        ),
      );
      if (encryptedContent != null) {
        existing['encrypted_content'] = encryptedContent;
      }
    } else {
      (existing['summary']! as List<JsonObject>).addAll(summaryParts);
      // 只有非 null 的 encrypted_content 才覆盖:`encrypted_content` 只
      // 在 reasoning item 的最后一个 summary part(`output_item.done`)
      // 才就位,中途 part 通常为 null,不应把已写入的真实值抹掉(逐字
      // 对齐 raw ~598-601 行)。
      if (encryptedContent != null) {
        existing['encrypted_content'] = encryptedContent;
      }
    }
    return;
  }

  if (encryptedContent != null) {
    final summary = part.text.isEmpty
        ? const <JsonObject>[]
        : <JsonObject>[
            <String, Object?>{'type': 'summary_text', 'text': part.text},
          ];
    input.add(<String, Object?>{
      'type': 'reasoning',
      'encrypted_content': encryptedContent,
      'summary': summary,
    });
    return;
  }

  warnings.add(
    OtherWarning(
      'Non-OpenAI reasoning parts are not supported. Skipping reasoning '
      'part with text: ${part.text}',
    ),
  );
}
