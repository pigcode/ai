import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// [convertToOpenAiCompatibleChatMessages] 的返回值:wire 消息数组 + 转换期
/// 告警。
final class OpenAiCompatibleChatMessagesResult {
  const OpenAiCompatibleChatMessagesResult({
    required this.messages,
    required this.warnings,
  });

  /// 已转换的 OpenAI 兼容 chat 消息数组,每个元素是一条消息的 JSON 形状。
  final List<Map<String, Object?>> messages;

  /// 转换期间产生的告警。本包目前所有分支都不产出 warning(与 openai 包
  /// `systemMessageMode: remove` 场景不同,本包无该概念),保留该字段是为了
  /// 与结果类型的既定形状(及未来可能新增的告警场景)保持一致。
  final List<Warning> warnings;
}

/// 把契约层 [LanguageModelPrompt] 转换为 OpenAI 兼容 Chat Completions 的
/// `messages` 数组。
///
/// wire 语义逐字对照 v7 `convertToOpenAICompatibleChatMessages`
/// (`raw/compatible__convert-to-openai-compatible-chat-messages.ts`)。与
/// `pigcode_ai_openai` 的 chat 版本相比,差异面集中在:无 `systemMessageMode`
/// (system 恒 `role: 'system'`)、file reference 一律不支持(直接 throw)、
/// 多出 `topLevel == 'text'` 的通用文本媒体分支、PDF 默认文件名
/// `'document.pdf'`(而非按 index 兜底)、assistant `reasoning` part 累积
/// 回传进 `reasoning_content`(而非静默丢弃)。
///
/// [providerOptionsName] 决定消息级与 part 级 `providerOptions` 透传读取哪个
/// provider key。v7 raw 在此处固定读 `'openaiCompatible'` 键
/// (`getOpenAIMetadata`);本包在单一 key 设计下改读 [providerOptionsName]
/// (与 `chat_options.dart`/provider 工厂的 `name` 参数取齐,同一实例整体只认
/// 一个 provider key)——这是相对 raw 的**主动偏离点**。
///
/// 例外:assistant tool-call part 的 Google Gemini `thoughtSignature` 回传优先
/// 读 [providerOptionsName] 键,读不到时兜底读固定 `'google'` 键。
///
/// 这是相对 raw 的**再一次主动偏离**(在已裁决的单 key 设计之上叠加):raw
/// 输出侧(`openai-compatible-chat-language-model.ts` ~386 行)把
/// thoughtSignature 写在 `[metadataKey]` 键下(即 provider 名本身),但输入侧
/// (`convert-to-openai-compatible-chat-messages.ts` ~199 行)回读时固定认
/// `'google'` 键——raw 自身对同一份数据的写入键与回读键不一致,导致核心工具
/// 循环把 `ToolCall.providerMetadata` 整体透传为下一轮 `part.providerOptions`
/// 时无法读回签名(raw 自己的往返路径已断裂;其输入侧注释「Include
/// extra_content for Google Gemini thought signatures」表明机制意图正是支持
/// 跨轮重放)。按「不照抄疑似 bug」先例主动修正:优先读
/// [providerOptionsName] 键(与本包输出侧取齐,补上断裂的往返路径),读不到
/// 时兜底读 `'google'` 键(兼容调用方按 v7 既有形状手工挂载的场景)。
/// [providerOptionsName] 键存在时优先,两键都存在时 [providerOptionsName]
/// 键胜出。
///
/// 第三处相对 raw 的**主动偏离**:`ToolMessage` 的消息级 `providerOptions`
/// 会展开进每条 `role: 'tool'` wire 消息,与 system/user/assistant 三分支
/// 展开消息级 metadata 的方式保持一致。如实说明:raw 的 `tool` 分支
/// (`convert-to-openai-compatible-chat-messages.ts` ~235-267 行)只展开
/// part 级 `getOpenAIMetadata(toolResponse)`,从未读取外层按消息计算一次的
/// `metadata`(该分支是唯一未使用外层 `metadata` 变量的角色分支)——这是
/// raw 自身在四种角色间不一致的处理,不是本包误读。契约层 [ToolMessage]
/// 本就声明了消息级 `providerOptions` 字段,若该分支静默丢弃它,调用方按
/// 其他三种角色的既有心智模型设置该字段时会诧异地发现被丢弃;故本包按
/// 「不照抄疑似遗漏」先例主动补齐,消息级与 part 级两者都展开(part 级
/// 后写、可覆盖同名消息级键,顺序对齐已有 `_convertUserMessage` 单 part
/// 快路径同款的「消息级 + part 级」叠加约定)。
///
/// 第四处相对 raw 的**主动偏离**(同一先例的延伸):[ToolResultOutput]
/// 各变体自身的输出级 `providerOptions`(契约在 v7 同名字段上声明,
/// 工具的 `toModelOutput` 可直接携带)也展开进对应 wire 消息——raw 的
/// tool 分支同样从不消费该字段,但契约声明的字段静默丢弃与消息级同理;
/// 展开顺序由外到内:消息级 → part 级 → 输出级(最贴近数据者最后写、
/// 同键胜出)。
///
/// 第五处相对 raw 的**主动偏离**(同一先例):user 消息的单 text 快路径
/// 也展开消息级 metadata——raw 的快路径(~45-51 行)唯独丢弃外层已算好
/// 的消息级 metadata、只展开 part 级,同一角色的两条路径行为不一致,
/// 调用方无法预期「加一个 image part 就有 cache 控制、纯文本就没有」。
OpenAiCompatibleChatMessagesResult convertToOpenAiCompatibleChatMessages({
  required LanguageModelPrompt prompt,
  required String providerOptionsName,
}) {
  final messages = <Map<String, Object?>>[];
  final warnings = <Warning>[];

  for (final message in prompt) {
    switch (message) {
      case SystemMessage(:final content, :final providerOptions):
        messages.add({
          'role': 'system',
          'content': content,
          ..._passthroughMetadata(providerOptions, providerOptionsName),
        });
      case UserMessage(:final content, :final providerOptions):
        messages.add(
          _convertUserMessage(content, providerOptions, providerOptionsName),
        );
      case AssistantMessage(:final content, :final providerOptions):
        messages.add(
          _convertAssistantMessage(
            content,
            providerOptions,
            providerOptionsName,
          ),
        );
      case ToolMessage(:final content, :final providerOptions):
        messages.addAll(
          _convertToolMessage(content, providerOptions, providerOptionsName),
        );
    }
  }

  return OpenAiCompatibleChatMessagesResult(
    messages: messages,
    warnings: warnings,
  );
}

/// 提取 [providerOptions] 中 [providerOptionsName] 键对应的透传值,用于展开
/// 进 wire 消息/part 对象(对照 raw `getOpenAIMetadata`,单一 key 版)。
JsonObject _passthroughMetadata(
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  return providerOptions?[providerOptionsName] ?? const <String, Object?>{};
}

Map<String, Object?> _convertUserMessage(
  List<UserContentPart> content,
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  // 单 text part 快路径:content 直接用字符串。消息级 + part 级 metadata
  // 依次展开(第五处主动偏离,同「疑似遗漏补齐」先例):raw 快路径
  // (~45-51 行)唯独丢弃外层已算好的消息级 metadata、只展开 part 级,
  // 与同角色多 part 路径及其余三种角色全部不一致——契约声明的消息级
  // providerOptions 不应因 content 恰为单 text 而被静默丢弃。part 级
  // 后写、同键覆盖消息级,与多 part 路径的叠加约定一致。
  if (content.length == 1 && content[0] is TextPart) {
    final textPart = content[0] as TextPart;
    return {
      'role': 'user',
      'content': textPart.text,
      ..._passthroughMetadata(providerOptions, providerOptionsName),
      ..._passthroughMetadata(textPart.providerOptions, providerOptionsName),
    };
  }

  final parts = <Object?>[
    for (final part in content)
      _convertUserContentPart(part, providerOptionsName),
  ];

  return {
    'role': 'user',
    'content': parts,
    ..._passthroughMetadata(providerOptions, providerOptionsName),
  };
}

Map<String, Object?> _convertUserContentPart(
  UserContentPart part,
  String providerOptionsName,
) {
  switch (part) {
    case TextPart(:final text, :final providerOptions):
      return {
        'type': 'text',
        'text': text,
        ..._passthroughMetadata(providerOptions, providerOptionsName),
      };
    case FilePart(
        :final data,
        :final mediaType,
        :final filename,
        :final providerOptions,
      ):
      return _convertFilePart(
        data: data,
        mediaType: mediaType,
        filename: filename,
        partMetadata:
            _passthroughMetadata(providerOptions, providerOptionsName),
      );
  }
}

Map<String, Object?> _convertFilePart({
  required FileData data,
  required String mediaType,
  required String? filename,
  required JsonObject partMetadata,
}) {
  switch (data) {
    // 本包不支持任何形式的文件引用:不做 provider 名匹配尝试,直接拒绝
    // (对照 raw 65-68 行;与 openai 包解析 file_id 的行为不同)。
    case FileDataReference():
      throw const UnsupportedFunctionalityError(
        functionality: 'file parts with provider references',
      );
    case FileDataText():
      throw const UnsupportedFunctionalityError(
        functionality: 'text file parts',
      );
    // raw 的 'url'/'data' 两态在 Dart sealed FileData 上对应这三个具体类,
    // 统一按"有实际媒体内容"处理。
    case FileDataUrl():
    case FileDataBytes():
    case FileDataBase64():
      return _convertMediaFilePart(
        data: data,
        mediaType: mediaType,
        filename: filename,
        partMetadata: partMetadata,
      );
  }
}

Map<String, Object?> _convertMediaFilePart({
  required FileData data,
  required String mediaType,
  required String? filename,
  required JsonObject partMetadata,
}) {
  final topLevel = mediaType.split('/').first;

  if (topLevel == 'image') {
    // raw 本身在 image_url 分支没有 detail 字段(那是 openai 包 chat 独有
    // 的 provider 专属扩展),本包不加 imageDetail 概念,与 raw 严格取齐。
    return {
      'type': 'image_url',
      'image_url': {'url': _imageUrl(data, mediaType)},
      ...partMetadata,
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
          functionality: 'audio media type $mediaType',
        ),
    };
    return {
      'type': 'input_audio',
      'input_audio': {'data': _base64Of(data), 'format': format},
      ...partMetadata,
    };
  }

  if (topLevel == 'application') {
    if (data is FileDataUrl) {
      throw const UnsupportedFunctionalityError(
        functionality: 'PDF file parts with URLs',
      );
    }
    if (mediaType != 'application/pdf') {
      throw UnsupportedFunctionalityError(
        functionality: 'file part media type $mediaType',
      );
    }
    // filename 默认值 'document.pdf' 对照 raw 133 行,与 openai 包的
    // 'part-<index>.pdf'(按 index 兜底)不同,如实对齐 raw。
    return {
      'type': 'file',
      'file': {
        'filename': filename ?? 'document.pdf',
        'file_data': 'data:application/pdf;base64,${_base64Of(data)}',
      },
      ...partMetadata,
    };
  }

  // 本包独有分支(openai 包无对应逻辑):通用文本媒体类型直接还原为
  // {type: text}(对照 raw 140-155 行)。
  if (topLevel == 'text') {
    return {
      'type': 'text',
      'text': _textContentOf(data),
      ...partMetadata,
    };
  }

  throw UnsupportedFunctionalityError(
    functionality: 'file part media type $mediaType',
  );
}

/// image_url.url 取值:远程 URL 原样透传;base64/bytes 来源补全
/// `data:<mediaType>;base64,` 前缀(与 `pigcode_ai_openai` chat 侧一致的 data URI
/// 规范化处理)。
String _imageUrl(FileData data, String mediaType) {
  if (data is FileDataUrl) {
    return data.url.toString();
  }
  return 'data:$mediaType;base64,${_base64Of(data)}';
}

/// `topLevel == 'text'` 分支的文本内容还原(对照 raw 140-155 行):远程 URL
/// 直接用 URL 字符串本身;字节/base64 来源按 UTF-8 解码还原为文本。
String _textContentOf(FileData data) {
  return switch (data) {
    FileDataUrl(:final url) => url.toString(),
    FileDataBytes(:final bytes) => utf8.decode(bytes),
    FileDataBase64(:final base64) => utf8.decode(base64Decode(base64)),
    _ => throw UnsupportedFunctionalityError(
        functionality: 'file data variant ${data.runtimeType}',
      ),
  };
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
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  var text = '';
  var reasoning = '';
  final toolCalls = <Map<String, Object?>>[];

  for (final part in content) {
    switch (part) {
      case TextPart(text: final partText):
        text += partText;
      // reasoning 累积回传进 reasoning_content(openai 包对 ReasoningPart
      // 是静默丢弃,本包对照 raw 191-193 行累积回传)。
      case ReasoningPart(text: final partText):
        reasoning += partText;
      case ToolCallPart(
          :final toolCallId,
          :final toolName,
          :final input,
          :final providerOptions,
        ):
        final partMetadata =
            _passthroughMetadata(providerOptions, providerOptionsName);
        // TODO(thoughtSignature): 待未来支持多 provider 时抽象化(对照 raw
        // `convert-to-openai-compatible-chat-messages.ts` 197 行同款 TODO,
        // 如实保留)。
        //
        // 读取优先级(Fix 1,详见函数文档「例外」段的主动偏离说明):本包
        // 输出侧([providerOptionsName] 键)优先,读不到时兜底读固定
        // 'google' 键——前者补上工具循环跨轮重放的往返路径,后者保留对
        // 手工按 v7 既有形状挂载 providerOptions 的兼容性。
        final thoughtSignature = providerOptions?[providerOptionsName]
                ?['thoughtSignature'] ??
            providerOptions?['google']?['thoughtSignature'];
        // 空串跳过对齐 raw 的 JS truthiness(`thoughtSignature ? ... : {}`,
        // 空串在 JS 中为 falsy)——`!= null` 单独判定会把显式空串误当作有效
        // 值写入 wire(Fix 4)。
        final hasThoughtSignature =
            thoughtSignature != null && thoughtSignature.toString().isNotEmpty;
        // input 为 null 时序列化为空对象:raw 对 null 会产出字符串 "null"
        // (JSON.stringify(null)),多数 OpenAI 兼容服务端无法解析这种
        // arguments;契约层 ToolCallPart.input 是可空 JsonValue,此处沿用
        // openai 包同款防御性兜底(input ?? {}),是刻意的兼容层行为。
        toolCalls.add({
          'id': toolCallId,
          'type': 'function',
          'function': {
            'name': toolName,
            'arguments': jsonEncode(input ?? const <String, Object?>{}),
          },
          ...partMetadata,
          if (hasThoughtSignature)
            'extra_content': {
              'google': {'thought_signature': thoughtSignature.toString()},
            },
        });
      // FilePart/ReasoningFilePart/CustomPart/ToolResultPart 在 raw 的
      // assistant switch 里没有对应分支(TS 隐式 default 无操作),Chat
      // Completions 协议本身不支持把这些内容回传给下一轮请求。
      case FilePart():
      case ReasoningFilePart():
      case CustomPart():
      case ToolApprovalRequestPart():
      case ToolResultPart():
    }
  }

  return {
    'role': 'assistant',
    'content': toolCalls.isNotEmpty ? (text.isEmpty ? null : text) : text,
    if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
    if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    ..._passthroughMetadata(providerOptions, providerOptionsName),
  };
}

List<Map<String, Object?>> _convertToolMessage(
  List<ToolContentPart> content,
  ProviderOptions? providerOptions,
  String providerOptionsName,
) {
  final messages = <Map<String, Object?>>[];
  // 消息级 providerOptions 展开:与 system/user/assistant 三分支一致,
  // ToolMessage 自身的 providerOptions 也需展开进每条 wire 消息(Fix 2)。
  // part 级 providerOptions([ToolResultPart.providerOptions])独立展开在
  // 其后,后写覆盖前写(Map 字面量展开顺序即优先级),两者互不排斥。
  final messageMetadata = _passthroughMetadata(
    providerOptions,
    providerOptionsName,
  );
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
      // 三层 metadata 由外到内依次展开(函数文档「第四处主动偏离」):
      // 消息级 → part 级 → 输出级,最贴近数据者最后写、同键胜出。
      ...messageMetadata,
      ..._passthroughMetadata(result.providerOptions, providerOptionsName),
      ..._passthroughMetadata(
        _toolResultOutputProviderOptions(result.output),
        providerOptionsName,
      ),
    });
  }
  return messages;
}

/// 提取 [ToolResultOutput] 各变体自身声明的输出级 `providerOptions`
/// (契约的 sealed 基类未上提该字段,穷尽 switch 逐变体取;
/// [ToolResultContentOutput] 契约本身不带该字段——它的逐条内容项各自
/// 携带 providerOptions,不属于「输出级」,返回 null)。
ProviderOptions? _toolResultOutputProviderOptions(ToolResultOutput output) {
  return switch (output) {
    ToolResultText(:final providerOptions) => providerOptions,
    ToolResultErrorText(:final providerOptions) => providerOptions,
    ToolResultExecutionDenied(:final providerOptions) => providerOptions,
    ToolResultJson(:final providerOptions) => providerOptions,
    ToolResultErrorJson(:final providerOptions) => providerOptions,
    ToolResultContentOutput() => null,
  };
}

/// 把 [ToolResultContentItem] 转换为 wire JSON 形状,供 `content` 类型工具
/// 结果 `jsonEncode` 为字符串。逻辑与 `pigcode_ai_openai` chat 侧同名辅助函数
/// 一致(这是契约层 `ToolResultContentItem`/`FileData` 判别联合本身的通用
/// 序列化规则,非 chat-only 逻辑,两包保持一致)。
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
    // 丢弃它该类型即完全为空。
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
