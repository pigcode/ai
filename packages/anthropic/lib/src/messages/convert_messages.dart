import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import 'cache_control.dart';

/// server 侧工具白名单(报告 07 §6.1/§6.2 + 报告 09 §5;决策摘要"无
/// toolName 别名映射"——响应侧 toolName 直接用 wire 名)。子工具名
/// (`bash_code_execution`/`text_editor_code_execution`)解码侧已归一为
/// `code_execution`,不进本集合(spec §3.5,报告 09 §3.2a)。
const _serverToolNames = {
  'web_search',
  'web_fetch',
  'code_execution',
  'tool_search_tool_regex',
  'tool_search_tool_bm25',
  'advisor',
};

/// `web_search_tool_result` 成功结果数组每项的输出校验 schema(报告 07 §1.2
/// OutputSchema 字段表;回传前用 [validateTypes] 校验,报告 07 §6.2 :1092-1095)。
final _webSearchResultItemValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'type': {'const': 'web_search_result'},
      'url': {'type': 'string'},
      // title 可空且必填(报告 07 §1.2 OutputSchema :62,`.nullable()`)。
      'title': {
        'type': ['string', 'null'],
      },
      // pageAge 可空且必填(报告 07 §1.2 OutputSchema :63,`.nullable()`)。
      'pageAge': {
        'type': ['string', 'null'],
      },
      'encryptedContent': {'type': 'string'},
    },
    'required': ['type', 'url', 'title', 'pageAge', 'encryptedContent'],
  }),
);

/// `web_fetch_tool_result` 成功结果的输出校验 schema(报告 07 §1.4
/// OutputSchema 字段表;20250910/20260209 两版共用同一 schema,报告 07
/// §6.2 :1026-1032)。
final _webFetchResultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'type': {'const': 'web_fetch_result'},
      'url': {'type': 'string'},
      // retrievedAt 可空且必填(报告 07 §1.4 OutputSchema :102,`.nullable()`)。
      'retrievedAt': {
        'type': ['string', 'null'],
      },
      'content': {
        'type': 'object',
        'properties': {
          'type': {'const': 'document'},
          // title 可空且必填(报告 07 §1.4 OutputSchema :99)。
          'title': {
            'type': ['string', 'null'],
          },
          'citations': {
            'type': 'object',
            'properties': {
              'enabled': {'type': 'boolean'},
            },
          },
          'source': {
            'type': 'object',
            'properties': {
              'type': {'type': 'string'},
              'mediaType': {'type': 'string'},
              'data': {'type': 'string'},
            },
            'required': ['type', 'mediaType', 'data'],
          },
        },
        'required': ['type', 'title', 'source'],
      },
    },
    'required': ['type', 'url', 'retrievedAt', 'content'],
  }),
);

/// `code_execution_result` 成功结果输出校验(报告 09 §1.1/§1.2
/// OutputSchema;解码保留 snake_case `return_code`,重建时直接取用不做
/// camel→snake)。
final _codeExecutionResultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'type': {'const': 'code_execution_result'},
      'stdout': {'type': 'string'},
      'stderr': {'type': 'string'},
      'return_code': {'type': 'number'},
      'content': {'type': 'array'},
    },
    'required': ['type', 'stdout', 'stderr', 'return_code'],
  }),
);

/// `encrypted_code_execution_result` 成功结果输出校验(报告 09 §1.3
/// OutputSchema:20260120 专属,`encrypted_stdout` 同样保留 snake_case)。
final _encryptedCodeExecutionResultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'type': {'const': 'encrypted_code_execution_result'},
      'encrypted_stdout': {'type': 'string'},
      'stderr': {'type': 'string'},
      'return_code': {'type': 'number'},
      'content': {'type': 'array'},
    },
    'required': ['type', 'encrypted_stdout', 'stderr', 'return_code'],
  }),
);

/// bash 味透传块的两支 type(报告 09 §5.2 :974-985)——union 校验通过后用于
/// bash / text_editor 块路由;其余四支照上游 else 落 text_editor 块(:986-993)。
const _bashCodeExecutionContentTypes = {
  'bash_code_execution_result',
  'bash_code_execution_tool_result_error',
};

/// code_execution 20250825 输出七支判别 union 的完整校验(报告 09 §1.2
/// OutputSchema :8-68;`.nullable()` 字段 = 必填键 + `['xxx','null']`,
/// `.optional()` 字段 = 缺席键)。上游在透传臂前对整个 union 跑校验
/// (:956-959)——未知 type 抛错而非丢弃。
final _codeExecution20250825OutputValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'oneOf': [
      {
        'properties': {
          'type': {
            'enum': ['code_execution_result'],
          },
          'stdout': {'type': 'string'},
          'stderr': {'type': 'string'},
          'return_code': {'type': 'number'},
          'content': {'type': 'array'},
        },
        'required': ['type', 'stdout', 'stderr', 'return_code'],
      },
      {
        'properties': {
          'type': {
            'enum': ['bash_code_execution_result'],
          },
          'content': {'type': 'array'},
          'stdout': {'type': 'string'},
          'stderr': {'type': 'string'},
          'return_code': {'type': 'number'},
        },
        // content 必填无 default(报告 09 §1.2 :26-37,与
        // code_execution_result 的 optional 刻意不对称)。
        'required': ['type', 'content', 'stdout', 'stderr', 'return_code'],
      },
      {
        'properties': {
          'type': {
            'enum': ['bash_code_execution_tool_result_error'],
          },
          'error_code': {'type': 'string'},
        },
        'required': ['type', 'error_code'],
      },
      {
        'properties': {
          'type': {
            'enum': ['text_editor_code_execution_tool_result_error'],
          },
          'error_code': {'type': 'string'},
        },
        'required': ['type', 'error_code'],
      },
      {
        'properties': {
          'type': {
            'enum': ['text_editor_code_execution_view_result'],
          },
          'content': {'type': 'string'},
          'file_type': {'type': 'string'},
          'num_lines': {
            'type': ['number', 'null'],
          },
          'start_line': {
            'type': ['number', 'null'],
          },
          'total_lines': {
            'type': ['number', 'null'],
          },
        },
        'required': [
          'type',
          'content',
          'file_type',
          'num_lines',
          'start_line',
          'total_lines',
        ],
      },
      {
        'properties': {
          'type': {
            'enum': ['text_editor_code_execution_create_result'],
          },
          'is_file_update': {'type': 'boolean'},
        },
        'required': ['type', 'is_file_update'],
      },
      {
        'properties': {
          'type': {
            'enum': ['text_editor_code_execution_str_replace_result'],
          },
          'lines': {
            'type': ['array', 'null'],
          },
          'new_lines': {
            'type': ['number', 'null'],
          },
          'new_start': {
            'type': ['number', 'null'],
          },
          'old_lines': {
            'type': ['number', 'null'],
          },
          'old_start': {
            'type': ['number', 'null'],
          },
        },
        'required': [
          'type',
          'lines',
          'new_lines',
          'new_start',
          'old_lines',
          'old_start',
        ],
      },
    ],
  }),
);

/// tool_search 成功结果输出校验(报告 09 §1.5/§1.6 OutputSchema;SDK 侧
/// camelCase `toolName`,regex/bm25 两版共用同一 schema)。
final _toolSearchResultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'array',
    'items': {
      'type': 'object',
      'properties': {
        'type': {'const': 'tool_reference'},
        'toolName': {'type': 'string'},
      },
      'required': ['type', 'toolName'],
    },
  }),
);

/// advisor 结果输出校验(报告 09 §1.7 OutputSchema 三支判别 union,SDK 侧
/// camelCase `encryptedContent`/`errorCode`)。
final _advisorResultValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'oneOf': [
      {
        'type': 'object',
        'properties': {
          'type': {'const': 'advisor_result'},
          'text': {'type': 'string'},
        },
        'required': ['type', 'text'],
      },
      {
        'type': 'object',
        'properties': {
          'type': {'const': 'advisor_redacted_result'},
          'encryptedContent': {'type': 'string'},
        },
        'required': ['type', 'encryptedContent'],
      },
      {
        'type': 'object',
        'properties': {
          'type': {'const': 'advisor_tool_result_error'},
          'errorCode': {'type': 'string'},
        },
        'required': ['type', 'errorCode'],
      },
    ],
  }),
);

/// [convertToAnthropicMessages] 的返回值:顶层 system 块数组 + wire 消息
/// 数组 + 转换期推导出的 beta 集合 + 转换期告警。
final class AnthropicPromptResult {
  const AnthropicPromptResult({
    required this.system,
    required this.messages,
    required this.betas,
    required this.warnings,
  });

  /// 顶层 `system` 字段(内容块数组);prompt 无前导 system 块时为 null,
  /// 对应上游 undefined 序列化消失(报告 02 §2 :146-147)。
  final List<Map<String, Object?>>? system;

  /// 已转换的 Anthropic 消息数组,每个元素是一条消息的 JSON 形状。
  final List<Map<String, Object?>> messages;

  /// 转换期间推导出的 beta 标识集合(如中段 system 触发的
  /// `mid-conversation-system-2026-04-07`)。
  final Set<String> betas;

  /// 转换期间产生的告警(含 [CacheControlValidator] 的告警,单通道合并)。
  final List<Warning> warnings;
}

/// 把契约层 [LanguageModelPrompt] 转换为 Anthropic Messages API 的
/// `system` / `messages` 请求形状。
///
/// wire 语义对照报告 02(上游 `convert-to-anthropic-prompt.ts`):
///
/// - 连续同角色消息合并分块;user 与 tool 消息归入**同一个** user 块,
///   每块产出一条 Anthropic 消息(§1.2 :1247-1301);
/// - 第一个 system 块进顶层 `system` 数组;中段 system 块作为
///   `{'role': 'system'}` 消息发出并触发
///   `mid-conversation-system-2026-04-07` beta(§2 :146-154);
/// - cache_control 经 [cacheControlValidator] 读取(canonical
///   `'anthropic'` key),值非 null 才写入 JSON key。
///
/// [cacheControlValidator] 缺省时内部新建(上游 :86);其累积的 warnings
/// 在返回前统一合并进 [AnthropicPromptResult.warnings](warnings 单通道,
/// 模型层不再单独读取 validator)。
///
/// [sendReasoning] 控制 reasoning part 是否发回模型(assistant 块细化时
/// 使用)。
AnthropicPromptResult convertToAnthropicMessages({
  required LanguageModelPrompt prompt,
  required bool sendReasoning,
  CacheControlValidator? cacheControlValidator,
}) {
  final validator = cacheControlValidator ?? CacheControlValidator();
  final betas = <String>{};
  final warnings = <Warning>[];
  List<Map<String, Object?>>? system;
  final messages = <Map<String, Object?>>[];

  // server 工具调用 id 预扫描提升到 **prompt 级**(codex PR #61 复审):
  // supportsDeferredResults 语义下 server 结果可跨 turn 到达——call 在上一个
  // assistant 块、result 在下一个 assistant 块(中间隔 user/tool 消息)。块内
  // 收集会断链丢历史;全 prompt 预扫描既覆盖跨块/乱序,又保留 toolCallId
  // 配对对"同名 function tool 误回放"的防护(比上游按 toolName 全局判更严)。
  final serverToolCallIds = <String, String>{};
  for (final message in prompt) {
    if (message is! AssistantMessage) {
      continue;
    }
    for (final part in message.content) {
      if (part is ToolCallPart &&
          part.providerExecuted == true &&
          _serverToolNames.contains(part.toolName)) {
        serverToolCallIds[part.toolCallId] = part.toolName;
      }
    }
  }

  final blocks = _groupIntoBlocks(prompt);
  for (final (blockIndex, block) in blocks.indexed) {
    switch (block) {
      case _SystemBlock(:final blockMessages):
        // 块内每条 system 消息 → text 内容块,消息级 cache_control
        // 条件注入(报告 02 §2 :137-144)。
        final content = <Map<String, Object?>>[
          for (final message in blockMessages)
            <String, Object?>{
              'type': 'text',
              'text': message.content,
              ..._cacheControlEntry(
                validator.getCacheControl(
                  message.providerOptions,
                  contextType: 'system message',
                  canCache: true,
                ),
              ),
            },
        ];
        if (system == null) {
          // 第一个 system 块赋给顶层 system 字段(:146-147)。
          system = content;
        } else {
          // 中段 system 块作为 role:system 消息发出(:149-150)。
          messages.add(<String, Object?>{'role': 'system', 'content': content});
          betas.add('mid-conversation-system-2026-04-07');
        }
      case _UserBlock(:final blockMessages):
        final userContent = _convertUserBlockContent(
          blockMessages,
          validator: validator,
          betas: betas,
          warnings: warnings,
        );
        // 内容全部被跳过(如 ToolMessage 仅含 tool-approval-response)时不发
        // 空消息:Anthropic 拒绝空内容——与 assistant 块的空消息丢弃对称。
        if (userContent.isNotEmpty) {
          messages.add(<String, Object?>{
            'role': 'user',
            'content': userContent,
          });
        }
      case _AssistantBlock(:final blockMessages):
        final assistantContent = _convertAssistantBlockContent(
          blockMessages,
          isLastBlock: blockIndex == blocks.length - 1,
          sendReasoning: sendReasoning,
          validator: validator,
          warnings: warnings,
          serverToolCallIds: serverToolCallIds,
        );
        // 内容全部被丢弃(如全空白末位文本 trim 后为空)时不发空消息:
        // Anthropic 拒绝空内容的 assistant 消息。
        if (assistantContent.isNotEmpty) {
          messages.add(<String, Object?>{
            'role': 'assistant',
            'content': assistantContent,
          });
        }
    }
  }

  // warnings 单通道:validator 的告警统一追加到末尾(见决策摘要)。
  warnings.addAll(validator.warnings);

  return AnthropicPromptResult(
    system: system,
    messages: messages,
    betas: betas,
    warnings: warnings,
  );
}

/// cache_control 注入统一模式:值非 null 才产出 key(全文件适用)。
Map<String, Object?> _cacheControlEntry(Object? cacheControl) =>
    cacheControl == null
        ? const <String, Object?>{}
        : <String, Object?>{'cache_control': cacheControl};

/// 分块中间结构:连续同角色消息合并为一个块,user 与 tool 共享 UserBlock
/// (报告 02 §1.2 :1247-1301)。契约 sealed 四角色穷举,无未知角色分支。
sealed class _Block {}

final class _SystemBlock implements _Block {
  final List<SystemMessage> blockMessages = <SystemMessage>[];
}

/// user 与 tool 消息(任意交错)归入同一块(:1275-1292)。
final class _UserBlock implements _Block {
  final List<LanguageModelMessage> blockMessages = <LanguageModelMessage>[];
}

final class _AssistantBlock implements _Block {
  final List<AssistantMessage> blockMessages = <AssistantMessage>[];
}

/// 按顺序把消息分成 System / User / Assistant 块:当前消息对应块型与
/// 当前块不同则新开一个块,相同则追加(报告 02 §1.2 :1258-1263)。
List<_Block> _groupIntoBlocks(LanguageModelPrompt prompt) {
  final blocks = <_Block>[];
  _Block? currentBlock;

  for (final message in prompt) {
    switch (message) {
      case SystemMessage():
        if (currentBlock is! _SystemBlock) {
          currentBlock = _SystemBlock();
          blocks.add(currentBlock);
        }
        currentBlock.blockMessages.add(message);
      case UserMessage() || ToolMessage():
        if (currentBlock is! _UserBlock) {
          currentBlock = _UserBlock();
          blocks.add(currentBlock);
        }
        currentBlock.blockMessages.add(message);
      case AssistantMessage():
        if (currentBlock is! _AssistantBlock) {
          currentBlock = _AssistantBlock();
          blocks.add(currentBlock);
        }
        currentBlock.blockMessages.add(message);
    }
  }

  return blocks;
}

/// user 块内容:块内 user / tool 消息的 part 顺序拼进同一 content 数组
/// (报告 02 §3)。
List<Map<String, Object?>> _convertUserBlockContent(
  List<LanguageModelMessage> blockMessages, {
  required CacheControlValidator validator,
  required Set<String> betas,
  required List<Warning> warnings,
}) {
  final content = <Map<String, Object?>>[];
  for (final message in blockMessages) {
    switch (message) {
      case UserMessage(content: final parts, :final providerOptions):
        for (final (index, part) in parts.indexed) {
          // cache_control 回退链:part 级 ?? 最后 part 时消息级(报告 02
          // §7.2 :172-182;消息级回退按每条消息各自的最后 part 判定)。
          final isContainerUpload =
              part is FilePart && _isContainerUploadFileReference(part);
          final partOptions = switch (part) {
            TextPart(:final providerOptions) => providerOptions,
            FilePart(:final providerOptions) => providerOptions,
          };
          final cacheControl = isContainerUpload
              ? null
              : validator.getCacheControl(
                    partOptions,
                    contextType: 'user message part',
                    canCache: true,
                  ) ??
                  (index == parts.length - 1
                      ? validator.getCacheControl(
                          providerOptions,
                          contextType: 'user message',
                          canCache: true,
                        )
                      : null);
          switch (part) {
            case TextPart(:final text):
              content.add(<String, Object?>{
                'type': 'text',
                'text': text,
                ..._cacheControlEntry(cacheControl),
              });
            case FilePart():
              content.add(
                _convertUserFilePart(
                  part,
                  cacheControl: cacheControl,
                  betas: betas,
                ),
              );
          }
        }
      case ToolMessage(content: final parts, :final providerOptions):
        for (final (index, part) in parts.indexed) {
          switch (part) {
            case ToolResultPart(:final toolCallId, :final output):
              // cache_control 三级回退:part 级 ?? output 级 ??(最后 part
              // 时)消息级(报告 02 §7.2 :384-398)。
              final cacheControl = validator.getCacheControl(
                    part.providerOptions,
                    contextType: 'tool result part',
                    canCache: true,
                  ) ??
                  validator.getCacheControl(
                    _toolResultOutputProviderOptions(output),
                    contextType: 'tool result output',
                    canCache: true,
                  ) ??
                  (index == parts.length - 1
                      ? validator.getCacheControl(
                          providerOptions,
                          contextType: 'tool result message',
                          canCache: true,
                        )
                      : null);
              content.add(<String, Object?>{
                'type': 'tool_result',
                'tool_use_id': toolCallId,
                'content': _toolResultContentValue(
                  output,
                  betas: betas,
                  warnings: warnings,
                ),
                // is_error 仅 error 变体时为 true,否则字段不出现
                // (报告 02 §3.3 :530-533)。
                if (output is ToolResultErrorText ||
                    output is ToolResultErrorJson)
                  'is_error': true,
                ..._cacheControlEntry(cacheControl),
              });
            case ToolApprovalResponsePart():
              // 审批回复不产生任何输出(报告 02 §3.3 :365-367)。
              break;
          }
        }
      case SystemMessage() || AssistantMessage():
        // _groupIntoBlocks 保证 user 块内只有 user/tool 消息。
        throw StateError('unexpected message role in user block');
    }
  }
  return content;
}

bool _isContainerUploadFileReference(FilePart part) =>
    part.data is FileDataReference &&
    part.providerOptions?['anthropic']?['containerUpload'] == true;

/// tool_result 的 output 级 providerOptions 取法(报告 02 §3.3 :370-377):
/// output 自身带 providerOptions 用之;content 型 output 取 items 中第一个
/// providerOptions 非 null 元素的 providerOptions;否则 null。
ProviderOptions? _toolResultOutputProviderOptions(ToolResultOutput output) {
  switch (output) {
    case ToolResultText(:final providerOptions) ||
          ToolResultErrorText(:final providerOptions) ||
          ToolResultExecutionDenied(:final providerOptions) ||
          ToolResultJson(:final providerOptions) ||
          ToolResultErrorJson(:final providerOptions):
      return providerOptions;
    case ToolResultContentOutput(:final items):
      for (final item in items) {
        final options = switch (item) {
          ToolResultTextItem(:final providerOptions) => providerOptions,
          ToolResultFileItem(:final providerOptions) => providerOptions,
          ToolResultCustomItem(:final providerOptions) => providerOptions,
        };
        if (options != null) {
          return options;
        }
      }
      return null;
  }
}

/// tool_result 的 content 值(报告 02 §3.3 :400-524):text / error-text
/// 原样字符串;execution-denied 取 reason 或默认拒绝文案;json / error-json
/// 统一 jsonEncode;content 型逐元素映射后过滤 null。
Object? _toolResultContentValue(
  ToolResultOutput output, {
  required Set<String> betas,
  required List<Warning> warnings,
}) =>
    switch (output) {
      ToolResultText(:final value) ||
      ToolResultErrorText(:final value) =>
        value,
      ToolResultExecutionDenied(:final reason) =>
        reason ?? 'Tool call execution denied.',
      ToolResultJson(:final value) ||
      ToolResultErrorJson(:final value) =>
        jsonEncode(value),
      ToolResultContentOutput(:final items) => items
          .map(
            (item) =>
                _toolResultContentItem(item, betas: betas, warnings: warnings),
          )
          .nonNulls
          .toList(),
    };

/// content 型 output 的单元素映射(报告 02 §3.3 :405-508);不支持的元素
/// 返回 null(被过滤)并记 [UnsupportedWarning]。media 判定同 Task 7 规则:
/// image 用 [getTopLevelMediaType],wire media_type 用 [resolveFullMediaType]
/// 等价逻辑(ToolResultFileItem 非 FilePart,借临时 FilePart 适配同语义)。
Map<String, Object?>? _toolResultContentItem(
  ToolResultContentItem item, {
  required Set<String> betas,
  required List<Warning> warnings,
}) {
  switch (item) {
    case ToolResultTextItem(:final text):
      return <String, Object?>{'type': 'text', 'text': text};
    case ToolResultFileItem(:final data, :final mediaType):
      switch (data) {
        case FileDataUrl(:final url):
          // url + 顶层 image → image url source;其余 → document url source
          // (:416-433)。
          if (getTopLevelMediaType(mediaType) == 'image') {
            return <String, Object?>{
              'type': 'image',
              'source': <String, Object?>{
                'type': 'url',
                'url': url.toString(),
              },
            };
          }
          return <String, Object?>{
            'type': 'document',
            'source': <String, Object?>{
              'type': 'url',
              'url': url.toString(),
            },
          };
        case FileDataBytes() || FileDataBase64():
          // 顶级-only mediaType(如 'image'/'application')从字节魔数探测完整
          // subtype;PDF 判定同样用探测后的完整类型(与 user file part 一致,
          // 上游 tool-result 分支亦用 resolveFullMediaType,:452-454),否则
          // mediaType:'application' 的 PDF 工具输出会被误判丢弃。
          final resolvedMediaType =
              resolveFullMediaType(FilePart(data: data, mediaType: mediaType));
          if (getTopLevelMediaType(mediaType) == 'image') {
            return <String, Object?>{
              'type': 'image',
              'source': <String, Object?>{
                'type': 'base64',
                'media_type': resolvedMediaType,
                'data': _base64Data(data),
              },
            };
          }
          if (resolvedMediaType == 'application/pdf') {
            betas.add('pdfs-2024-09-25');
            return <String, Object?>{
              'type': 'document',
              'source': <String, Object?>{
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': _base64Data(data),
              },
            };
          }
          // 其他 media type 过滤 + warning(:467-472)。
          warnings.add(
            UnsupportedWarning(
              'tool result content part',
              details: 'unsupported tool content part type: file with '
                  'media type: $mediaType. It will be ignored.',
            ),
          );
          return null;
        case FileDataText() || FileDataReference():
          // 非内联数据形态过滤 + warning(:475-480)。
          final dataType = data is FileDataText ? 'text' : 'reference';
          warnings.add(
            UnsupportedWarning(
              'tool result content part',
              details: 'unsupported tool content part type: file with '
                  'data type: $dataType. It will be ignored.',
            ),
          );
          return null;
      }
    case ToolResultCustomItem():
      // 首版不支持 custom 元素(spec 疑点 #8;上游 :493-497)。
      warnings.add(
        const UnsupportedWarning(
          'tool result content part',
          details: 'unsupported custom tool content part. It will be ignored.',
        ),
      );
      return null;
  }
}

/// user file part → image / document 内容块(报告 02 §3.2)。
///
/// 分派顺序照上游:先按 data 变体处理 reference(Files API source)与 text
/// (document text source),再对 url / data 按 mediaType 三分支
/// (image / PDF / text-plain),其余 mediaType 抛
/// [UnsupportedFunctionalityError](:345-349)。
Map<String, Object?> _convertUserFilePart(
  FilePart part, {
  required Object? cacheControl,
  required Set<String> betas,
}) {
  switch (part.data) {
    case FileDataReference(:final reference):
      final fileId = resolveProviderReference(
        reference: reference,
        provider: 'anthropic',
      );
      betas.add('files-api-2025-04-14');
      if (_isContainerUploadFileReference(part)) {
        return <String, Object?>{
          'type': 'container_upload',
          'file_id': fileId,
        };
      }
      if (getTopLevelMediaType(part.mediaType) == 'image') {
        return <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{'type': 'file', 'file_id': fileId},
          ..._cacheControlEntry(cacheControl),
        };
      }
      return <String, Object?>{
        'type': 'document',
        'source': <String, Object?>{'type': 'file', 'file_id': fileId},
        ..._documentMetadataEntries(part),
        ..._cacheControlEntry(cacheControl),
      };
    case FileDataText(:final text):
      // 纯文本文件数据 → document text source(:227-253)。
      return <String, Object?>{
        'type': 'document',
        'source': <String, Object?>{
          'type': 'text',
          'media_type': 'text/plain',
          'data': text,
        },
        ..._documentMetadataEntries(part),
        ..._cacheControlEntry(cacheControl),
      };
    case FileDataUrl(:final url):
      // image 判定用顶级 mediaType(上游 getTopLevelMediaType,:257-265)。
      if (getTopLevelMediaType(part.mediaType) == 'image') {
        return <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'url',
            'url': url.toString(),
          },
          ..._cacheControlEntry(cacheControl),
        };
      }
      // PDF url 分支按完整 mediaType 判定(:273-279)。
      if (part.mediaType == 'application/pdf') {
        betas.add('pdfs-2024-09-25');
        return <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'url',
            'url': url.toString(),
          },
          ..._documentMetadataEntries(part),
          ..._cacheControlEntry(cacheControl),
        };
      }
      if (part.mediaType == 'text/plain') {
        return <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'url',
            'url': url.toString(),
          },
          ..._documentMetadataEntries(part),
          ..._cacheControlEntry(cacheControl),
        };
      }
      throw UnsupportedFunctionalityError(
        functionality: 'media type: ${part.mediaType}',
      );
    case FileDataBytes() || FileDataBase64():
      // 顶级-only mediaType(如 'image' / 'application')经
      // resolveFullMediaType 从字节魔数探测完整 subtype(media.dart:82)。
      if (getTopLevelMediaType(part.mediaType) == 'image') {
        return <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': resolveFullMediaType(part),
            'data': _base64Data(part.data),
          },
          ..._cacheControlEntry(cacheControl),
        };
      }
      if (getTopLevelMediaType(part.mediaType) == 'application' &&
          resolveFullMediaType(part) == 'application/pdf') {
        betas.add('pdfs-2024-09-25');
        return <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': _base64Data(part.data),
          },
          ..._documentMetadataEntries(part),
          ..._cacheControlEntry(cacheControl),
        };
      }
      if (part.mediaType == 'text/plain') {
        return <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'text',
            'media_type': 'text/plain',
            'data': _decodeTextData(part.data),
          },
          ..._documentMetadataEntries(part),
          ..._cacheControlEntry(cacheControl),
        };
      }
      throw UnsupportedFunctionalityError(
        functionality: 'media type: ${part.mediaType}',
      );
  }
}

/// document 块的 title / context / citations 字段(报告 02 §3.2(b)/§6):
/// title 取 providerOptions 的 `anthropic.title`,缺省回退 `part.filename`;
/// context 仅非空才带;citations 仅 `enabled == true` 才带。
Map<String, Object?> _documentMetadataEntries(FilePart part) {
  final options = part.providerOptions?['anthropic'];
  final title = options?['title'] as String? ?? part.filename;
  final context = options?['context'] as String?;
  final citations = options?['citations'];
  final citationsEnabled =
      citations is Map<String, Object?> && citations['enabled'] == true;
  return <String, Object?>{
    if (title != null) 'title': title,
    if (context != null) 'context': context,
    if (citationsEnabled) 'citations': <String, Object?>{'enabled': true},
  };
}

/// bytes / base64 数据 → wire base64 字符串(上游 convertToBase64)。
String _base64Data(FileData data) => switch (data) {
      FileDataBytes(:final bytes) => base64Encode(bytes),
      FileDataBase64(:final base64) => base64,
      FileDataUrl() ||
      FileDataText() ||
      FileDataReference() =>
        throw StateError('expected inline file data'),
    };

/// bytes / base64 数据解码回 UTF-8 字符串(上游 convertBytesDataToString,
/// :38-43)。`allowMalformed: true` 对齐上游 `TextDecoder().decode` 默认
/// 替换语义:非法序列换 U+FFFD 而非抛 FormatException。
String _decodeTextData(FileData data) => switch (data) {
      FileDataBytes(:final bytes) => utf8.decode(bytes, allowMalformed: true),
      FileDataBase64(:final base64) =>
        utf8.decode(base64Decode(base64), allowMalformed: true),
      FileDataUrl() ||
      FileDataText() ||
      FileDataReference() =>
        throw StateError('expected inline file data'),
    };

/// assistant 块内容:多条 assistant 消息的 part 顺序拼接后经
/// [_moveToolUseBlocksToEnd] 重排(报告 02 §4)。
///
/// [isLastBlock] 用于末位 text trim 判定:仅整个 prompt 最后一个块的
/// 最后一条消息的最后一个 part 才 trim(§4.1 :596-607,Anthropic 不允许
/// pre-fill assistant 响应有尾随空白)。
List<Map<String, Object?>> _convertAssistantBlockContent(
  List<AssistantMessage> blockMessages, {
  required bool isLastBlock,
  required bool sendReasoning,
  required CacheControlValidator validator,
  required List<Warning> warnings,
  // prompt 级 server 工具调用 id 表(toolCallId → toolName,由
  // convertToAnthropicMessages 顶层预扫描产出):支持 result 与 call 跨
  // assistant 块/乱序出现(deferred server-tool 续轮场景,codex PR #61 复审)。
  required Map<String, String> serverToolCallIds,
}) {
  final content = <Map<String, Object?>>[];
  // MCP 调用 id 集合:assistant 块级局部(每次本函数调用即一个块,作用域
  // 与上游在 case 'assistant' 内创建等价,:554-558)。明令禁止提升为
  // prompt 级预扫描(spec §7):MCP 结果恒与 mcp_tool_use 同响应到达,无
  // deferred 场景;prompt 级反会把后续块/tool role 的同 id 结果错序列化成
  // mcp_tool_result。
  final mcpToolUseIds = <String>{};
  for (final message in blockMessages) {
    for (final (partIndex, part) in message.content.indexed) {
      final isLastContentPart = partIndex == message.content.length - 1;

      // cache_control 回退链:part 级 ??(该消息最后 part 时)消息级
      // (报告 02 §7.2 :570-580)。惰性求值:仅可携带 cache_control 的
      // 分支调用,thinking 等 canCache:false 场景不消耗计数。
      Object? cacheControlFor(ProviderOptions? partOptions) =>
          validator.getCacheControl(
            partOptions,
            contextType: 'assistant message part',
            canCache: true,
          ) ??
          (isLastContentPart
              ? validator.getCacheControl(
                  message.providerOptions,
                  contextType: 'assistant message',
                  canCache: true,
                )
              : null);

      switch (part) {
        case TextPart(:final text, :final providerOptions):
          // compaction 文本回放为 compaction 块(:584-612):判定键沿解析侧
          // metadata 形态;块字段名是 content(非 text);照上游不做末位
          // trim——trim 只在普通 text 分支,且函数尾部的末位 trim 只认
          // type 为 text 的块,compaction 天然不触及。
          if (providerOptions?['anthropic']?['type'] == 'compaction') {
            content.add(<String, Object?>{
              'type': 'compaction',
              'content': text,
              ..._cacheControlEntry(cacheControlFor(providerOptions)),
            });
            break;
          }
          final citations = providerOptions?['anthropic']?['citations'];
          content.add(<String, Object?>{
            'type': 'text',
            // 末位 text trim 延后到过滤/重排后统一处理(见函数尾部),避免末尾
            // part 被跳过时漏 trim(§4.1 :596-607)。
            'text': text,
            if (citations is List<Object?>) 'citations': citations,
            ..._cacheControlEntry(cacheControlFor(providerOptions)),
          });
        case ReasoningPart(:final text, :final providerOptions):
          if (!sendReasoning) {
            // 模型禁发 reasoning:整个 part 丢弃(:658-664)。
            warnings.add(
              const OtherWarning(
                'sending reasoning content is disabled for this model',
              ),
            );
            break;
          }
          final reasoningOptions = providerOptions?['anthropic'];
          final signature = reasoningOptions?['signature'] as String?;
          final redactedData = reasoningOptions?['redactedData'] as String?;
          if (signature != null) {
            // thinking 块不能带 cache_control,调用仅触发 warning
            // (:621-628,返回值弃用)。
            validator.getCacheControl(
              providerOptions,
              contextType: 'thinking block',
              canCache: false,
            );
            content.add(<String, Object?>{
              'type': 'thinking',
              'thinking': text,
              'signature': signature,
            });
          } else if (redactedData != null) {
            validator.getCacheControl(
              providerOptions,
              contextType: 'redacted thinking block',
              canCache: false,
            );
            // redacted_thinking 不带 thinking 文本(:642-645)。
            content.add(<String, Object?>{
              'type': 'redacted_thinking',
              'data': redactedData,
            });
          } else {
            // metadata 缺失:丢弃(:646-657)。
            warnings.add(const OtherWarning('unsupported reasoning metadata'));
          }
        case ToolCallPart(
            :final toolCallId,
            :final toolName,
            :final input,
            :final providerExecuted,
            :final providerOptions,
          ):
          if (providerExecuted == true) {
            // MCP 调用判定优先于 server 工具名单(判定顺序照 :670-700;
            // 报告 10 §8.6 插入位):判定键是解析侧写入的 metadata 形态
            // `anthropic.type == 'mcp-tool-use'`(连字符)。
            if (providerOptions?['anthropic']?['type'] == 'mcp-tool-use') {
              // id 先进块级集合(照 :984 顺序),供同块 ToolResultPart 配对。
              mcpToolUseIds.add(toolCallId);
              final serverName = providerOptions?['anthropic']?['serverName'];
              if (serverName is! String) {
                // 上游此处为 warning + 跳过该调用(:989-996);pigcode 收紧
                // 为 fail-fast(有据偏离):回放侧 wire 接口 server_name
                // 必填(:387-402),缺失无法重建合法块,warning 静默跳过会
                // 把损坏历史悄悄发出;caller 契约违例按 pigcode 既有先例用
                // ArgumentError(文案沿上游 warning 原文)。
                throw ArgumentError(
                  'mcp tool use server name is required and must be a string',
                );
              }
              // input 原样直传,不经 _toAnthropicToolInput 包装(:1002)。
              content.add(<String, Object?>{
                'type': 'mcp_tool_use',
                'id': toolCallId,
                'name': toolName,
                'input': input,
                'server_name': serverName,
                ..._cacheControlEntry(cacheControlFor(providerOptions)),
              });
              break;
            }
            if (_serverToolNames.contains(toolName)) {
              // server_tool_use 回传:input 原样不包装(报告 07 §6.1
              // :739-750,与普通 tool_use 的 _toAnthropicToolInput 包装
              // 路径不同);不回传 caller(上游回传形状无 caller 字段)。
              // code_execution/advisor 需按各自形态改写 name/input
              // (报告 09 §5.1a/b/c/e,spec §3.5)。
              final (wireName, wireInput) = switch (toolName) {
                'code_execution' => _codeExecutionReplayForm(input),
                // advisor 的 server_tool_use.input 恒为 {}(上游硬编码,
                // 不读 part.input;报告 09 §5.1e :762-770)。
                'advisor' => ('advisor', const <String, Object?>{}),
                _ => (toolName, input),
              };
              content.add(<String, Object?>{
                'type': 'server_tool_use',
                'id': toolCallId,
                'name': wireName,
                'input': wireInput,
                ..._cacheControlEntry(cacheControlFor(providerOptions)),
              });
              break;
            }
            // 未知服务端工具首版不支持(上游 :769-774 兜底分支)。
            warnings.add(
              UnsupportedWarning(
                'provider executed tool call',
                details: 'provider executed tool call for tool $toolName '
                    'is not supported. It will be ignored.',
              ),
            );
            break;
          }
          content.add(<String, Object?>{
            'type': 'tool_use',
            'id': toolCallId,
            'name': toolName,
            'input': _toAnthropicToolInput(input),
            ..._toolUseCallerEntry(providerOptions),
            ..._cacheControlEntry(cacheControlFor(providerOptions)),
          });
        case ToolResultPart(
            :final toolCallId,
            :final toolName,
            :final output,
            :final providerOptions,
          ):
          // mcp_tool_result 判定优先于 prompt 级 serverToolCallIds(:1022
          // 在分支链最前;报告 10 §4.6:同 id 同时命中两类时 MCP 胜出)。
          if (mcpToolUseIds.contains(toolCallId)) {
            switch (output) {
              case ToolResultJson(:final value) ||
                    ToolResultErrorJson(:final value):
                content.add(<String, Object?>{
                  'type': 'mcp_tool_result',
                  'tool_use_id': toolCallId,
                  'is_error': output is ToolResultErrorJson,
                  // content 原样直传(:1034-1042 上游 output.value as-is,
                  // 不 jsonEncode——与普通 tool_result 的字符串化路径不同)。
                  'content': value,
                  ..._cacheControlEntry(cacheControlFor(providerOptions)),
                });
              // 仅收 json/error-json 两型(:1025-1032);其余 output 型
              // warning + 跳过不回放(文案照上游逐字)。
              case ToolResultText() ||
                    ToolResultErrorText() ||
                    ToolResultExecutionDenied() ||
                    ToolResultContentOutput():
                warnings.add(OtherWarning(
                  'provider executed tool result output type '
                  '${_toolResultOutputTypeName(output)} for tool $toolName '
                  'is not supported',
                ));
            }
            // 成功回放到此为止,不发兜底 warning:上游成功 push 后因缺
            // break 落穿到兜底 `provider executed tool result for tool X is
            // not supported`(:1204-1209),成功路径报 not supported 自相
            // 矛盾,属"上游内部矛盾不照抄"框架——已拍板走向 B 修掉(有据
            // 偏离,依据报告 10 §4.4 差异表;上游快照锁并存行为不证有意)。
            break;
          }
          final serverToolName = serverToolCallIds[toolCallId];
          if (serverToolName != null) {
            final replayed = _replayServerToolResult(
              serverToolName: serverToolName,
              toolCallId: toolCallId,
              output: output,
              warnings: warnings,
            );
            if (replayed != null) {
              content.add(replayed);
            }
            break;
          }
          // 未命中 server 侧调用集合的服务端工具结果首版不支持(上游
          // :1202-1205 兜底;决策摘要偏离项:toolCallId 集合匹配)。
          warnings.add(
            UnsupportedWarning(
              'provider executed tool result',
              details: 'provider executed tool result for tool $toolName '
                  'is not supported. It will be ignored.',
            ),
          );
        // 以下四类是 pigcode 契约允许出现在 assistant 的形态,上游 TS 无
        // 对应物——首版一律丢弃 + warning(计划 Task 9 定案条)。
        case FilePart():
          warnings.add(_unsupportedAssistantPartWarning('FilePart'));
        case ReasoningFilePart():
          warnings.add(_unsupportedAssistantPartWarning('ReasoningFilePart'));
        case CustomPart():
          warnings.add(_unsupportedAssistantPartWarning('CustomPart'));
        case ToolApprovalRequestPart():
          warnings.add(
            _unsupportedAssistantPartWarning('ToolApprovalRequestPart'),
          );
      }
    }
  }
  final reordered = _moveToolUseBlocksToEnd(content);
  // 末位文本 trim:Anthropic 拒绝 assistant prefill 尾随空白。基于过滤/重排后
  // 真正的末位块判定(而非原始位置 isLastContentPart):末尾 part 若被跳过——如
  // sendReasoning:false 丢弃末位 ReasoningPart、或契约独有 part 被丢弃——按位置
  // 判定会漏 trim 真正落地的末位文本而产生 400。仅当末位块确为 text 时 trim,
  // tool_use 收尾不动(pigcode 比上游 :604 的纯位置判定更严谨)。
  if (isLastBlock && reordered.isNotEmpty) {
    final lastIndex = reordered.length - 1;
    final last = reordered[lastIndex];
    final text = last['text'];
    if (last['type'] == 'text' && text is String) {
      // 仅去尾随空白:API 约束只针对 trailing whitespace(上游注释自证,
      // convert-to-anthropic-prompt.ts:601-603),前导空白(如缩进 prefill)有
      // 语义须保留——上游实现用两端 trim() 属注释-实现不一致,不照抄。
      final trimmed = text.trimRight();
      if (trimmed.isEmpty) {
        // 全空白末位文本 trim 后为空:Anthropic 拒绝空 text 内容块,直接丢弃
        // (偏离点的自洽收尾;消息级空内容由 caller 丢弃整条消息)。
        reordered.removeLast();
      } else {
        reordered[lastIndex] = <String, Object?>{...last, 'text': trimmed};
      }
    }
  }
  return reordered;
}

/// 契约独有 assistant part 的统一丢弃告警(计划 Task 9 定案条)。
UnsupportedWarning _unsupportedAssistantPartWarning(String typeName) =>
    UnsupportedWarning(
      'assistant content part',
      details: '$typeName in assistant message is not supported by '
          'anthropic messages. It will be ignored.',
    );

/// [ToolResultOutput] 变体 → 上游 output.type 字面量(mcp_tool_result 的
/// output-type warning 文案用)。
String _toolResultOutputTypeName(ToolResultOutput output) => switch (output) {
      ToolResultText() => 'text',
      ToolResultJson() => 'json',
      ToolResultErrorText() => 'error-text',
      ToolResultErrorJson() => 'error-json',
      ToolResultExecutionDenied() => 'execution-denied',
      ToolResultContentOutput() => 'content',
    };

/// Anthropic 要求 tool_use.input 必须是 object;契约 input 为 JsonValue
/// 可为任意形态:非 null 的 Map 原样直传,其余(String/List/num/bool/null)
/// 包装为 `{'rawInvalidInput': input}`(上游 origin/main 148babc
/// convert-to-anthropic-prompt.ts:1333-1338 toAnthropicToolInput)。
Map<String, Object?> _toAnthropicToolInput(JsonValue input) =>
    input is Map<String, Object?>
        ? input
        : <String, Object?>{'rawInvalidInput': input};

/// code_execution 的 `server_tool_use` 回放三态选择(报告 09 §5.1a/b/c,
/// spec §3.5 / §6.2 定案),返回 (wire name, wire input)。
///
/// - `input` 含 `type` 且为 `bash_code_execution`/
///   `text_editor_code_execution` → wire name = 该子工具名,**input 原样
///   含 type 键**(上游 convert :711-717,不剥离;测试快照 :3090-3140
///   背书);
/// - `input` 含 `type: 'programmatic-tool-call'`(SDK 内部虚构 type,wire
///   上不存在)→ wire name = `code_execution`,**剥离 type 键**(上游
///   :727-737);
/// - 其余(20250522 无 type 形态,input 仅 `{code}`)→ wire name =
///   `code_execution`,input 原样(上游 :738-750)。
(String, Object?) _codeExecutionReplayForm(JsonValue input) {
  if (input case Map<String, Object?> map) {
    final type = map['type'];
    if (type == 'bash_code_execution' || type == 'text_editor_code_execution') {
      return (type! as String, map);
    }
    if (type == 'programmatic-tool-call') {
      return ('code_execution', Map<String, Object?>.of(map)..remove('type'));
    }
  }
  return ('code_execution', input);
}

/// server 侧工具结果回放:按登记的 [serverToolName] 分派到各家族 helper,
/// 把 [output] 还原成对应 wire 结果块(报告 07 §6.2 web 两族 + 报告 09
/// §5.2 code_execution/tool_search/advisor 三族)。
Map<String, Object?>? _replayServerToolResult({
  required String serverToolName,
  required String toolCallId,
  required ToolResultOutput output,
  required List<Warning> warnings,
}) {
  switch (serverToolName) {
    case 'web_search':
    case 'web_fetch':
      return _replayWebToolResult(
        serverToolName: serverToolName,
        toolCallId: toolCallId,
        output: output,
        warnings: warnings,
      );
    case 'code_execution':
      return _replayCodeExecutionToolResult(
        toolCallId: toolCallId,
        output: output,
        warnings: warnings,
      );
    case 'tool_search_tool_regex':
    case 'tool_search_tool_bm25':
      return _replayToolSearchToolResult(
        serverToolName: serverToolName,
        toolCallId: toolCallId,
        output: output,
        warnings: warnings,
      );
    case 'advisor':
      return _replayAdvisorToolResult(
        toolCallId: toolCallId,
        output: output,
        warnings: warnings,
      );
    default:
      // 理论不可达:调用方只对 _serverToolNames 成员登记的 toolCallId
      // 调用本函数(见 prompt 级 prescan)。
      warnings.add(
        UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool $serverToolName '
              'is not supported. It will be ignored.',
        ),
      );
      return null;
  }
}

/// web_search/web_fetch 结果回放(报告 07 §6.2,批次 1 既有逻辑原样抽出,
/// 行为不变)。
Map<String, Object?>? _replayWebToolResult({
  required String serverToolName,
  required String toolCallId,
  required ToolResultOutput output,
  required List<Warning> warnings,
}) {
  switch (output) {
    case ToolResultErrorJson(:final value):
      final errorCode = _extractErrorCode(value) ?? 'unavailable';
      final errorType = serverToolName == 'web_search'
          ? 'web_search_tool_result_error'
          : 'web_fetch_tool_result_error';
      return <String, Object?>{
        'type': '${serverToolName}_tool_result',
        'tool_use_id': toolCallId,
        'content': <String, Object?>{
          'type': errorType,
          'error_code': errorCode,
        },
      };
    case ToolResultJson(:final value):
      return serverToolName == 'web_search'
          ? _replayWebSearchResult(toolCallId: toolCallId, value: value)
          : _replayWebFetchResult(toolCallId: toolCallId, value: value);
    case ToolResultText() ||
          ToolResultErrorText() ||
          ToolResultExecutionDenied() ||
          ToolResultContentOutput():
      // 非 json/error-json 变体:warning + 丢弃(报告 07 §6.2 :1017-1024
      // 同构)。
      warnings.add(
        UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool $serverToolName '
              'is not supported. It will be ignored.',
        ),
      );
      return null;
  }
}

/// code_execution 结果回放:一名对三块,按存储 output 的变体与
/// value['type'] 判别选块(报告 09 §5.2 :839-996)。
Map<String, Object?>? _replayCodeExecutionToolResult({
  required String toolCallId,
  required ToolResultOutput output,
  required List<Warning> warnings,
}) {
  switch (output) {
    case ToolResultErrorText(:final value):
      return _replayCodeExecutionError(toolCallId: toolCallId, rawValue: value);
    case ToolResultErrorJson(:final value):
      return _replayCodeExecutionError(toolCallId: toolCallId, rawValue: value);
    case ToolResultJson(:final value):
      if (value is! Map<String, Object?> || value['type'] is! String) {
        // 报告 09 §5.2 步骤 2(:892-903):非「带 string type 的对象」→
        // warning 丢弃。
        warnings.add(
          const UnsupportedWarning(
            'provider executed tool result',
            details: 'provider executed tool result output value is not a '
                'valid code execution result. It will be ignored.',
          ),
        );
        return null;
      }
      return _replayCodeExecutionSuccess(toolCallId: toolCallId, value: value);
    case ToolResultText() ||
          ToolResultExecutionDenied() ||
          ToolResultContentOutput():
      // 报告 09 §5.2 步骤 2(:883-890):非 json → warning 丢弃。
      warnings.add(
        const UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool code_execution '
              'is not supported. It will be ignored.',
        ),
      );
      return null;
  }
}

/// code_execution 错误结果回放(报告 09 §5.2 步骤 1,:843-881):
/// errorInfo.type == 'code_execution_tool_result_error' →
/// code_execution_tool_result 块;否则(含解析失败/字段缺失)恒落
/// bash_code_execution_tool_result 错误块(上游 :870-879——text_editor 的
/// error-json 形态在此变形为 bash 错误块,照抄,报告 09 §9.8)。
/// error_code 缺失兜底 'unknown'(web 工具为 'unavailable',不同于此处)。
Map<String, Object?> _replayCodeExecutionError({
  required String toolCallId,
  required Object? rawValue,
}) {
  final errorInfo = _parseCodeExecutionErrorInfo(rawValue);
  if (errorInfo['type'] == 'code_execution_tool_result_error') {
    return <String, Object?>{
      'type': 'code_execution_tool_result',
      'tool_use_id': toolCallId,
      'content': <String, Object?>{
        'type': 'code_execution_tool_result_error',
        'error_code': errorInfo['errorCode'] ?? 'unknown',
      },
    };
  }
  return <String, Object?>{
    'type': 'bash_code_execution_tool_result',
    'tool_use_id': toolCallId,
    'content': <String, Object?>{
      'type': 'bash_code_execution_tool_result_error',
      'error_code': errorInfo['errorCode'] ?? 'unknown',
    },
  };
}

/// 从 error-text/error-json 的载体值解析 `{type, errorCode}`(报告 09
/// :847-857):值为字符串先 JSON 解码,已是 Map 直接读;解析失败/形态不符
/// 时返回空 map(两键皆 null),下游按兜底处理——与上游 try/catch 吞异常的
/// 静默失败语义一致。
Map<String, Object?> _parseCodeExecutionErrorInfo(Object? rawValue) {
  Object? decoded = rawValue;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return const <String, Object?>{};
    }
  }
  if (decoded is Map<String, Object?>) {
    return <String, Object?>{
      'type': decoded['type'],
      'errorCode': decoded['errorCode'],
    };
  }
  return const <String, Object?>{};
}

/// code_execution 成功结果回放(报告 09 §5.2 步骤 3,:905-994):按
/// value['type'] 三态分派——`code_execution_result`/
/// `encrypted_code_execution_result` 逐字段重建;其余先过 20250825 输出
/// 七支 union 完整校验(:956-959,**未知 type 抛错而非丢弃**),再按 bash
/// 两支 / 其余四支路由到 bash / text_editor 透传块(:974-993,content
/// 原样不重建)。
Map<String, Object?> _replayCodeExecutionSuccess({
  required String toolCallId,
  required Map<String, Object?> value,
}) {
  final resultType = value['type']! as String;
  switch (resultType) {
    case 'code_execution_result':
      final result =
          validateTypes(value, _codeExecutionResultValidator)! as JsonObject;
      return <String, Object?>{
        'type': 'code_execution_tool_result',
        'tool_use_id': toolCallId,
        'content': <String, Object?>{
          'type': 'code_execution_result',
          'stdout': result['stdout'],
          'stderr': result['stderr'],
          'return_code': result['return_code'],
          'content': result['content'] ?? const <Object?>[],
        },
      };
    case 'encrypted_code_execution_result':
      final result = validateTypes(
        value,
        _encryptedCodeExecutionResultValidator,
      )! as JsonObject;
      return <String, Object?>{
        'type': 'code_execution_tool_result',
        'tool_use_id': toolCallId,
        'content': <String, Object?>{
          'type': 'encrypted_code_execution_result',
          'encrypted_stdout': result['encrypted_stdout'],
          'stderr': result['stderr'],
          'return_code': result['return_code'],
          'content': result['content'] ?? const <Object?>[],
        },
      };
    default:
      // 上游 :956-959:透传臂前对完整 20250825 七支 union 跑校验——
      // 未知具体 type 在此抛 TypeValidationError,而非 warning 丢弃。
      validateTypes(value, _codeExecution20250825OutputValidator);
      if (_bashCodeExecutionContentTypes.contains(resultType)) {
        return <String, Object?>{
          'type': 'bash_code_execution_tool_result',
          'tool_use_id': toolCallId,
          'content': value,
        };
      }
      // 其余四支(text_editor 三种结果 + 其错误)→ text_editor 块,
      // 照上游 else(:986-993)。
      return <String, Object?>{
        'type': 'text_editor_code_execution_tool_result',
        'tool_use_id': toolCallId,
        'content': value,
      };
  }
}

/// tool_search 结果回放:只收 json;error-json 等一律 warning 丢弃(报告
/// 09 §5.2 :1113-1150,§9 疑点 7——错误结果无回放路径,往返不闭环,上游
/// 现状照抄)。wrapper 块 type 恒为 `tool_search_tool_result`,不因
/// regex/bm25 而变(§5.2 :1139-1147)。
Map<String, Object?>? _replayToolSearchToolResult({
  required String serverToolName,
  required String toolCallId,
  required ToolResultOutput output,
  required List<Warning> warnings,
}) {
  switch (output) {
    case ToolResultJson(:final value):
      validateTypes(value, _toolSearchResultValidator);
      final refs = (value! as List<Object?>).cast<JsonObject>();
      return <String, Object?>{
        'type': 'tool_search_tool_result',
        'tool_use_id': toolCallId,
        'content': <String, Object?>{
          'type': 'tool_search_tool_search_result',
          'tool_references': [
            for (final ref in refs)
              <String, Object?>{
                'type': ref['type'],
                'tool_name': ref['toolName'],
              },
          ],
        },
      };
    case ToolResultText() ||
          ToolResultErrorText() ||
          ToolResultErrorJson() ||
          ToolResultExecutionDenied() ||
          ToolResultContentOutput():
      warnings.add(
        UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool $serverToolName '
              'is not supported. It will be ignored.',
        ),
      );
      return null;
  }
}

/// advisor 结果回放:json 与 error-json 两种都经统一 schema 校验(报告 09
/// §5.2 :1152-1202)。
Map<String, Object?>? _replayAdvisorToolResult({
  required String toolCallId,
  required ToolResultOutput output,
  required List<Warning> warnings,
}) {
  switch (output) {
    case ToolResultJson(:final value):
      return _replayAdvisorContent(toolCallId: toolCallId, value: value);
    case ToolResultErrorJson(:final value):
      return _replayAdvisorContent(toolCallId: toolCallId, value: value);
    case ToolResultText() ||
          ToolResultErrorText() ||
          ToolResultExecutionDenied() ||
          ToolResultContentOutput():
      warnings.add(
        const UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool advisor is not '
              'supported. It will be ignored.',
        ),
      );
      return null;
  }
}

/// advisor 三支内容重建(报告 09 §5.2 :1152-1202):advisor_result → text
/// 原样;advisor_redacted_result → encryptedContent→encrypted_content
/// 原样回传(server 解密依赖,报告 09 §7.4 :2610-2658 verbatim 往返测试
/// 背书);其余(advisor_tool_result_error)→ errorCode→error_code。
Map<String, Object?> _replayAdvisorContent({
  required String toolCallId,
  required JsonValue value,
}) {
  final result = validateTypes(value, _advisorResultValidator)! as JsonObject;
  final content = switch (result['type']) {
    'advisor_result' => <String, Object?>{
        'type': 'advisor_result',
        'text': result['text'],
      },
    'advisor_redacted_result' => <String, Object?>{
        'type': 'advisor_redacted_result',
        'encrypted_content': result['encryptedContent'],
      },
    _ => <String, Object?>{
        'type': 'advisor_tool_result_error',
        'error_code': result['errorCode'],
      },
  };
  return <String, Object?>{
    'type': 'advisor_tool_result',
    'tool_use_id': toolCallId,
    'content': content,
  };
}

/// `web_search_tool_result` 成功变体回传:校验每条结果后 camel→snake 还原
/// (报告 07 §6.2 :1097-1108)。
Map<String, Object?> _replayWebSearchResult({
  required String toolCallId,
  required JsonValue value,
}) {
  final items = (value! as List<Object?>)
      .map((item) =>
          validateTypes(item, _webSearchResultItemValidator)! as JsonObject)
      .toList();
  return <String, Object?>{
    'type': 'web_search_tool_result',
    'tool_use_id': toolCallId,
    'content': [
      for (final item in items)
        <String, Object?>{
          'url': item['url'],
          'title': item['title'],
          'page_age': item['pageAge'],
          'encrypted_content': item['encryptedContent'],
          'type': item['type'],
        },
    ],
  };
}

/// `web_fetch_tool_result` 成功变体回传:校验后还原 `retrieved_at`/
/// `media_type`(报告 07 §6.2 :1034-1056)。
Map<String, Object?> _replayWebFetchResult({
  required String toolCallId,
  required JsonValue value,
}) {
  final result = validateTypes(value, _webFetchResultValidator)! as JsonObject;
  final document = result['content']! as JsonObject;
  final source = document['source']! as JsonObject;
  return <String, Object?>{
    'type': 'web_fetch_tool_result',
    'tool_use_id': toolCallId,
    'content': <String, Object?>{
      'type': result['type'],
      'url': result['url'],
      'retrieved_at': result['retrievedAt'],
      'content': <String, Object?>{
        'type': document['type'],
        'title': document['title'],
        if (document.containsKey('citations'))
          'citations': document['citations'],
        'source': <String, Object?>{
          'type': source['type'],
          'media_type': source['mediaType'],
          'data': source['data'],
        },
      },
    },
  };
}

/// error-json 的 errorCode 提取(报告 07 §6.2 extractErrorValue,兼容
/// 字符串化 JSON 与对象两种载体)。
String? _extractErrorCode(JsonValue value) {
  if (value is Map<String, Object?>) {
    return value['errorCode'] as String?;
  }
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) {
        return decoded['errorCode'] as String?;
      }
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// tool_use 块的 caller 字段(报告 02 §4.3 :781-798):
/// `direct` → `{'type': 'direct'}`;code_execution 两版本且带 toolId →
/// `{'type': ..., 'tool_id': ...}`(wire snake_case);其余不产出 caller。
Map<String, Object?> _toolUseCallerEntry(ProviderOptions? providerOptions) {
  final caller = providerOptions?['anthropic']?['caller'];
  if (caller is! Map<String, Object?>) {
    return const <String, Object?>{};
  }
  final type = caller['type'];
  if (type == 'direct') {
    return const <String, Object?>{
      'caller': <String, Object?>{'type': 'direct'},
    };
  }
  final toolId = caller['toolId'];
  if ((type == 'code_execution_20250825' ||
          type == 'code_execution_20260120') &&
      toolId is String) {
    return <String, Object?>{
      'caller': <String, Object?>{'type': type, 'tool_id': toolId},
    };
  }
  return const <String, Object?>{};
}

/// assistant 内容按 thinking 边界分段重排(报告 02 §4.6 :1303-1329):
/// 遇 `thinking` / `redacted_thinking` 先 flush 当前段(非 tool_use 先出、
/// tool_use 移段尾)再原位 push;结尾 flush。只识别 `'tool_use'`,不含
/// server_tool_use / mcp_tool_use 等其他块。
List<Map<String, Object?>> _moveToolUseBlocksToEnd(
  List<Map<String, Object?>> content,
) {
  final result = <Map<String, Object?>>[];
  final segmentOthers = <Map<String, Object?>>[];
  final segmentToolUses = <Map<String, Object?>>[];

  void flushSegment() {
    result
      ..addAll(segmentOthers)
      ..addAll(segmentToolUses);
    segmentOthers.clear();
    segmentToolUses.clear();
  }

  for (final block in content) {
    final type = block['type'];
    if (type == 'thinking' || type == 'redacted_thinking') {
      flushSegment();
      result.add(block);
    } else if (type == 'tool_use') {
      segmentToolUses.add(block);
    } else {
      segmentOthers.add(block);
    }
  }
  flushSegment();
  return result;
}
