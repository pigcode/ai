import '../id/opaque_id.dart';
import '../json/domain_json.dart';
import 'agent_event_metadata.dart';
import 'agent_event_type.dart';

const _maximumSafeSequence = 9007199254740991;

final class AgentEvent {
  AgentEvent({
    required this.eventId,
    required this.schemaVersion,
    required this.sessionId,
    required this.sequence,
    required this.recordedAt,
    required this.type,
    this.runId,
    this.attemptId,
    this.workItemId,
    required this.causationId,
    required Map<String, Object?> payload,
    required this.metadata,
  }) : payload = _freezePayload(payload) {
    _validateEnvelope();
  }

  final EventId eventId;
  final int schemaVersion;
  final SessionId sessionId;
  final int sequence;
  final DateTime recordedAt;
  final AgentEventType type;
  final RunId? runId;
  final AttemptId? attemptId;
  final WorkItemId? workItemId;
  final OpaqueId causationId;
  final Map<String, Object?> payload;
  final AgentEventMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'eventId': eventId.value,
        'schemaVersion': schemaVersion,
        'sessionId': sessionId.value,
        'sequence': sequence,
        'recordedAt': recordedAt.toIso8601String(),
        'type': type.wireName,
        if (runId != null) 'runId': runId!.value,
        if (attemptId != null) 'attemptId': attemptId!.value,
        if (workItemId != null) 'workItemId': workItemId!.value,
        'causationId': causationId.value,
        'payload': payload,
        'metadata': metadata.toJson(),
      };

  void _validateEnvelope() {
    if (schemaVersion != 1) {
      throw AgentEventCodecException(
        'unsupported_event_schema',
        'Only AgentEvent schemaVersion 1 is supported.',
      );
    }
    if (sequence <= 0 || sequence > _maximumSafeSequence) {
      throw AgentEventCodecException(
        'invalid_event_sequence',
        'AgentEvent sequence must be a positive safe integer.',
      );
    }
    if (!recordedAt.isUtc) {
      throw AgentEventCodecException(
        'invalid_recorded_at',
        'AgentEvent recordedAt must be UTC.',
      );
    }
    if (causationId is! CommandId && causationId is! EventId) {
      throw AgentEventCodecException(
        'invalid_causation_id',
        'AgentEvent causationId must be a CommandId or EventId.',
      );
    }
    if ((type.requiresRunId && runId == null) ||
        (type.requiresAttemptId && attemptId == null) ||
        (type.requiresWorkItemId && workItemId == null)) {
      throw AgentEventCodecException(
        'missing_context_id',
        'AgentEvent ${type.wireName} is missing a required context ID.',
      );
    }
    _validatePayloadContextId();
  }

  void _validatePayloadContextId() {
    final required = type.requiredPayloadId;
    if (required == null) {
      return;
    }
    final key = switch (required) {
      AgentPayloadContextId.approvalId => 'approvalId',
      AgentPayloadContextId.deferredOperationId => 'deferredOperationId',
      AgentPayloadContextId.runtimeResourceId => 'runtimeResourceId',
    };
    final value = payload[key];
    if (value is! String) {
      throw AgentEventCodecException(
        'missing_context_id',
        'AgentEvent ${type.wireName} requires payload.$key.',
      );
    }
    try {
      switch (required) {
        case AgentPayloadContextId.approvalId:
          ApprovalId.parse(value);
        case AgentPayloadContextId.deferredOperationId:
          DeferredOperationId.parse(value);
        case AgentPayloadContextId.runtimeResourceId:
          RuntimeResourceId.parse(value);
      }
    } on FormatException catch (error) {
      throw AgentEventCodecException(
        'invalid_context_id',
        'AgentEvent ${type.wireName} has an invalid payload.$key.',
        cause: error,
      );
    }
  }
}

Map<String, Object?> _freezePayload(Map<String, Object?> value) {
  try {
    final frozen = DomainJson.freeze(value)! as Map<String, Object?>;
    validateSafePersistedJson(frozen);
    return frozen;
  } on DomainJsonException catch (error) {
    throw AgentEventCodecException(
      'invalid_event_payload',
      'AgentEvent payload is not valid domain JSON.',
      cause: error,
    );
  }
}
