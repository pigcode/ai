import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

/// A serialized UI message stream event.
sealed class UiMessageChunk extends Equatable {
  /// Creates a UI message stream event.
  const UiMessageChunk();

  /// Converts this chunk to its stable JSON representation.
  provider.JsonObject toJson();

  /// Parses and validates a UI message stream event from JSON.
  static UiMessageChunk fromJson(provider.JsonObject json) {
    final type = _string(json, 'type');

    switch (type) {
      case 'start':
        return StartUiMessageChunk(
          messageId: _optionalString(json, 'messageId'),
          messageMetadata: _optionalObject(json, 'messageMetadata'),
        );
      case 'finish':
        return FinishUiMessageChunk(
          finishReason: _optionalFinishReason(json, 'finishReason'),
          messageMetadata: _optionalObject(json, 'messageMetadata'),
        );
      case 'abort':
        return AbortUiMessageChunk(
          reason: _optionalString(json, 'reason'),
          messageMetadata: _optionalObject(json, 'messageMetadata'),
        );
      case 'error':
        return ErrorUiMessageChunk(
          _string(json, 'errorText'),
          messageMetadata: _optionalObject(json, 'messageMetadata'),
        );
      case 'message-metadata':
        return MessageMetadataUiMessageChunk(
          _object(json, 'messageMetadata'),
        );
      case 'start-step':
        return const StartStepUiMessageChunk();
      case 'finish-step':
        return const FinishStepUiMessageChunk();
      case 'text-start':
        return TextStartUiMessageChunk(
          _string(json, 'id'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'text-delta':
        return TextDeltaUiMessageChunk(
          _string(json, 'id'),
          _string(json, 'delta'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'text-end':
        return TextEndUiMessageChunk(
          _string(json, 'id'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'reasoning-start':
        return ReasoningStartUiMessageChunk(
          _string(json, 'id'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'reasoning-delta':
        return ReasoningDeltaUiMessageChunk(
          _string(json, 'id'),
          _string(json, 'delta'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'reasoning-end':
        return ReasoningEndUiMessageChunk(
          _string(json, 'id'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-input-start':
        return ToolInputStartUiMessageChunk(
          toolCallId: _string(json, 'toolCallId'),
          toolName: _string(json, 'toolName'),
          providerExecuted: _optionalBool(json, 'providerExecuted'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-input-delta':
        return ToolInputDeltaUiMessageChunk(
          _string(json, 'toolCallId'),
          _string(json, 'inputTextDelta'),
        );
      case 'tool-input-available':
        return ToolInputAvailableUiMessageChunk(
          toolCallId: _string(json, 'toolCallId'),
          toolName: _string(json, 'toolName'),
          input: _jsonValue(json, 'input'),
          providerExecuted: _optionalBool(json, 'providerExecuted'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-approval-request':
        return ToolApprovalRequestUiMessageChunk(
          approvalId: _string(json, 'approvalId'),
          toolCallId: _string(json, 'toolCallId'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-approval-response':
        return ToolApprovalResponseUiMessageChunk(
          approvalId: _string(json, 'approvalId'),
          approved: _bool(json, 'approved'),
          reason: _optionalString(json, 'reason'),
          providerExecuted: _optionalBool(json, 'providerExecuted'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-output-available':
        return ToolOutputAvailableUiMessageChunk(
          toolCallId: _string(json, 'toolCallId'),
          output: _jsonValue(json, 'output'),
          providerExecuted: _optionalBool(json, 'providerExecuted'),
          preliminary: _optionalBool(json, 'preliminary'),
          providerMetadata: _optionalProviderMetadata(json),
        );
      case 'tool-output-error':
        return ToolOutputErrorUiMessageChunk(
          toolCallId: _string(json, 'toolCallId'),
          errorText: _string(json, 'errorText'),
          providerExecuted: _optionalBool(json, 'providerExecuted'),
          providerMetadata: _optionalProviderMetadata(json),
        );
    }

    if (type.startsWith('data-')) {
      return DataUiMessageChunk(
        type: type,
        id: _optionalString(json, 'id'),
        data: _jsonValue(json, 'data'),
        transient: _optionalBool(json, 'transient'),
      );
    }

    throw provider.InvalidArgumentError(
      argument: 'type',
      message: 'Unsupported UI message chunk type: $type.',
    );
  }
}

/// Marks the start of a UI message.
final class StartUiMessageChunk extends UiMessageChunk {
  /// Creates a start chunk.
  StartUiMessageChunk({
    this.messageId,
    provider.JsonObject? messageMetadata,
  }) : messageMetadata = messageMetadata == null
            ? null
            : _snapshotJsonObject(messageMetadata, 'messageMetadata');

  /// Optional persisted UI message id.
  final String? messageId;

  /// Optional JSON metadata attached to the whole message.
  final provider.JsonObject? messageMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'start',
        'messageId': messageId,
        'messageMetadata': messageMetadata,
      });

  @override
  List<Object?> get props => <Object?>[messageId, messageMetadata];
}

/// Marks the end of a UI message.
final class FinishUiMessageChunk extends UiMessageChunk {
  /// Creates a finish chunk.
  FinishUiMessageChunk({
    provider.LanguageModelFinishReason? finishReason,
    provider.JsonObject? messageMetadata,
  })  : finishReason = _normalizeFinishReason(finishReason),
        messageMetadata = messageMetadata == null
            ? null
            : _snapshotJsonObject(messageMetadata, 'messageMetadata');

  /// Optional model finish reason.
  final provider.LanguageModelFinishReason? finishReason;

  /// Optional JSON metadata attached to the completed message.
  final provider.JsonObject? messageMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'finish',
        'finishReason':
            finishReason == null ? null : _finishReasonToJson(finishReason!),
        'messageMetadata': messageMetadata,
      });

  @override
  List<Object?> get props => <Object?>[finishReason, messageMetadata];
}

/// Marks an aborted UI message stream.
final class AbortUiMessageChunk extends UiMessageChunk {
  /// Creates an abort chunk.
  AbortUiMessageChunk({
    this.reason,
    provider.JsonObject? messageMetadata,
  }) : messageMetadata = messageMetadata == null
            ? null
            : _snapshotJsonObject(messageMetadata, 'messageMetadata');

  /// Optional human-readable abort reason.
  final String? reason;

  /// Optional JSON metadata attached to the aborted message.
  final provider.JsonObject? messageMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'abort',
        'reason': reason,
        'messageMetadata': messageMetadata,
      });

  @override
  List<Object?> get props => <Object?>[reason, messageMetadata];
}

/// Carries a terminal UI-facing error.
final class ErrorUiMessageChunk extends UiMessageChunk {
  /// Creates an error chunk.
  ErrorUiMessageChunk(
    this.errorText, {
    provider.JsonObject? messageMetadata,
  }) : messageMetadata = messageMetadata == null
            ? null
            : _snapshotJsonObject(messageMetadata, 'messageMetadata');

  /// Human-readable error text.
  final String errorText;

  /// Optional JSON metadata attached to the errored message.
  final provider.JsonObject? messageMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'error',
        'errorText': errorText,
        'messageMetadata': messageMetadata,
      });

  @override
  List<Object?> get props => <Object?>[errorText, messageMetadata];
}

/// Carries additional message metadata after stream start.
final class MessageMetadataUiMessageChunk extends UiMessageChunk {
  /// Creates a message metadata chunk.
  MessageMetadataUiMessageChunk(provider.JsonObject messageMetadata)
      : messageMetadata = _snapshotJsonObject(
          messageMetadata,
          'messageMetadata',
        );

  /// JSON metadata to merge into the UI message.
  final provider.JsonObject messageMetadata;

  @override
  provider.JsonObject toJson() => <String, Object?>{
        'type': 'message-metadata',
        'messageMetadata': messageMetadata,
      };

  @override
  List<Object?> get props => <Object?>[messageMetadata];
}

/// Carries an application-defined JSON data part.
///
/// [type] must start with `data-`. Transient chunks are delivered to the
/// reader's data callback but are not stored in the resulting [DataUiPart].
final class DataUiMessageChunk extends UiMessageChunk {
  /// Creates an application-defined data chunk.
  DataUiMessageChunk({
    required this.type,
    required provider.JsonValue data,
    this.id,
    this.transient,
  }) : data = _snapshotJsonValue(data, 'data') {
    if (!type.startsWith('data-')) {
      throw provider.InvalidArgumentError(
        argument: 'type',
        message: 'UI data chunk type must start with "data-".',
      );
    }
  }

  /// Application-defined chunk type, prefixed with `data-`.
  final String type;

  /// Optional stable id used to update an existing data part.
  final String? id;

  /// JSON payload.
  final provider.JsonValue data;

  /// Whether this chunk should bypass persisted UI message state.
  final bool? transient;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': type,
        'id': id,
        'data': data,
        'transient': transient,
      });

  @override
  List<Object?> get props => <Object?>[type, id, data, transient];
}

/// Marks the start of an assistant step.
final class StartStepUiMessageChunk extends UiMessageChunk {
  /// Creates a start-step chunk.
  const StartStepUiMessageChunk();

  @override
  provider.JsonObject toJson() => <String, Object?>{'type': 'start-step'};

  @override
  List<Object?> get props => const <Object?>[];
}

/// Marks the end of an assistant step.
final class FinishStepUiMessageChunk extends UiMessageChunk {
  /// Creates a finish-step chunk.
  const FinishStepUiMessageChunk();

  @override
  provider.JsonObject toJson() => <String, Object?>{'type': 'finish-step'};

  @override
  List<Object?> get props => const <Object?>[];
}

/// Starts a streamed text part.
final class TextStartUiMessageChunk extends UiMessageChunk {
  /// Creates a text-start chunk.
  TextStartUiMessageChunk(this.id,
      {provider.ProviderMetadata? providerMetadata})
      : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed text part.
  final String id;

  /// Provider-specific metadata associated with the text part.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'text-start',
        'id': id,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, providerMetadata];
}

/// Appends text to a streamed text part.
final class TextDeltaUiMessageChunk extends UiMessageChunk {
  /// Creates a text-delta chunk.
  TextDeltaUiMessageChunk(
    this.id,
    this.delta, {
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed text part.
  final String id;

  /// Text delta to append.
  final String delta;

  /// Provider-specific metadata associated with the text delta.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'text-delta',
        'id': id,
        'delta': delta,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, delta, providerMetadata];
}

/// Ends a streamed text part.
final class TextEndUiMessageChunk extends UiMessageChunk {
  /// Creates a text-end chunk.
  TextEndUiMessageChunk(this.id, {provider.ProviderMetadata? providerMetadata})
      : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed text part.
  final String id;

  /// Provider-specific metadata associated with the completed text part.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'text-end',
        'id': id,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, providerMetadata];
}

/// Starts a streamed reasoning part.
final class ReasoningStartUiMessageChunk extends UiMessageChunk {
  /// Creates a reasoning-start chunk.
  ReasoningStartUiMessageChunk(
    this.id, {
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed reasoning part.
  final String id;

  /// Provider-specific metadata associated with the reasoning part.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'reasoning-start',
        'id': id,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, providerMetadata];
}

/// Appends text to a streamed reasoning part.
final class ReasoningDeltaUiMessageChunk extends UiMessageChunk {
  /// Creates a reasoning-delta chunk.
  ReasoningDeltaUiMessageChunk(
    this.id,
    this.delta, {
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed reasoning part.
  final String id;

  /// Reasoning text delta to append.
  final String delta;

  /// Provider-specific metadata associated with the reasoning delta.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'reasoning-delta',
        'id': id,
        'delta': delta,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, delta, providerMetadata];
}

/// Ends a streamed reasoning part.
final class ReasoningEndUiMessageChunk extends UiMessageChunk {
  /// Creates a reasoning-end chunk.
  ReasoningEndUiMessageChunk(
    this.id, {
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable id for the streamed reasoning part.
  final String id;

  /// Provider-specific metadata associated with the completed reasoning part.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'reasoning-end',
        'id': id,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[id, providerMetadata];
}

/// Starts streaming a tool input.
final class ToolInputStartUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-input-start chunk.
  ToolInputStartUiMessageChunk({
    required this.toolCallId,
    required this.toolName,
    this.providerExecuted,
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable tool call id.
  final String toolCallId;

  /// Tool name requested by the model.
  final String toolName;

  /// Whether the provider executed the tool call.
  final bool? providerExecuted;

  /// Provider-specific metadata associated with the tool call.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'tool-input-start',
        'toolCallId': toolCallId,
        'toolName': toolName,
        'providerExecuted': providerExecuted,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[
        toolCallId,
        toolName,
        providerExecuted,
        providerMetadata,
      ];
}

/// Appends text to a streamed tool input.
final class ToolInputDeltaUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-input-delta chunk.
  const ToolInputDeltaUiMessageChunk(this.toolCallId, this.inputTextDelta);

  /// Stable tool call id.
  final String toolCallId;

  /// Raw tool input text delta.
  final String inputTextDelta;

  @override
  provider.JsonObject toJson() => <String, Object?>{
        'type': 'tool-input-delta',
        'toolCallId': toolCallId,
        'inputTextDelta': inputTextDelta,
      };

  @override
  List<Object?> get props => <Object?>[toolCallId, inputTextDelta];
}

/// Provides the completed tool input.
final class ToolInputAvailableUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-input-available chunk.
  ToolInputAvailableUiMessageChunk({
    required this.toolCallId,
    required this.toolName,
    required provider.JsonValue input,
    this.providerExecuted,
    provider.ProviderMetadata? providerMetadata,
  })  : input = _snapshotJsonValue(input, 'input'),
        providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable tool call id.
  final String toolCallId;

  /// Tool name requested by the model.
  final String toolName;

  /// Completed JSON input payload.
  final provider.JsonValue input;

  /// Whether the provider executed the tool call.
  final bool? providerExecuted;

  /// Provider-specific metadata associated with the tool call.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() {
    final json = <String, Object?>{
      'type': 'tool-input-available',
      'toolCallId': toolCallId,
      'toolName': toolName,
      'input': input,
    };
    if (providerExecuted != null) {
      json['providerExecuted'] = providerExecuted;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }

  @override
  List<Object?> get props => <Object?>[
        toolCallId,
        toolName,
        input,
        providerExecuted,
        providerMetadata,
      ];
}

/// Requests user approval for a tool call.
final class ToolApprovalRequestUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-approval-request chunk.
  ToolApprovalRequestUiMessageChunk({
    required this.approvalId,
    required this.toolCallId,
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable approval request id.
  final String approvalId;

  /// Stable tool call id.
  final String toolCallId;

  /// Provider-specific metadata associated with the approval request.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'tool-approval-request',
        'approvalId': approvalId,
        'toolCallId': toolCallId,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[
        approvalId,
        toolCallId,
        providerMetadata,
      ];
}

/// Carries the user response to a tool approval request.
final class ToolApprovalResponseUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-approval-response chunk.
  ToolApprovalResponseUiMessageChunk({
    required this.approvalId,
    required this.approved,
    this.reason,
    this.providerExecuted,
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable approval request id.
  final String approvalId;

  /// Whether the tool call was approved.
  final bool approved;

  /// Optional reason attached to the approval response.
  final String? reason;

  /// Whether the provider executed the tool call.
  final bool? providerExecuted;

  /// Provider-specific metadata associated with the approval response.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'tool-approval-response',
        'approvalId': approvalId,
        'approved': approved,
        'reason': reason,
        'providerExecuted': providerExecuted,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[
        approvalId,
        approved,
        reason,
        providerExecuted,
        providerMetadata,
      ];
}

/// Provides a completed tool output payload.
final class ToolOutputAvailableUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-output-available chunk.
  ToolOutputAvailableUiMessageChunk({
    required this.toolCallId,
    required provider.JsonValue output,
    this.providerExecuted,
    this.preliminary,
    provider.ProviderMetadata? providerMetadata,
  })  : output = _snapshotJsonValue(output, 'output'),
        providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable tool call id.
  final String toolCallId;

  /// Completed JSON output payload.
  final provider.JsonValue output;

  /// Whether the provider executed the tool call.
  final bool? providerExecuted;

  /// Whether this output can be replaced by a later result.
  final bool? preliminary;

  /// Provider-specific metadata associated with the tool output.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() {
    final json = <String, Object?>{
      'type': 'tool-output-available',
      'toolCallId': toolCallId,
      'output': output,
    };
    if (providerExecuted != null) {
      json['providerExecuted'] = providerExecuted;
    }
    if (preliminary != null) {
      json['preliminary'] = preliminary;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }

  @override
  List<Object?> get props => <Object?>[
        toolCallId,
        output,
        providerExecuted,
        preliminary,
        providerMetadata,
      ];
}

/// Provides a failed tool output.
final class ToolOutputErrorUiMessageChunk extends UiMessageChunk {
  /// Creates a tool-output-error chunk.
  ToolOutputErrorUiMessageChunk({
    required this.toolCallId,
    required this.errorText,
    this.providerExecuted,
    provider.ProviderMetadata? providerMetadata,
  }) : providerMetadata = _snapshotProviderMetadata(providerMetadata);

  /// Stable tool call id.
  final String toolCallId;

  /// Human-readable tool error text.
  final String errorText;

  /// Whether the provider executed the tool call.
  final bool? providerExecuted;

  /// Provider-specific metadata associated with the tool error.
  final provider.ProviderMetadata? providerMetadata;

  @override
  provider.JsonObject toJson() => _withoutNulls(<String, Object?>{
        'type': 'tool-output-error',
        'toolCallId': toolCallId,
        'errorText': errorText,
        'providerExecuted': providerExecuted,
        'providerMetadata': providerMetadata,
      });

  @override
  List<Object?> get props => <Object?>[
        toolCallId,
        errorText,
        providerExecuted,
        providerMetadata,
      ];
}

provider.JsonObject _withoutNulls(provider.JsonObject json) {
  final result = <String, Object?>{...json};
  result.removeWhere((_, value) => value == null);
  return result;
}

String _string(provider.JsonObject json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw _invalidField(key, 'must be a string');
}

String? _optionalString(provider.JsonObject json, String key) {
  final value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw _invalidField(key, 'must be a string when present');
}

bool _bool(provider.JsonObject json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw _invalidField(key, 'must be a bool');
}

bool? _optionalBool(provider.JsonObject json, String key) {
  final value = json[key];
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw _invalidField(key, 'must be a bool when present');
}

provider.JsonObject _object(provider.JsonObject json, String key) {
  final value = json[key];
  if (value is Map<Object?, Object?>) {
    return _snapshotJsonObject(value, key);
  }
  throw _invalidField(key, 'must be a JSON object');
}

provider.JsonObject? _optionalObject(provider.JsonObject json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is Map<Object?, Object?>) {
    return _snapshotJsonObject(value, key);
  }
  throw _invalidField(key, 'must be a JSON object when present');
}

provider.JsonValue _jsonValue(provider.JsonObject json, String key) {
  if (json.containsKey(key)) {
    return _snapshotJsonValue(json[key], key);
  }
  throw _invalidField(key, 'is required');
}

provider.ProviderMetadata? _optionalProviderMetadata(
  provider.JsonObject json,
) {
  return _snapshotProviderMetadataFromValue(json['providerMetadata']);
}

provider.ProviderMetadata? _snapshotProviderMetadata(
  provider.ProviderMetadata? value,
) {
  return _snapshotProviderMetadataFromValue(value);
}

provider.ProviderMetadata? _snapshotProviderMetadataFromValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map<Object?, Object?>) {
    throw _invalidField('providerMetadata', 'must be a provider metadata map');
  }
  final result = <String, provider.JsonObject>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final metadata = entry.value;
    if (key is! String || metadata is! Map<Object?, Object?>) {
      throw _invalidField(
          'providerMetadata', 'must be a provider metadata map');
    }
    result[key] = _snapshotJsonObject(metadata, 'providerMetadata');
  }
  return Map<String, provider.JsonObject>.unmodifiable(result);
}

provider.JsonObject _snapshotJsonObject(
  Map<Object?, Object?> value,
  String argument,
) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw _invalidField(argument, 'must be a JSON object');
    }
    result[key] = _snapshotJsonValue(entry.value, argument);
  }
  return Map<String, Object?>.unmodifiable(result);
}

provider.JsonValue _snapshotJsonValue(
  provider.JsonValue value,
  String argument,
) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return _snapshotJsonObject(value, argument);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      value.map((item) => _snapshotJsonValue(item, argument)),
    );
  }
  throw _invalidField(argument, 'must be valid JSON');
}

String _finishReasonToJson(provider.LanguageModelFinishReason reason) {
  return switch (reason.unified) {
    provider.FinishReasonType.stop => 'stop',
    provider.FinishReasonType.length => 'length',
    provider.FinishReasonType.contentFilter => 'content-filter',
    provider.FinishReasonType.toolCalls => 'tool-calls',
    provider.FinishReasonType.error => 'error',
    provider.FinishReasonType.other => 'other',
  };
}

provider.LanguageModelFinishReason? _normalizeFinishReason(
  provider.LanguageModelFinishReason? reason,
) {
  if (reason == null) {
    return null;
  }
  return provider.LanguageModelFinishReason(reason.unified);
}

provider.LanguageModelFinishReason? _optionalFinishReason(
  provider.JsonObject json,
  String key,
) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw _invalidField(key, 'must be a finish reason string when present');
  }

  final unified = switch (value) {
    'stop' => provider.FinishReasonType.stop,
    'length' => provider.FinishReasonType.length,
    'content-filter' => provider.FinishReasonType.contentFilter,
    'tool-calls' => provider.FinishReasonType.toolCalls,
    'error' => provider.FinishReasonType.error,
    'other' => provider.FinishReasonType.other,
    _ => throw _invalidField(key, 'has an unsupported finish reason value'),
  };
  return provider.LanguageModelFinishReason(unified);
}

provider.InvalidArgumentError _invalidField(String argument, String detail) {
  return provider.InvalidArgumentError(
    argument: argument,
    message: 'UI message chunk field "$argument" $detail.',
  );
}
