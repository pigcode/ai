import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../prompt/content_part.dart';
import '../prompt/model_message.dart';
import 'ui_message.dart';

/// 将 UI data part 转为用户 prompt part;返回 `null` 表示跳过。
typedef ConvertUiDataPart = UserContentPart? Function(DataUiPart part);

/// 将持久化 UI 消息转换回模型 prompt 消息。
List<ModelMessage> convertToModelMessages(
  List<UiMessage> messages, {
  bool ignoreIncompleteToolCalls = false,
  ConvertUiDataPart? convertDataPart,
}) {
  final result = <ModelMessage>[];

  for (final message in messages) {
    switch (message.role) {
      case UiMessageRole.system:
        result.add(_convertSystemMessage(message));
      case UiMessageRole.user:
        final userMessage = _convertUserMessage(message, convertDataPart);
        if (userMessage != null) {
          result.add(userMessage);
        }
      case UiMessageRole.assistant:
        result.addAll(
          _convertAssistantMessage(
            message,
            ignoreIncompleteToolCalls: ignoreIncompleteToolCalls,
          ),
        );
    }
  }

  return result;
}

SystemModelMessage _convertSystemMessage(UiMessage message) {
  final buffer = StringBuffer();
  for (final part in message.parts) {
    if (part is TextUiPart) {
      buffer.write(part.text);
    }
  }
  return SystemModelMessage(buffer.toString());
}

UserModelMessage? _convertUserMessage(
  UiMessage message,
  ConvertUiDataPart? convertDataPart,
) {
  final content = <UserContentPart>[];

  for (final part in message.parts) {
    switch (part) {
      case TextUiPart():
        content.add(TextPart(
          part.text,
          providerOptions: part.providerMetadata,
        ));
      case FileUiPart():
        content.add(_toFilePart(part));
      case DataUiPart():
        final converted = convertDataPart?.call(part);
        if (converted != null) {
          content.add(converted);
        }
      case ReasoningUiPart() ||
            ReasoningFileUiPart() ||
            CustomUiPart() ||
            ToolUiPart() ||
            StepStartUiPart():
        break;
    }
  }

  if (content.isEmpty) {
    return null;
  }

  return UserModelMessage(content);
}

List<ModelMessage> _convertAssistantMessage(
  UiMessage message, {
  required bool ignoreIncompleteToolCalls,
}) {
  final result = <ModelMessage>[];
  final assistantContent = <AssistantContentPart>[];
  final toolContent = <ToolContentPart>[];
  final emittedToolResults = <String>{};

  void flushStep() {
    if (assistantContent.isNotEmpty) {
      result.add(AssistantModelMessage(List<AssistantContentPart>.of(
        assistantContent,
      )));
      assistantContent.clear();
    }
    if (toolContent.isNotEmpty) {
      result.add(ToolModelMessage(List<ToolContentPart>.of(toolContent)));
      toolContent.clear();
    }
    emittedToolResults.clear();
  }

  for (final part in message.parts) {
    switch (part) {
      case TextUiPart():
        assistantContent.add(TextPart(
          part.text,
          providerOptions: part.providerMetadata,
        ));
      case ReasoningUiPart():
        assistantContent.add(ReasoningPart(
          part.text,
          providerOptions: part.providerMetadata,
        ));
      case FileUiPart():
        assistantContent.add(_toFilePart(part));
      case ReasoningFileUiPart():
        assistantContent.add(ReasoningFilePart(
          data: DataUrl(part.url),
          mediaType: part.mediaType,
          providerOptions: part.providerMetadata,
        ));
      case CustomUiPart():
        assistantContent.add(CustomPart(
          part.kind,
          providerOptions: part.providerMetadata,
        ));
      case DataUiPart():
        break;
      case StepStartUiPart():
        flushStep();
      case ToolUiPart():
        _appendToolPart(
          part,
          assistantContent: assistantContent,
          toolContent: toolContent,
          emittedToolResults: emittedToolResults,
          ignoreIncompleteToolCalls: ignoreIncompleteToolCalls,
        );
    }
  }

  flushStep();
  return result;
}

FilePart _toFilePart(FileUiPart part) {
  final providerReference = part.providerReference;
  return FilePart(
    data: providerReference != null
        ? DataProviderRef(providerReference)
        : DataUrl(part.url),
    mediaType: part.mediaType,
    filename: part.filename,
    providerOptions: part.providerMetadata,
  );
}

void _appendToolPart(
  ToolUiPart part, {
  required List<AssistantContentPart> assistantContent,
  required List<ToolContentPart> toolContent,
  required Set<String> emittedToolResults,
  required bool ignoreIncompleteToolCalls,
}) {
  if (part.state == UiToolState.inputStreaming) {
    if (ignoreIncompleteToolCalls) {
      return;
    }
    throw provider.InvalidArgumentError(
      argument: 'messages',
      message: 'Cannot convert incomplete streaming tool call: '
          '${part.toolCallId}.',
    );
  }

  if (ignoreIncompleteToolCalls && part.state == UiToolState.inputAvailable) {
    return;
  }

  assistantContent.add(ToolCallPart(
    toolCallId: part.toolCallId,
    toolName: part.toolName,
    input: part.input,
    providerExecuted: part.providerExecuted,
    providerOptions: part.callProviderMetadata,
  ));

  final approval = part.approval;
  if (_stateMayHaveApprovalRequest(part.state) && approval != null) {
    assistantContent.add(ToolApprovalRequestPart(
      approvalId: approval.approvalId,
      toolCallId: part.toolCallId,
      providerOptions: part.callProviderMetadata,
    ));
  }

  if (approval?.approved != null) {
    toolContent.add(ToolApprovalResponsePart(
      approvalId: approval!.approvalId,
      approved: approval.approved!,
      reason: approval.reason,
      providerOptions: part.resultProviderMetadata,
    ));
  }

  if (part.state == UiToolState.outputAvailable) {
    if (part.providerExecuted == true) {
      assistantContent.add(ToolResultPart(
        toolCallId: part.toolCallId,
        toolName: part.toolName,
        output: _toToolResultOutput(part.output),
        providerOptions: part.resultProviderMetadata,
      ));
    } else {
      _appendToolResult(
        toolContent,
        emittedToolResults,
        key: 'json:${part.toolCallId}',
        result: ToolResultPart(
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output: _toToolResultOutput(part.output),
          providerOptions: part.resultProviderMetadata,
        ),
      );
    }
  }

  if (part.state == UiToolState.outputError && part.providerExecuted == true) {
    assistantContent.add(ToolResultPart(
      toolCallId: part.toolCallId,
      toolName: part.toolName,
      output: provider.ToolResultErrorText(
        part.errorText ?? 'Tool execution failed.',
      ),
      providerOptions: part.resultProviderMetadata,
    ));
  }

  if (part.state == UiToolState.outputError && part.providerExecuted != true) {
    _appendToolResult(
      toolContent,
      emittedToolResults,
      key: 'error:${part.toolCallId}',
      result: ToolResultPart(
        toolCallId: part.toolCallId,
        toolName: part.toolName,
        output: provider.ToolResultErrorText(
          part.errorText ?? 'Tool execution failed.',
        ),
        providerOptions: part.resultProviderMetadata,
      ),
    );
  }

  if (part.state == UiToolState.outputDenied) {
    final result = ToolResultPart(
      toolCallId: part.toolCallId,
      toolName: part.toolName,
      output: provider.ToolResultErrorText(
        approval?.reason ?? 'Tool call execution denied.',
      ),
      providerOptions: part.resultProviderMetadata,
    );
    if (part.providerExecuted == true) {
      assistantContent.add(result);
    } else {
      _appendToolResult(
        toolContent,
        emittedToolResults,
        key: 'denied:${part.toolCallId}',
        result: result,
      );
    }
  }

  if (part.state == UiToolState.approvalResponded &&
      approval?.approved == false) {
    _appendToolResult(
      toolContent,
      emittedToolResults,
      key: 'denied:${part.toolCallId}',
      result: ToolResultPart(
        toolCallId: part.toolCallId,
        toolName: part.toolName,
        output: provider.ToolResultExecutionDenied(reason: approval?.reason),
        providerOptions: part.resultProviderMetadata,
      ),
    );
  }
}

bool _stateMayHaveApprovalRequest(UiToolState state) {
  return switch (state) {
    UiToolState.approvalRequested ||
    UiToolState.approvalResponded ||
    UiToolState.outputAvailable ||
    UiToolState.outputError ||
    UiToolState.outputDenied =>
      true,
    UiToolState.inputStreaming || UiToolState.inputAvailable => false,
  };
}

provider.ToolResultOutput _toToolResultOutput(provider.JsonValue output) {
  return switch (output) {
    String() => provider.ToolResultText(output),
    _ => provider.ToolResultJson(output),
  };
}

void _appendToolResult(
  List<ToolContentPart> toolContent,
  Set<String> emittedToolResults, {
  required String key,
  required ToolResultPart result,
}) {
  if (!emittedToolResults.add(key)) {
    return;
  }

  toolContent.add(result);
}
