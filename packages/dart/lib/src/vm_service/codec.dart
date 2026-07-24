import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'models.dart';
import 'version.dart';

enum VmServiceMessageKind {
  request,
  response,
  event,
}

final class VmServiceEvent {
  const VmServiceEvent({
    required this.streamId,
    required this.kind,
    required this.value,
  });

  final String streamId;
  final VmServiceEventKind kind;
  final JsonObject value;
}

final class VmServiceDecodedMessage {
  const VmServiceDecodedMessage({
    required this.kind,
    required this.method,
    required this.envelope,
    this.result,
    this.event,
  });

  final VmServiceMessageKind kind;
  final String? method;
  final JsonObject envelope;
  final Object? result;
  final VmServiceEvent? event;
}

final class VmServiceCodec {
  const VmServiceCodec._();

  static const instance = VmServiceCodec._();

  VmServiceDecodedMessage decode(
    String message, {
    String? requestMethod,
    VmServiceWireVersion version = vmServiceCurrentRuntimeVersion,
  }) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException catch (error) {
      throw ToolingCodecError(
        'vm_service_json_invalid',
        'VM Service message is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?> || decoded['jsonrpc'] != '2.0') {
      throw const ToolingCodecError(
        'vm_service_envelope_invalid',
        'VM Service envelope must be a JSON-RPC 2.0 object.',
      );
    }
    if (decoded['method'] != null) {
      return _decodeCall(decoded, version);
    }
    if (decoded['id'] != null) {
      return _decodeResponse(decoded, requestMethod, version);
    }
    throw const ToolingCodecError(
      'vm_service_envelope_kind_unknown',
      'VM Service envelope kind is unknown.',
    );
  }

  VmServiceDecodedMessage _decodeCall(
    JsonObject envelope,
    VmServiceWireVersion version,
  ) {
    final method = envelope['method'];
    if (method is! String || method.isEmpty) {
      throw const ToolingCodecError(
        'vm_service_method_invalid',
        'VM Service method must be a non-empty string.',
      );
    }
    if (method == 'streamNotify') {
      if (envelope.containsKey('id')) {
        throw const ToolingCodecError(
          'vm_service_event_has_id',
          'VM Service streamNotify event must not contain an id.',
        );
      }
      final event = _validateEvent(envelope['params'], version);
      return VmServiceDecodedMessage(
        kind: VmServiceMessageKind.event,
        method: method,
        envelope: _freeze(envelope),
        event: event,
      );
    }
    _validateId(envelope['id']);
    VmServiceModelRegistry.instance.validateParams(
      method,
      envelope['params'],
      version: version,
    );
    return VmServiceDecodedMessage(
      kind: VmServiceMessageKind.request,
      method: method,
      envelope: _freeze(envelope),
    );
  }

  VmServiceDecodedMessage _decodeResponse(
    JsonObject envelope,
    String? requestMethod,
    VmServiceWireVersion version,
  ) {
    _validateId(envelope['id']);
    if (requestMethod == null) {
      throw const ToolingCodecError(
        'vm_service_response_method_required',
        'VM Service response requires its correlated request method.',
      );
    }
    final hasResult = envelope.containsKey('result');
    final hasError = envelope.containsKey('error');
    if (hasResult == hasError) {
      throw const ToolingCodecError(
        'vm_service_response_outcome_invalid',
        'VM Service response requires exactly one result or error.',
      );
    }
    Object? result;
    if (hasError) {
      _validateError(envelope['error']);
    } else {
      result = VmServiceModelRegistry.instance.validateResult(
        requestMethod,
        envelope['result'],
        version: version,
      );
    }
    return VmServiceDecodedMessage(
      kind: VmServiceMessageKind.response,
      method: requestMethod,
      envelope: _freeze(envelope),
      result: result,
    );
  }

  VmServiceEvent _validateEvent(
    Object? value,
    VmServiceWireVersion version,
  ) {
    if (value is! Map<String, Object?> ||
        value['streamId'] is! String ||
        value['event'] is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'vm_service_event_invalid',
        'VM Service streamNotify params are malformed.',
      );
    }
    final event = value['event']! as Map<String, Object?>;
    if (event['type'] != 'Event' ||
        event['kind'] is! String ||
        event['timestamp'] is! int) {
      throw const ToolingSchemaError(
        'vm_service_event_invalid',
        'VM Service event requires type, kind, and timestamp.',
      );
    }
    return VmServiceEvent(
      streamId: value['streamId']! as String,
      kind: VmServiceModelRegistry.instance.validateEventKind(
        event['kind']! as String,
        version: version,
      ),
      value: _freeze(event),
    );
  }

  void _validateError(Object? value) {
    if (value is! Map<String, Object?> ||
        value['code'] is! int ||
        value['message'] is! String ||
        value['data'] != null && value['data'] is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'vm_service_error_invalid',
        'VM Service JSON-RPC error is malformed.',
      );
    }
    _freeze(value);
  }

  void _validateId(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const ToolingCodecError(
        'vm_service_id_invalid',
        'VM Service request id must be a non-empty string.',
      );
    }
  }
}

JsonObject _freeze(Map<String, Object?> value) {
  try {
    return freezeJsonObject(value);
  } on Object catch (error) {
    throw ToolingSchemaError(
      'vm_service_json_value_invalid',
      'VM Service envelope is not JSON-safe.',
      cause: error,
    );
  }
}
