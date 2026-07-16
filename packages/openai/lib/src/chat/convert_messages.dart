import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../internal/capabilities.dart';

/// [convertToOpenAiChatMessages] 的返回值:wire 消息数组 + 转换期告警。
final class OpenAiChatMessagesResult {
  const OpenAiChatMessagesResult({
    required this.messages,
    required this.warnings,
  });

  /// 已转换的 OpenAI chat 消息数组,每个元素是一条消息的 JSON 形状。
  final List<Map<String, Object?>> messages;

  /// 转换期间产生的告警(目前仅 `systemMessageMode: remove` 场景)。
  final List<Warning> warnings;
}

/// 把契约层 [LanguageModelPrompt] 转换为 OpenAI Chat Completions 的
/// `messages` 数组。
///
/// wire 语义逐字对照 v7 `convertToOpenAIChatMessages`(`raw/`
/// `convert-to-openai-chat-messages.ts`),仅在 image part 的 base64 编码上
/// 主动偏离上游:上游对 `FileDataBase64`/`FileDataBytes` 来源只写了裸
/// base64 字符串(疑似遗漏 data URI 前缀),经核对 OpenAI 官方文档
/// (Vision 指南)`image_url.url` 字段对 base64 图片要求完整 data URI 形态
/// `data:<mediaType>;base64,<data>`,故本实现补全前缀,不照抄疑似 bug。
///
/// [providerOptionsName] 决定 `FileDataReference.reference` 读取哪个
/// provider key。上游 chat converter 此处硬编码 `'openai'`(raw ~81 行
/// `resolveProviderReference({provider: 'openai'})`,chat wire 无 azure
/// 派生机制),本参数是**主动超上游**的包内对称延伸:chat 的 call 级
/// provider options 已按 provider 名派生(见
/// `chat_language_model.dart` 对 `resolveOpenAiProviderOptions` 的使用),
/// responses 侧文件引用也读派生 key,若此处仍恒读 `'openai'`,同一个
/// `createOpenAi(name: 'azure-x')` 实例会出现 call 级认 `'azure'` 键、
/// 文件引用只认 `'openai'` 键的自相矛盾。
OpenAiChatMessagesResult convertToOpenAiChatMessages({
  required LanguageModelPrompt prompt,
  required SystemMessageMode systemMessageMode,
  String providerOptionsName = 'openai',
}) {
  final messages = <Map<String, Object?>>[];
  final warnings = <Warning>[];

  for (final message in prompt) {
    switch (message) {
      case SystemMessage(:final content):
        _convertSystemMessage(
          content: content,
          mode: systemMessageMode,
          messages: messages,
          warnings: warnings,
        );
      case UserMessage(:final content):
        messages.add(_convertUserMessage(content, providerOptionsName));
      case AssistantMessage(:final content):
        messages.add(_convertAssistantMessage(content));
      case ToolMessage(:final content):
        messages.addAll(_convertToolMessage(content));
    }
  }

  return OpenAiChatMessagesResult(messages: messages, warnings: warnings);
}

void _convertSystemMessage({
  required String content,
  required SystemMessageMode mode,
  required List<Map<String, Object?>> messages,
  required List<Warning> warnings,
}) {
  switch (mode) {
    case SystemMessageMode.system:
      messages.add({'role': 'system', 'content': content});
    case SystemMessageMode.developer:
      messages.add({'role': 'developer', 'content': content});
    case SystemMessageMode.remove:
      warnings.add(
        const OtherWarning('system messages are removed for this model'),
      );
  }
}

Map<String, Object?> _convertUserMessage(
  List<UserContentPart> content,
  String providerOptionsName,
) {
  if (content.length == 1 && content[0] is TextPart) {
    return {
      'role': 'user',
      'content': (content[0] as TextPart).text,
    };
  }

  final parts = <Object?>[];
  for (var index = 0; index < content.length; index++) {
    parts.add(
      _convertUserContentPart(content[index], index, providerOptionsName),
    );
  }
  return {'role': 'user', 'content': parts};
}

Map<String, Object?> _convertUserContentPart(
  UserContentPart part,
  int index,
  String providerOptionsName,
) {
  switch (part) {
    case TextPart(:final text):
      return {'type': 'text', 'text': text};
    case FilePart(
        :final data,
        :final mediaType,
        :final filename,
        :final providerOptions
      ):
      return _convertFilePart(
        data: data,
        mediaType: mediaType,
        filename: filename,
        index: index,
        providerOptionsName: providerOptionsName,
        providerOptions: providerOptions,
      );
  }
}

Map<String, Object?> _convertFilePart({
  required FileData data,
  required String mediaType,
  required String? filename,
  required int index,
  required String providerOptionsName,
  required ProviderOptions? providerOptions,
}) {
  if (data is FileDataReference) {
    final fileId = resolveProviderReference(
      reference: data.reference,
      provider: providerOptionsName,
    );
    return {
      'type': 'file',
      'file': {'file_id': fileId},
    };
  }
  if (data is FileDataText) {
    throw const UnsupportedFunctionalityError(functionality: 'text file parts');
  }

  final topLevel = mediaType.split('/').first;

  if (topLevel == 'image') {
    // `detail` 对照 raw `convert-to-openai-chat-messages.ts` ~104 行
    // `part.providerOptions?.openai?.imageDetail`;pigcode 按
    // [providerOptionsName] 派生 key 读取(与本文件其余 part 读取取齐,
    // 见文件头注释),未设置时不发该字段(wire 侧留空触发 OpenAI 默认
    // 的 `auto` 行为)。
    final imageDetail =
        providerOptions?[providerOptionsName]?['imageDetail'] as String?;
    return {
      'type': 'image_url',
      'image_url': {
        'url': _imageUrl(data, mediaType),
        if (imageDetail != null) 'detail': imageDetail,
      },
    };
  }

  if (topLevel == 'audio') {
    if (data is FileDataUrl) {
      throw const UnsupportedFunctionalityError(
        functionality: 'audio file parts with URLs',
      );
    }
    final format = switch (mediaType) {
      'audio/wav' => 'wav',
      'audio/mp3' || 'audio/mpeg' => 'mp3',
      _ => throw UnsupportedFunctionalityError(
          functionality: 'audio content parts with media type $mediaType',
        ),
    };
    return {
      'type': 'input_audio',
      'input_audio': {
        'data': _base64Of(data),
        'format': format,
      },
    };
  }

  if (mediaType != 'application/pdf') {
    throw UnsupportedFunctionalityError(
      functionality: 'file part media type $mediaType',
    );
  }
  if (data is FileDataUrl) {
    throw const UnsupportedFunctionalityError(
      functionality: 'PDF file parts with URLs',
    );
  }

  return {
    'type': 'file',
    'file': {
      'filename': filename ?? 'part-$index.pdf',
      'file_data': 'data:application/pdf;base64,${_base64Of(data)}',
    },
  };
}

/// image_url.url 取值:远程 URL 原样透传;base64/bytes 来源统一补全
/// `data:<mediaType>;base64,` 前缀(见本文件头注释的上游偏离说明)。
String _imageUrl(FileData data, String mediaType) {
  if (data is FileDataUrl) {
    return data.url.toString();
  }
  return 'data:$mediaType;base64,${_base64Of(data)}';
}

String _base64Of(FileData data) {
  return switch (data) {
    FileDataBytes(:final bytes) => base64Encode(bytes),
    FileDataBase64(:final base64) => base64,
    _ => throw UnsupportedFunctionalityError(
        functionality: 'file data variant ${data.runtimeType}',
      ),
  };
}

Map<String, Object?> _convertAssistantMessage(
  List<AssistantContentPart> content,
) {
  var text = '';
  final toolCalls = <Map<String, Object?>>[];

  for (final part in content) {
    switch (part) {
      case TextPart(text: final partText):
        text += partText;
      case ToolCallPart(:final toolCallId, :final toolName, :final input):
        toolCalls.add({
          'id': toolCallId,
          'type': 'function',
          'function': {
            'name': toolName,
            'arguments': jsonEncode(input ?? const <String, Object?>{}),
          },
        });
      // reasoning/文件/自定义/工具结果等 part 在 chat wire 静默丢弃:
      // OpenAI Chat Completions 协议本身不支持把这些内容回传给下一轮请求。
      case ReasoningPart():
      case ReasoningFilePart():
      case CustomPart():
      case FilePart():
      case ToolApprovalRequestPart():
      case ToolResultPart():
    }
  }

  return {
    'role': 'assistant',
    'content': toolCalls.isNotEmpty ? (text.isEmpty ? null : text) : text,
    if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
  };
}

List<Map<String, Object?>> _convertToolMessage(
  List<ToolContentPart> content,
) {
  final messages = <Map<String, Object?>>[];
  for (final part in content) {
    if (part is ToolApprovalResponsePart) {
      continue;
    }
    final result = part as ToolResultPart;
    final contentValue = switch (result.output) {
      ToolResultText(:final value) => value,
      ToolResultErrorText(:final value) => value,
      ToolResultExecutionDenied(:final reason) =>
        reason ?? 'Tool call execution denied.',
      ToolResultJson(:final value) => jsonEncode(value),
      ToolResultErrorJson(:final value) => jsonEncode(value),
      ToolResultContentOutput(:final items) =>
        jsonEncode(items.map(_toolResultContentItemJson).toList()),
    };
    messages.add({
      'role': 'tool',
      'tool_call_id': result.toolCallId,
      'content': contentValue,
    });
  }
  return messages;
}

/// 把 [ToolResultContentItem] 转换为 wire JSON 形状,供 `content` 类型
/// 工具结果 `jsonEncode` 为字符串。字段取舍逐字对照上游
/// `LanguageModelV4ToolResultOutput` 的 `content` 变体(`text`/`file`/
/// `custom` 三种 item),不做 chat-only 的再加工。
Map<String, Object?> _toolResultContentItemJson(ToolResultContentItem item) {
  return switch (item) {
    ToolResultTextItem(:final text) => {'type': 'text', 'text': text},
    ToolResultFileItem(:final data, :final mediaType, :final filename) => {
        'type': 'file',
        'data': _fileDataJson(data),
        'mediaType': mediaType,
        if (filename != null) 'filename': filename,
      },
    // providerOptions 是 custom item 的唯一载荷(契约 doc:「仅承载
    // providerOptions……不必丢弃或错误编码」),整 map 原样入 JSON——
    // 丢弃它该类型即完全为空(与 openai_compatible 同名函数保持一致)。
    ToolResultCustomItem(:final providerOptions) => {
        'type': 'custom',
        if (providerOptions != null) 'providerOptions': providerOptions,
      },
  };
}

/// [FileData] 的 wire JSON 形状,对照上游 `SharedV4FileData` 判别联合。
Object? _fileDataJson(FileData data) {
  return switch (data) {
    FileDataBytes(:final bytes) => base64Encode(bytes),
    FileDataBase64(:final base64) => base64,
    FileDataUrl(:final url) => url.toString(),
    FileDataReference(:final reference) => reference,
    FileDataText(:final text) => text,
  };
}
