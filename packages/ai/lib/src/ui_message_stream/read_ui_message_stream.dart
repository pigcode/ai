import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../generate_text/parse_partial_json.dart';
import '../ui/ui_message.dart';
import 'ui_message_chunk.dart';

/// Reads UI message chunks and emits immutable assistant message snapshots.
Stream<UiMessage> readUiMessageStream({
  required Stream<UiMessageChunk> stream,
  UiMessage? message,
  bool terminateOnError = false,
  void Function(Object error)? onError,
}) async* {
  final state = _UiMessageReadState(message);

  await for (final chunk in stream) {
    if (chunk is ErrorUiMessageChunk) {
      try {
        state.apply(chunk);
        if (chunk.messageMetadata != null) {
          yield state.snapshot();
        }
      } catch (error) {
        onError?.call(error);
        if (terminateOnError) {
          rethrow;
        }
      }
      onError?.call(chunk.errorText);
      if (terminateOnError) {
        throw provider.InvalidArgumentError(
          argument: 'errorText',
          message: chunk.errorText,
        );
      }
      continue;
    }

    try {
      state.apply(chunk);
      yield state.snapshot();
    } catch (error) {
      onError?.call(error);
      if (terminateOnError) {
        rethrow;
      }
    }
  }

  try {
    state.finishStream();
  } catch (error) {
    onError?.call(error);
    if (terminateOnError) {
      rethrow;
    }
  }
}

final class _UiMessageReadState {
  _UiMessageReadState(UiMessage? message)
      : id = message?.id ?? '',
        metadata = <String, Object?>{
          if (message?.metadata != null) ...message!.metadata!,
        },
        parts = List<UiMessagePart>.of(message?.parts ?? const []) {
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part is StepStartUiPart) {
        _resetStepToolScope();
        continue;
      }
      if (part is ToolUiPart) {
        toolParts[part.toolCallId] = i;
        final approvalId = part.approval?.approvalId;
        if (approvalId != null) {
          approvalToolCallIds[approvalId] = part.toolCallId;
        }
      }
    }
  }

  String id;
  final provider.JsonObject metadata;
  final List<UiMessagePart> parts;
  final Map<String, int> activeTextParts = <String, int>{};
  final Map<String, int> activeReasoningParts = <String, int>{};
  final Map<String, int> toolParts = <String, int>{};
  final Map<String, String> approvalToolCallIds = <String, String>{};
  final Map<String, StringBuffer> partialToolInputs = <String, StringBuffer>{};

  UiMessage snapshot() {
    return UiMessage(
      id: id,
      role: UiMessageRole.assistant,
      parts: parts,
      metadata:
          metadata.isEmpty ? null : Map<String, Object?>.unmodifiable(metadata),
    );
  }

  void apply(UiMessageChunk chunk) {
    switch (chunk) {
      case StartUiMessageChunk(:final messageId, :final messageMetadata):
        if (messageId != null) {
          id = messageId;
        }
        _mergeMetadata(messageMetadata);
      case FinishUiMessageChunk(:final messageMetadata):
        _failIfActiveToolInput();
        _mergeMetadata(messageMetadata);
        _markActiveTextDone();
        _markActiveReasoningDone();
      case AbortUiMessageChunk():
        _mergeMetadata(chunk.messageMetadata);
      case ErrorUiMessageChunk():
        _mergeMetadata(chunk.messageMetadata);
      case MessageMetadataUiMessageChunk(:final messageMetadata):
        _mergeMetadata(messageMetadata);
      case StartStepUiMessageChunk():
        _failIfActiveToolInput();
        _resetStepToolScope();
        parts.add(const StepStartUiPart());
      case FinishStepUiMessageChunk():
        break;
      case TextStartUiMessageChunk(:final id, :final providerMetadata):
        _failIfActivePart(activeTextParts, id, 'text-start');
        activeTextParts[id] = parts.length;
        parts.add(TextUiPart(
          '',
          state: UiPartState.streaming,
          providerMetadata: providerMetadata,
        ));
      case TextDeltaUiMessageChunk(
          :final id,
          :final delta,
          :final providerMetadata,
        ):
        final index = _requiredIndex(activeTextParts, id, 'text-delta');
        final part = parts[index] as TextUiPart;
        parts[index] = part.append(delta, providerMetadata: providerMetadata);
      case TextEndUiMessageChunk(:final id, :final providerMetadata):
        final index = _requiredIndex(activeTextParts, id, 'text-end');
        final part = parts[index] as TextUiPart;
        parts[index] = part.markDone(providerMetadata: providerMetadata);
        activeTextParts.remove(id);
      case ReasoningStartUiMessageChunk(:final id, :final providerMetadata):
        _failIfActivePart(activeReasoningParts, id, 'reasoning-start');
        activeReasoningParts[id] = parts.length;
        parts.add(ReasoningUiPart(
          '',
          state: UiPartState.streaming,
          providerMetadata: providerMetadata,
        ));
      case ReasoningDeltaUiMessageChunk(
          :final id,
          :final delta,
          :final providerMetadata,
        ):
        final index = _requiredIndex(
          activeReasoningParts,
          id,
          'reasoning-delta',
        );
        final part = parts[index] as ReasoningUiPart;
        parts[index] = part.append(delta, providerMetadata: providerMetadata);
      case ReasoningEndUiMessageChunk(:final id, :final providerMetadata):
        final index = _requiredIndex(
          activeReasoningParts,
          id,
          'reasoning-end',
        );
        final part = parts[index] as ReasoningUiPart;
        parts[index] = part.markDone(providerMetadata: providerMetadata);
        activeReasoningParts.remove(id);
      case ToolInputStartUiMessageChunk():
        _applyToolInputStart(chunk);
      case ToolInputDeltaUiMessageChunk():
        _applyToolInputDelta(chunk);
      case ToolInputAvailableUiMessageChunk():
        _applyToolInputAvailable(chunk);
      case ToolApprovalRequestUiMessageChunk():
        _applyToolApprovalRequest(chunk);
      case ToolApprovalResponseUiMessageChunk():
        _applyToolApprovalResponse(chunk);
      case ToolOutputAvailableUiMessageChunk():
        _applyToolOutputAvailable(chunk);
      case ToolOutputErrorUiMessageChunk():
        _applyToolOutputError(chunk);
    }
  }

  void finishStream() {
    _failIfActiveToolInput();
  }

  void _mergeMetadata(provider.JsonObject? value) {
    if (value != null) {
      metadata.addAll(value);
    }
  }

  void _markActiveTextDone() {
    for (final entry in activeTextParts.entries.toList()) {
      final part = parts[entry.value] as TextUiPart;
      parts[entry.value] = part.markDone();
      activeTextParts.remove(entry.key);
    }
  }

  void _markActiveReasoningDone() {
    for (final entry in activeReasoningParts.entries.toList()) {
      final part = parts[entry.value] as ReasoningUiPart;
      parts[entry.value] = part.markDone();
      activeReasoningParts.remove(entry.key);
    }
  }

  int _requiredIndex(Map<String, int> indexes, String id, String chunkType) {
    final index = indexes[id];
    if (index == null) {
      throw provider.InvalidArgumentError(
        argument: 'id',
        message: 'No active UI message part for $chunkType ID "$id".',
      );
    }
    return index;
  }

  void _failIfActivePart(
    Map<String, int> indexes,
    String id,
    String chunkType,
  ) {
    if (!indexes.containsKey(id)) {
      return;
    }
    throw provider.InvalidArgumentError(
      argument: 'id',
      message: 'UI message part for $chunkType ID "$id" is already active.',
    );
  }

  void _applyToolInputStart(ToolInputStartUiMessageChunk chunk) {
    if (toolParts.containsKey(chunk.toolCallId) ||
        partialToolInputs.containsKey(chunk.toolCallId)) {
      throw provider.InvalidArgumentError(
        argument: 'toolCallId',
        message:
            'Tool input for tool call ID "${chunk.toolCallId}" already exists.',
      );
    }
    var part = ToolUiPart(
      toolCallId: chunk.toolCallId,
      toolName: chunk.toolName,
      state: UiToolState.inputStreaming,
    );
    part = _withProviderExecuted(part, chunk.providerExecuted);
    part = _withCallProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(chunk.toolCallId, part);
    partialToolInputs[chunk.toolCallId] = StringBuffer();
  }

  void _applyToolInputDelta(ToolInputDeltaUiMessageChunk chunk) {
    final buffer = partialToolInputs[chunk.toolCallId];
    if (buffer == null) {
      throw provider.InvalidArgumentError(
        argument: 'toolCallId',
        message: 'No active tool input for tool call ID "${chunk.toolCallId}".',
      );
    }
    buffer.write(chunk.inputTextDelta);

    final existing = _requiredToolPart(chunk.toolCallId, 'tool-input-delta');
    final input = _partialToolInput(buffer.toString());
    _upsertToolPart(
      chunk.toolCallId,
      existing.copyWith(input: input, setInput: true),
    );
  }

  void _applyToolInputAvailable(ToolInputAvailableUiMessageChunk chunk) {
    final existing = _toolPart(chunk.toolCallId);
    if (existing != null && existing.state != UiToolState.inputStreaming) {
      throw provider.InvalidArgumentError(
        argument: 'toolCallId',
        message:
            'Tool input for tool call ID "${chunk.toolCallId}" is already complete.',
      );
    }
    var part = existing ??
        ToolUiPart(
          toolCallId: chunk.toolCallId,
          toolName: chunk.toolName,
          state: UiToolState.inputAvailable,
        );
    part = part.copyWith(
      toolName: chunk.toolName,
      state: UiToolState.inputAvailable,
      input: chunk.input,
      setInput: true,
    );
    part = _withProviderExecuted(part, chunk.providerExecuted);
    part = _withCallProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(chunk.toolCallId, part);
    partialToolInputs.remove(chunk.toolCallId);
  }

  void _applyToolApprovalRequest(ToolApprovalRequestUiMessageChunk chunk) {
    if (approvalToolCallIds.containsKey(chunk.approvalId)) {
      throw provider.InvalidArgumentError(
        argument: 'approvalId',
        message: 'Tool approval ID "${chunk.approvalId}" already exists.',
      );
    }
    final existing = _requiredToolPart(
      chunk.toolCallId,
      'tool-approval-request',
    );
    if (existing.approval != null) {
      throw provider.InvalidArgumentError(
        argument: 'toolCallId',
        message:
            'Tool call ID "${chunk.toolCallId}" already has an approval request.',
      );
    }
    _failUnlessToolState(
      existing,
      'tool-approval-request',
      const [UiToolState.inputAvailable],
    );
    var part = existing.copyWith(
      state: UiToolState.approvalRequested,
      approval: UiToolApproval(approvalId: chunk.approvalId),
    );
    part = _withCallProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(chunk.toolCallId, part);
    approvalToolCallIds[chunk.approvalId] = chunk.toolCallId;
  }

  void _applyToolApprovalResponse(ToolApprovalResponseUiMessageChunk chunk) {
    final toolCallId = _toolCallIdForApproval(chunk.approvalId);
    final existing = _requiredToolPart(toolCallId, 'tool-approval-response');
    _failUnlessToolState(
      existing,
      'tool-approval-response',
      const [UiToolState.approvalRequested],
    );
    var part = existing.copyWith(
      state: UiToolState.approvalResponded,
      approval:
          (existing.approval ?? UiToolApproval(approvalId: chunk.approvalId))
              .copyWith(
        approved: chunk.approved,
        reason: chunk.reason,
      ),
    );
    part = _withProviderExecuted(part, chunk.providerExecuted);
    part = _withResultProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(toolCallId, part);
  }

  void _applyToolOutputAvailable(ToolOutputAvailableUiMessageChunk chunk) {
    final existing = _requiredToolPart(
      chunk.toolCallId,
      'tool-output-available',
    );
    if (existing.state == UiToolState.approvalResponded &&
        existing.approval?.approved == false) {
      var part = _withProviderExecuted(existing, chunk.providerExecuted);
      part = _withResultProviderMetadata(part, chunk.providerMetadata);
      _upsertToolPart(chunk.toolCallId, part);
      return;
    }
    _failUnlessToolCanAcceptResult(existing, 'tool-output-available');
    var part = existing.copyWith(
      state: UiToolState.outputAvailable,
      output: chunk.output,
      setOutput: true,
      errorText: null,
      setErrorText: true,
      preliminary: chunk.preliminary,
    );
    part = _withProviderExecuted(part, chunk.providerExecuted);
    part = _withResultProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(chunk.toolCallId, part);
  }

  void _applyToolOutputError(ToolOutputErrorUiMessageChunk chunk) {
    final existing = _requiredToolPart(chunk.toolCallId, 'tool-output-error');
    _failUnlessToolCanAcceptResult(existing, 'tool-output-error');
    var part = existing.copyWith(
      state: UiToolState.outputError,
      output: null,
      setOutput: true,
      errorText: chunk.errorText,
      setErrorText: true,
      preliminary: null,
    );
    part = _withProviderExecuted(part, chunk.providerExecuted);
    part = _withResultProviderMetadata(part, chunk.providerMetadata);
    _upsertToolPart(chunk.toolCallId, part);
  }

  provider.JsonValue _partialToolInput(String inputText) {
    final parsed = parsePartialJson(inputText);
    if (parsed.value is provider.JsonObject) {
      return parsed.value;
    }
    return inputText;
  }

  ToolUiPart? _toolPart(String toolCallId) {
    final index = toolParts[toolCallId];
    return index == null ? null : parts[index] as ToolUiPart;
  }

  ToolUiPart _requiredToolPart(String toolCallId, String chunkType) {
    final part = _toolPart(toolCallId);
    if (part == null) {
      throw provider.InvalidArgumentError(
        argument: 'toolCallId',
        message: 'No tool invocation found for $chunkType ID "$toolCallId".',
      );
    }
    return part;
  }

  String _toolCallIdForApproval(String approvalId) {
    final toolCallId = approvalToolCallIds[approvalId];
    if (toolCallId != null) {
      return toolCallId;
    }
    throw provider.InvalidArgumentError(
      argument: 'approvalId',
      message: 'No tool invocation found for approval ID "$approvalId".',
    );
  }

  void _upsertToolPart(String toolCallId, ToolUiPart part) {
    final index = toolParts[toolCallId];
    if (index == null) {
      toolParts[toolCallId] = parts.length;
      parts.add(part);
      return;
    }
    parts[index] = part;
  }

  void _resetStepToolScope() {
    toolParts.clear();
    approvalToolCallIds.clear();
    partialToolInputs.clear();
  }

  ToolUiPart _withProviderExecuted(ToolUiPart part, bool? providerExecuted) {
    if (providerExecuted == null) {
      return part;
    }
    return part.copyWith(providerExecuted: providerExecuted);
  }

  ToolUiPart _withCallProviderMetadata(
    ToolUiPart part,
    provider.ProviderMetadata? providerMetadata,
  ) {
    if (providerMetadata == null) {
      return part;
    }
    return part.copyWith(callProviderMetadata: providerMetadata);
  }

  ToolUiPart _withResultProviderMetadata(
    ToolUiPart part,
    provider.ProviderMetadata? providerMetadata,
  ) {
    if (providerMetadata == null) {
      return part;
    }
    return part.copyWith(resultProviderMetadata: providerMetadata);
  }

  void _failUnlessToolState(
    ToolUiPart part,
    String chunkType,
    List<UiToolState> allowedStates,
  ) {
    if (allowedStates.contains(part.state)) {
      return;
    }
    throw provider.InvalidArgumentError(
      argument: 'toolCallId',
      message:
          'Tool call ID "${part.toolCallId}" cannot accept $chunkType while in state ${part.state.name}.',
    );
  }

  void _failUnlessToolCanAcceptResult(ToolUiPart part, String chunkType) {
    if (part.state == UiToolState.inputAvailable ||
        (part.state == UiToolState.approvalResponded &&
            part.approval?.approved != false) ||
        (part.state == UiToolState.outputAvailable &&
            part.preliminary == true)) {
      return;
    }

    throw provider.InvalidArgumentError(
      argument: 'toolCallId',
      message:
          'Tool call ID "${part.toolCallId}" cannot accept $chunkType while in state ${part.state.name}.',
    );
  }

  void _failIfActiveToolInput() {
    if (partialToolInputs.isEmpty) {
      return;
    }
    final toolCallId = partialToolInputs.keys.first;
    partialToolInputs.clear();
    throw provider.InvalidArgumentError(
      argument: 'toolCallId',
      message: 'Tool input stream for tool call ID "$toolCallId" is active.',
    );
  }
}
