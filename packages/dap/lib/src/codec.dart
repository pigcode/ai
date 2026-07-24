import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';
import 'models.dart';

enum DapMessageType {
  request,
  response,
  event,
}

final class DapDecodedMessage {
  const DapDecodedMessage({
    required this.type,
    required this.name,
    required this.envelope,
    this.requestDescriptor,
    this.eventDescriptor,
  });

  final DapMessageType type;
  final String name;
  final JsonObject envelope;
  final DapRequestDescriptor? requestDescriptor;
  final DapEventDescriptor? eventDescriptor;

  JsonObject toJson() => envelope;
}

final class DapCodec {
  const DapCodec._();

  static const DapCodec instance = DapCodec._();

  DapDecodedMessage decode(
    String source, {
    String? requestCommand,
  }) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DapCodecException(
        'dap_malformed_json',
        'DAP message is not valid JSON.',
        cause: error,
      );
    }
    late final JsonValue frozen;
    try {
      frozen = freezeJsonValue(decoded);
    } on JsonValueException catch (error) {
      throw DapCodecException(
        'dap_invalid_json',
        'DAP message is not JSON-compatible.',
        cause: error,
      );
    }
    if (frozen is! JsonObject) {
      throw const DapCodecException(
        'dap_invalid_envelope',
        'DAP message must be an object.',
      );
    }
    final sequence = frozen['seq'];
    if (sequence is! int || sequence < 1) {
      throw const DapCodecException(
        'dap_invalid_seq',
        'DAP seq must be a positive integer.',
      );
    }
    return switch (frozen['type']) {
      'request' => _decodeRequest(frozen),
      'response' => _decodeResponse(frozen, requestCommand),
      'event' => _decodeEvent(frozen),
      _ => throw const DapCodecException(
          'dap_unknown_type',
          'DAP type must be request, response, or event.',
        ),
    };
  }

  String encode(DapDecodedMessage message) => jsonEncode(message.envelope);

  DapDecodedMessage _decodeRequest(JsonObject envelope) {
    final command = envelope['command'];
    if (command is! String) {
      throw const DapCodecException(
        'dap_request_command_invalid',
        'DAP request command must be a string.',
      );
    }
    final descriptor = dapRequestsByCommand[command];
    if (descriptor == null) {
      throw DapCodecException(
        'dap_request_command_unknown',
        'DAP request command is not in the pinned inventory.',
        name: command,
      );
    }
    final validated = DapModelRegistry.instance.validateNamed(
      descriptor.requestDefinition,
      envelope,
    )! as JsonObject;
    return DapDecodedMessage(
      type: DapMessageType.request,
      name: command,
      envelope: validated,
      requestDescriptor: descriptor,
    );
  }

  DapDecodedMessage _decodeResponse(
    JsonObject envelope,
    String? requestCommand,
  ) {
    if (requestCommand == null) {
      throw const DapCodecException(
        'dap_response_command_required',
        'DAP responses require their correlated request command.',
      );
    }
    final descriptor = dapRequestsByCommand[requestCommand];
    if (descriptor == null) {
      throw DapCodecException(
        'dap_request_command_unknown',
        'DAP response command is not in the pinned inventory.',
        name: requestCommand,
      );
    }
    if (envelope['command'] != requestCommand) {
      throw DapCodecException(
        'dap_response_command_mismatch',
        'DAP response command does not match the pending request.',
        name: requestCommand,
      );
    }
    final requestSequence = envelope['request_seq'];
    if (requestSequence is! int || requestSequence < 1) {
      throw const DapCodecException(
        'dap_response_request_seq_invalid',
        'DAP request_seq must be a positive integer.',
      );
    }
    final validated = DapModelRegistry.instance.validateNamed(
      descriptor.responseDefinition,
      envelope,
    )! as JsonObject;
    return DapDecodedMessage(
      type: DapMessageType.response,
      name: requestCommand,
      envelope: validated,
      requestDescriptor: descriptor,
    );
  }

  DapDecodedMessage _decodeEvent(JsonObject envelope) {
    final event = envelope['event'];
    if (event is! String) {
      throw const DapCodecException(
        'dap_event_name_invalid',
        'DAP event name must be a string.',
      );
    }
    final descriptor = dapEventsByName[event];
    if (descriptor == null) {
      throw DapCodecException(
        'dap_event_name_unknown',
        'DAP event is not in the pinned inventory.',
        name: event,
      );
    }
    final validated = DapModelRegistry.instance.validateNamed(
      descriptor.definition,
      envelope,
    )! as JsonObject;
    return DapDecodedMessage(
      type: DapMessageType.event,
      name: event,
      envelope: validated,
      eventDescriptor: descriptor,
    );
  }
}
