import 'dart:convert';

import '../id/opaque_id.dart';
import '../json/canonical_json.dart';
import 'agent_event.dart';
import 'agent_event_metadata.dart';
import 'agent_event_type.dart';

const _requiredEventKeys = <String>{
  'eventId',
  'schemaVersion',
  'sessionId',
  'sequence',
  'recordedAt',
  'type',
  'causationId',
  'payload',
  'metadata',
};

const _allowedEventKeys = <String>{
  ..._requiredEventKeys,
  'runId',
  'attemptId',
  'workItemId',
};

final class AgentEventCodec {
  const AgentEventCodec._();

  static const instance = AgentEventCodec._();

  String encode(AgentEvent event) => canonicalJsonEncode(event.toJson());

  AgentEvent decode(String encoded) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException catch (error) {
      throw AgentEventCodecException(
        'invalid_event_json',
        'AgentEvent is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw AgentEventCodecException(
        'invalid_event_envelope',
        'AgentEvent must be a JSON object.',
      );
    }
    return decodeObject(decoded);
  }

  AgentEvent decodeObject(Map<String, Object?> value) {
    final missing = _requiredEventKeys.difference(value.keys.toSet());
    final unknown = value.keys.toSet().difference(_allowedEventKeys);
    if (missing.isNotEmpty || unknown.isNotEmpty) {
      throw AgentEventCodecException(
        'invalid_event_envelope',
        'AgentEvent has missing or unknown envelope fields.',
      );
    }

    try {
      final schemaVersion = _integer(value, 'schemaVersion');
      final sequence = _integer(value, 'sequence');
      final type = AgentEventType.parse(_string(value, 'type'));
      final recordedAtText = _string(value, 'recordedAt');
      final recordedAt = DateTime.tryParse(recordedAtText);
      if (recordedAt == null ||
          !recordedAt.isUtc ||
          !recordedAtText.endsWith('Z')) {
        throw AgentEventCodecException(
          'invalid_recorded_at',
          'AgentEvent recordedAt must be an RFC 3339 UTC timestamp.',
        );
      }

      return AgentEvent(
        eventId: EventId.parse(_string(value, 'eventId')),
        schemaVersion: schemaVersion,
        sessionId: SessionId.parse(_string(value, 'sessionId')),
        sequence: sequence,
        recordedAt: recordedAt,
        type: type,
        runId: _optionalId(value, 'runId', RunId.parse),
        attemptId: _optionalId(value, 'attemptId', AttemptId.parse),
        workItemId: _optionalId(value, 'workItemId', WorkItemId.parse),
        causationId: _causationId(_string(value, 'causationId')),
        payload: _object(value, 'payload'),
        metadata: AgentEventMetadata.fromJson(_object(value, 'metadata')),
      );
    } on AgentEventCodecException {
      rethrow;
    } on FormatException catch (error) {
      throw AgentEventCodecException(
        'invalid_context_id',
        'AgentEvent contains an invalid typed identifier or discriminant.',
        cause: error,
      );
    }
  }
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) {
    throw AgentEventCodecException(
      'invalid_event_field',
      'AgentEvent $key must be a string.',
    );
  }
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) {
    throw AgentEventCodecException(
      'invalid_event_field',
      'AgentEvent $key must be an integer.',
    );
  }
  return field;
}

Map<String, Object?> _object(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! Map<String, Object?>) {
    throw AgentEventCodecException(
      'invalid_event_field',
      'AgentEvent $key must be an object.',
    );
  }
  return field;
}

T? _optionalId<T extends OpaqueId>(
  Map<String, Object?> value,
  String key,
  T Function(String value) parse,
) {
  final field = value[key];
  if (field == null) {
    return null;
  }
  if (field is! String) {
    throw AgentEventCodecException(
      'invalid_context_id',
      'AgentEvent $key must be a typed identifier string.',
    );
  }
  return parse(field);
}

OpaqueId _causationId(String value) {
  if (value.startsWith('cmd_')) {
    return CommandId.parse(value);
  }
  if (value.startsWith('evt_')) {
    return EventId.parse(value);
  }
  throw AgentEventCodecException(
    'invalid_causation_id',
    'AgentEvent causationId must be a CommandId or EventId.',
  );
}
