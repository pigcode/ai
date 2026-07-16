import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'content_part.dart';
import 'model_message.dart';

/// 把契约面 prompt 转回 pigcode_ai 用户面消息列表。
///
/// prepareStep 的公共回调使用用户面 [ModelMessage],但循环内部仍以 provider
/// prompt 执行;该转换用于给回调提供当前 step 的只读快照。
List<ModelMessage> convertFromLanguageModelPrompt(
  Iterable<provider.LanguageModelMessage> messages,
) {
  return List<ModelMessage>.unmodifiable(messages.map(_fromMessage));
}

ModelMessage _fromMessage(provider.LanguageModelMessage message) {
  return switch (message) {
    provider.SystemMessage(:final content, :final providerOptions) =>
      SystemModelMessage(content, providerOptions: providerOptions),
    provider.UserMessage(:final content, :final providerOptions) =>
      UserModelMessage(
        List<UserContentPart>.unmodifiable(content.map(_fromUserContentPart)),
        providerOptions: providerOptions,
      ),
    provider.AssistantMessage(:final content, :final providerOptions) =>
      AssistantModelMessage(
        List<AssistantContentPart>.unmodifiable(
          content.map(_fromAssistantContentPart),
        ),
        providerOptions: providerOptions,
      ),
    provider.ToolMessage(:final content, :final providerOptions) =>
      ToolModelMessage(
        List<ToolContentPart>.unmodifiable(content.map(_fromToolContentPart)),
        providerOptions: providerOptions,
      ),
  };
}

UserContentPart _fromUserContentPart(provider.UserContentPart part) {
  return switch (part) {
    provider.TextPart(:final text, :final providerOptions) =>
      TextPart(text, providerOptions: providerOptions),
    provider.FilePart(
      :final data,
      :final mediaType,
      :final filename,
      :final providerOptions,
    ) =>
      FilePart(
        data: _fromFileData(data),
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions,
      ),
  };
}

AssistantContentPart _fromAssistantContentPart(
  provider.AssistantContentPart part,
) {
  return switch (part) {
    provider.TextPart(:final text, :final providerOptions) =>
      TextPart(text, providerOptions: providerOptions),
    provider.FilePart(
      :final data,
      :final mediaType,
      :final filename,
      :final providerOptions,
    ) =>
      FilePart(
        data: _fromFileData(data),
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions,
      ),
    provider.ReasoningPart(:final text, :final providerOptions) =>
      ReasoningPart(text, providerOptions: providerOptions),
    provider.ReasoningFilePart(
      :final data,
      :final mediaType,
      :final providerOptions,
    ) =>
      ReasoningFilePart(
        data: _fromFileData(data),
        mediaType: mediaType,
        providerOptions: providerOptions,
      ),
    provider.CustomPart(:final kind, :final providerOptions) =>
      CustomPart(kind, providerOptions: providerOptions),
    provider.ToolCallPart(
      :final toolCallId,
      :final toolName,
      :final input,
      :final providerExecuted,
      :final providerOptions,
    ) =>
      ToolCallPart(
        toolCallId: toolCallId,
        toolName: toolName,
        input: input,
        providerExecuted: providerExecuted,
        providerOptions: providerOptions,
      ),
    provider.ToolApprovalRequestPart(
      :final approvalId,
      :final toolCallId,
      :final providerOptions,
    ) =>
      ToolApprovalRequestPart(
        approvalId: approvalId,
        toolCallId: toolCallId,
        providerOptions: providerOptions,
      ),
    provider.ToolResultPart() => _fromToolResultPart(part),
  };
}

ToolContentPart _fromToolContentPart(provider.ToolContentPart part) {
  return switch (part) {
    provider.ToolResultPart() => _fromToolResultPart(part),
    provider.ToolApprovalResponsePart(
      :final approvalId,
      :final approved,
      :final reason,
      :final providerOptions,
    ) =>
      ToolApprovalResponsePart(
        approvalId: approvalId,
        approved: approved,
        reason: reason,
        providerOptions: providerOptions,
      ),
  };
}

ToolResultPart _fromToolResultPart(provider.ToolResultPart part) {
  return ToolResultPart(
    toolCallId: part.toolCallId,
    toolName: part.toolName,
    output: part.output,
    providerOptions: part.providerOptions,
  );
}

DataContent _fromFileData(provider.FileData data) {
  return switch (data) {
    provider.FileDataBytes(:final bytes) => DataBytes(bytes),
    provider.FileDataBase64(:final base64) => DataBase64(base64),
    provider.FileDataText(:final text) => DataText(text),
    provider.FileDataUrl(:final url) => DataUrl(url),
    provider.FileDataReference(:final reference) => DataProviderRef(reference),
  };
}
