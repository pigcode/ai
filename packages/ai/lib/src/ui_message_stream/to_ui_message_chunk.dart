import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../generate_text/text_stream_part.dart';
import 'ui_message_chunk.dart';

/// Maps an error event to UI-facing text.
typedef UiMessageErrorText = String Function(Object? error);

/// Default UI error text that avoids leaking internal error details.
String defaultUiMessageErrorText(Object? error) => 'An error occurred.';

/// Converts a single text stream part to a UI message chunk.
UiMessageChunk? toUiMessageChunk(
  TextStreamPart part, {
  bool sendReasoning = true,
  bool sendStart = true,
  bool sendFinish = true,
  UiMessageErrorText onError = defaultUiMessageErrorText,
  String? responseMessageId,
  provider.JsonObject? messageMetadata,
}) {
  return switch (part) {
    StartPart() => sendStart
        ? StartUiMessageChunk(
            messageId: responseMessageId,
            messageMetadata: messageMetadata,
          )
        : null,
    FinishPart(:final finishReason) => sendFinish
        ? FinishUiMessageChunk(
            finishReason: finishReason,
            messageMetadata: messageMetadata,
          )
        : null,
    AbortPart(:final reason) => AbortUiMessageChunk(
        reason: reason,
        messageMetadata: messageMetadata,
      ),
    ErrorPart(:final error) => ErrorUiMessageChunk(
        onError(error),
        messageMetadata: messageMetadata,
      ),
    StartStepPart() => const StartStepUiMessageChunk(),
    FinishStepPart() => const FinishStepUiMessageChunk(),
    TextStartPart(:final id, :final providerMetadata) =>
      TextStartUiMessageChunk(id, providerMetadata: providerMetadata),
    TextDeltaPart(:final id, :final delta, :final providerMetadata) =>
      TextDeltaUiMessageChunk(id, delta, providerMetadata: providerMetadata),
    TextEndPart(:final id, :final providerMetadata) =>
      TextEndUiMessageChunk(id, providerMetadata: providerMetadata),
    ReasoningStartPart(:final id, :final providerMetadata) => sendReasoning
        ? ReasoningStartUiMessageChunk(id, providerMetadata: providerMetadata)
        : null,
    ReasoningDeltaPart(:final id, :final delta, :final providerMetadata) =>
      sendReasoning
          ? ReasoningDeltaUiMessageChunk(
              id,
              delta,
              providerMetadata: providerMetadata,
            )
          : null,
    ReasoningEndPart(:final id, :final providerMetadata) => sendReasoning
        ? ReasoningEndUiMessageChunk(id, providerMetadata: providerMetadata)
        : null,
    ToolInputStartPart(:final id, :final toolName) =>
      ToolInputStartUiMessageChunk(toolCallId: id, toolName: toolName),
    ToolInputDeltaPart(:final id, :final delta) =>
      ToolInputDeltaUiMessageChunk(id, delta),
    ToolInputEndPart() => null,
    ToolCallStreamPart(:final toolCall) => ToolInputAvailableUiMessageChunk(
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: _decodeToolInput(toolCall.input),
        providerExecuted: toolCall.providerExecuted,
        providerMetadata: toolCall.providerMetadata,
      ),
    ToolApprovalRequestStreamPart(:final request) =>
      ToolApprovalRequestUiMessageChunk(
        approvalId: request.approvalId,
        toolCallId: request.toolCallId,
        providerMetadata: request.providerMetadata,
      ),
    ToolApprovalResponseStreamPart(:final response) =>
      ToolApprovalResponseUiMessageChunk(
        approvalId: response.approvalId,
        approved: response.approved,
        reason: response.reason,
        providerMetadata: response.providerOptions,
      ),
    ToolResultStreamPart(:final toolResult) => toolResult.isError == true
        ? ToolOutputErrorUiMessageChunk(
            toolCallId: toolResult.toolCallId,
            errorText: _toolErrorText(toolResult.result),
            providerMetadata: toolResult.providerMetadata,
          )
        : ToolOutputAvailableUiMessageChunk(
            toolCallId: toolResult.toolCallId,
            output: toolResult.result,
            preliminary: toolResult.preliminary,
            providerMetadata: toolResult.providerMetadata,
          ),
    RawStreamPart() => null,
  };
}

provider.JsonValue _decodeToolInput(String input) {
  if (input.isEmpty) {
    return const <String, Object?>{};
  }
  try {
    return jsonDecode(input) as provider.JsonValue;
  } catch (_) {
    return input;
  }
}

String _toolErrorText(Object? error) {
  if (error is String) {
    return error;
  }
  try {
    return jsonEncode(error);
  } catch (_) {
    return 'Tool execution failed.';
  }
}
