import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'method.dart';
import 'models.dart';

enum DtdMessageKind {
  request,
  response,
  notification,
}

final class DtdDecodedMessage {
  const DtdDecodedMessage({
    required this.kind,
    required this.method,
    required this.envelope,
  });

  final DtdMessageKind kind;
  final String? method;
  final JsonObject envelope;

  String encode() => jsonEncode(envelope);
}

final class DtdCodec {
  const DtdCodec._();

  static const instance = DtdCodec._();

  DtdDecodedMessage decode(String message, {String? requestMethod}) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException catch (error) {
      throw ToolingCodecError(
        'dtd_json_invalid',
        'DTD message is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?> || decoded['jsonrpc'] != '2.0') {
      throw const ToolingCodecError(
        'dtd_envelope_invalid',
        'DTD envelope must be a JSON-RPC 2.0 object.',
      );
    }
    if (decoded['method'] != null) {
      return _decodeCall(decoded);
    }
    if (decoded['id'] != null) {
      return _decodeResponse(decoded, requestMethod);
    }
    throw const ToolingCodecError(
      'dtd_envelope_kind_unknown',
      'DTD envelope kind is unknown.',
    );
  }

  DtdDecodedMessage _decodeCall(JsonObject envelope) {
    final method = envelope['method'];
    if (method is! String || method.isEmpty) {
      throw const ToolingCodecError(
        'dtd_method_invalid',
        'DTD method must be a non-empty string.',
      );
    }
    final descriptor = DtdModelRegistry.instance.method(method);
    final hasId = envelope.containsKey('id');
    if (hasId) {
      _validateId(envelope['id']);
      if (descriptor?.kind == DtdMethodKind.notification) {
        throw const ToolingCodecError(
          'dtd_notification_has_id',
          'DTD fixed notification must not contain an id.',
        );
      }
    } else if (descriptor?.kind != DtdMethodKind.notification) {
      throw const ToolingCodecError(
        'dtd_request_id_missing',
        'DTD request must contain an id.',
      );
    }
    DtdModelRegistry.instance.validateParams(method, envelope['params']);
    return DtdDecodedMessage(
      kind: hasId ? DtdMessageKind.request : DtdMessageKind.notification,
      method: method,
      envelope: _freeze(envelope),
    );
  }

  DtdDecodedMessage _decodeResponse(
    JsonObject envelope,
    String? requestMethod,
  ) {
    _validateId(envelope['id']);
    if (requestMethod == null) {
      throw const ToolingCodecError(
        'dtd_response_method_required',
        'DTD response requires its correlated request method.',
      );
    }
    final hasResult = envelope.containsKey('result');
    final hasError = envelope.containsKey('error');
    if (hasResult == hasError) {
      throw const ToolingCodecError(
        'dtd_response_outcome_invalid',
        'DTD response requires exactly one result or error.',
      );
    }
    if (hasError) {
      _validateError(envelope['error']);
    } else {
      DtdModelRegistry.instance.validateResult(
        requestMethod,
        envelope['result'],
      );
    }
    return DtdDecodedMessage(
      kind: DtdMessageKind.response,
      method: requestMethod,
      envelope: _freeze(envelope),
    );
  }

  void _validateError(Object? value) {
    if (value is! Map<String, Object?> ||
        value['code'] is! int ||
        value['message'] is! String ||
        value['data'] is! Map<String, Object?>) {
      throw const ToolingSchemaError(
        'dtd_error_invalid',
        'DTD JSON-RPC error must contain code, message, and object data.',
      );
    }
    DtdErrorCode.parse(value['code']! as int);
    _freeze(value);
  }

  void _validateId(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const ToolingCodecError(
        'dtd_id_invalid',
        'DTD request id must be a non-empty string.',
      );
    }
  }
}

JsonObject _freeze(Map<String, Object?> value) {
  try {
    return freezeJsonObject(value);
  } on Object catch (error) {
    throw ToolingSchemaError(
      'dtd_json_value_invalid',
      'DTD envelope is not JSON-safe.',
      cause: error,
    );
  }
}
