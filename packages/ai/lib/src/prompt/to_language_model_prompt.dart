import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'content_part.dart';
import 'model_message.dart';
import 'standardize_prompt.dart';

/// 把 pigcode_ai 用户面 [StandardizedPrompt] 转换为契约面
/// [provider.LanguageModelPrompt]。
///
/// 非空 `instructions` 会被转换为一条 [provider.SystemMessage] 并置于消息列表最前;
/// 之后逐条按角色转换 `messages`,逐 part 映射为契约类型。
provider.LanguageModelPrompt convertToLanguageModelPrompt(
  StandardizedPrompt p,
) {
  final result = <provider.LanguageModelMessage>[];

  final instructions = p.instructions;
  if (instructions != null) {
    result.add(provider.SystemMessage(instructions));
  }

  result.addAll(convertModelMessagesToLanguageModelPrompt(p.messages));

  return result;
}

/// 把完整的 pigcode_ai 用户面消息列表转换为契约面 prompt。
///
/// 与 [standardizePrompt] 不同,这里接受 [SystemModelMessage],供
/// prepareStep 覆盖完整 step prompt。
provider.LanguageModelPrompt convertModelMessagesToLanguageModelPrompt(
  Iterable<ModelMessage> messages,
) {
  final result = <provider.LanguageModelMessage>[];
  for (final message in messages) {
    result.add(_convertMessage(message));
  }
  return result;
}

/// 逐条转换消息;内容 part 列表用 `List.unmodifiable` 固化——转换产物会跨步
/// 复用在每步 `callOptions.prompt` 里,provider/中间件对消息内部列表的原地
/// 改动不得污染循环历史与已保留的 tracing/replay 快照。
provider.LanguageModelMessage _convertMessage(ModelMessage message) {
  return switch (message) {
    SystemModelMessage(:final content, :final providerOptions) =>
      provider.SystemMessage(
        content,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    UserModelMessage(:final content, :final providerOptions) =>
      provider.UserMessage(
        List<provider.UserContentPart>.unmodifiable(
          content.map(_toUserContentPart),
        ),
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    AssistantModelMessage(:final content, :final providerOptions) =>
      provider.AssistantMessage(
        List<provider.AssistantContentPart>.unmodifiable(
          content.map(_toAssistantContentPart),
        ),
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    ToolModelMessage(:final content, :final providerOptions) =>
      provider.ToolMessage(
        List<provider.ToolContentPart>.unmodifiable(
          content.map(_toToolContentPart),
        ),
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
  };
}

provider.UserContentPart _toUserContentPart(UserContentPart part) {
  return switch (part) {
    TextPart(:final text, :final providerOptions) => provider.TextPart(
        text,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    FilePart(
      :final data,
      :final mediaType,
      :final filename,
      :final providerOptions
    ) =>
      _toProviderFilePart(
        data: data,
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions,
      ),
  };
}

provider.AssistantContentPart _toAssistantContentPart(
  AssistantContentPart part,
) {
  return switch (part) {
    TextPart(:final text, :final providerOptions) => provider.TextPart(
        text,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    FilePart(
      :final data,
      :final mediaType,
      :final filename,
      :final providerOptions
    ) =>
      _toProviderFilePart(
        data: data,
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions,
      ),
    ReasoningPart(:final text, :final providerOptions) =>
      provider.ReasoningPart(
        text,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    ReasoningFilePart(
      :final data,
      :final mediaType,
      :final providerOptions,
    ) =>
      _toProviderReasoningFilePart(
        data: data,
        mediaType: mediaType,
        providerOptions: providerOptions,
      ),
    CustomPart(:final kind, :final providerOptions) => provider.CustomPart(
        kind,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    ToolCallPart(
      :final toolCallId,
      :final toolName,
      :final input,
      :final providerExecuted,
      :final providerOptions,
    ) =>
      provider.ToolCallPart(
        toolCallId: toolCallId,
        toolName: toolName,
        input: _snapshotJsonValue(input),
        providerExecuted: providerExecuted,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    ToolApprovalRequestPart(
      :final approvalId,
      :final toolCallId,
      :final providerOptions,
    ) =>
      provider.ToolApprovalRequestPart(
        approvalId: approvalId,
        toolCallId: toolCallId,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    ToolResultPart() => _toolResultToProvider(part),
  };
}

provider.ToolContentPart _toToolContentPart(ToolContentPart part) {
  return switch (part) {
    ToolResultPart() => _toolResultToProvider(part),
    ToolApprovalResponsePart(
      :final approvalId,
      :final approved,
      :final reason,
      :final providerOptions,
    ) =>
      provider.ToolApprovalResponsePart(
        approvalId: approvalId,
        approved: approved,
        reason: reason,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
  };
}

provider.ToolResultPart _toolResultToProvider(ToolResultPart part) {
  return provider.ToolResultPart(
    toolCallId: part.toolCallId,
    toolName: part.toolName,
    output: _snapshotToolResultOutput(part.output),
    providerOptions: _snapshotProviderOptions(part.providerOptions),
  );
}

provider.ToolResultOutput _snapshotToolResultOutput(
  provider.ToolResultOutput output,
) {
  return switch (output) {
    provider.ToolResultText(:final value, :final providerOptions) =>
      provider.ToolResultText(
        value,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultJson(:final value, :final providerOptions) =>
      provider.ToolResultJson(
        _snapshotJsonValue(value),
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultExecutionDenied(:final reason, :final providerOptions) =>
      provider.ToolResultExecutionDenied(
        reason: reason,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultErrorText(:final value, :final providerOptions) =>
      provider.ToolResultErrorText(
        value,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultErrorJson(:final value, :final providerOptions) =>
      provider.ToolResultErrorJson(
        _snapshotJsonValue(value),
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultContentOutput(:final items) =>
      provider.ToolResultContentOutput(
        List<provider.ToolResultContentItem>.unmodifiable(
          items.map(_snapshotToolResultContentItem),
        ),
      ),
  };
}

provider.ToolResultContentItem _snapshotToolResultContentItem(
  provider.ToolResultContentItem item,
) {
  return switch (item) {
    provider.ToolResultTextItem(:final text, :final providerOptions) =>
      provider.ToolResultTextItem(
        text,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultFileItem(
      :final data,
      :final mediaType,
      :final filename,
      :final providerOptions,
    ) =>
      provider.ToolResultFileItem(
        data: data,
        mediaType: mediaType,
        filename: filename,
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
    provider.ToolResultCustomItem(:final providerOptions) =>
      provider.ToolResultCustomItem(
        providerOptions: _snapshotProviderOptions(providerOptions),
      ),
  };
}

provider.FilePart _toProviderFilePart({
  required DataContent data,
  required String mediaType,
  String? filename,
  provider.ProviderOptions? providerOptions,
}) {
  final converted = _toFileData(data);
  return provider.FilePart(
    data: converted.data,
    mediaType: converted.mediaType ?? mediaType,
    filename: filename,
    providerOptions: _snapshotProviderOptions(providerOptions),
  );
}

provider.ReasoningFilePart _toProviderReasoningFilePart({
  required DataContent data,
  required String mediaType,
  provider.ProviderOptions? providerOptions,
}) {
  final converted = _toFileData(data);
  return provider.ReasoningFilePart(
    data: converted.data,
    mediaType: converted.mediaType ?? mediaType,
    providerOptions: _snapshotProviderOptions(providerOptions),
  );
}

({provider.FileData data, String? mediaType}) _toFileData(DataContent data) {
  if (data is DataUrl && data.url.scheme == 'data') {
    return _dataUrlToFileData(data.url);
  }

  return switch (data) {
    DataBytes(:final bytes) => (
        data: provider.FileDataBytes(bytes),
        mediaType: null,
      ),
    DataBase64(:final base64) => (
        data: provider.FileDataBase64(base64),
        mediaType: null,
      ),
    DataText(:final text) => (
        data: provider.FileDataText(text),
        mediaType: null,
      ),
    DataUrl(:final url) => (
        data: provider.FileDataUrl(url),
        mediaType: null,
      ),
    DataProviderRef(:final reference) => (
        data: provider.FileDataReference(reference),
        mediaType: null,
      ),
  };
}

({provider.FileData data, String? mediaType}) _dataUrlToFileData(Uri url) {
  final value = url.toString();
  final UriData uriData;
  try {
    uriData = UriData.parse(value);
  } on FormatException {
    return (data: provider.FileDataUrl(url), mediaType: null);
  }

  final mediaType = _explicitDataUrlMediaType(value);

  if (!uriData.isBase64) {
    return (
      data: provider.FileDataBytes(uriData.contentAsBytes()),
      mediaType: mediaType,
    );
  }

  final comma = value.indexOf(',');
  if (comma < 0) {
    return (data: provider.FileDataUrl(url), mediaType: null);
  }

  final payload = Uri.decodeComponent(value.substring(comma + 1));
  return (
    data: provider.FileDataBase64(base64.normalize(payload)),
    mediaType: mediaType,
  );
}

String? _explicitDataUrlMediaType(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) {
    return null;
  }

  final header = value.substring(0, comma);
  final typeSeparator = header.indexOf(':');
  if (typeSeparator < 0) {
    return null;
  }

  final mediaType = header.substring(typeSeparator + 1).split(';').first;
  return mediaType.isEmpty ? null : mediaType;
}

provider.ProviderOptions? _snapshotProviderOptions(
  provider.ProviderOptions? options,
) {
  if (options == null) {
    return null;
  }
  return Map<String, provider.JsonObject>.unmodifiable(
    options.map(
      (key, value) => MapEntry(key, _deepUnmodifiableJsonObject(value)),
    ),
  );
}

provider.JsonValue _snapshotJsonValue(provider.JsonValue value) {
  return _deepUnmodifiableJsonValue(value);
}

provider.JsonObject _deepUnmodifiableJsonObject(provider.JsonObject value) {
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _deepUnmodifiableJsonValue(value))),
  );
}

Object? _deepUnmodifiableJsonValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepUnmodifiableJsonObject(value);
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, value) =>
            MapEntry(key as String, _deepUnmodifiableJsonValue(value)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiableJsonValue));
  }
  return value;
}
