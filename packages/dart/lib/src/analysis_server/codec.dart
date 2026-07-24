import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'models.dart';
import 'version.dart';

enum AnalysisServerMessageKind {
  request,
  response,
  notification,
}

final class AnalysisServerDecodedMessage {
  const AnalysisServerDecodedMessage({
    required this.kind,
    required this.name,
    required this.envelope,
  });

  final AnalysisServerMessageKind kind;
  final String name;
  final JsonObject envelope;

  JsonObject toJson() => envelope;

  String encodeLine() => jsonEncode(envelope);
}

final class AnalysisServerCodec {
  const AnalysisServerCodec._();

  static const instance = AnalysisServerCodec._();

  AnalysisServerDecodedMessage decodeLine(
    String line, {
    String? requestMethod,
    AnalysisServerApiVersion version = analysisServerCurrentApiVersion,
  }) {
    if (line.contains('\n') || line.contains('\r')) {
      throw const ToolingFramingError(
        'analysis_server_ndjson_multiple_lines',
        'Analysis Server decoder accepts exactly one NDJSON record.',
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      throw ToolingCodecError(
        'analysis_server_json_invalid',
        'Analysis Server record is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const ToolingCodecError(
        'analysis_server_envelope_invalid',
        'Analysis Server envelope must be an object.',
      );
    }
    if (decoded.containsKey('method')) {
      return _decodeRequest(decoded, version);
    }
    if (decoded.containsKey('event')) {
      return _decodeNotification(decoded, version);
    }
    if (decoded.containsKey('id')) {
      return _decodeResponse(decoded, requestMethod, version);
    }
    throw const ToolingCodecError(
      'analysis_server_envelope_kind_unknown',
      'Analysis Server envelope kind is unknown.',
    );
  }

  AnalysisServerDecodedMessage _decodeRequest(
    JsonObject envelope,
    AnalysisServerApiVersion version,
  ) {
    _validateId(envelope['id']);
    final method = envelope['method'];
    if (method is! String) {
      throw const ToolingCodecError(
        'analysis_server_method_invalid',
        'Analysis Server request method must be a string.',
      );
    }
    AnalysisServerModelRegistry.instance.validateRequestParams(
      method,
      envelope['params'],
      version: version,
    );
    final clientRequestTime = envelope['clientRequestTime'];
    if (clientRequestTime != null && clientRequestTime is! int) {
      throw const ToolingCodecError(
        'analysis_server_client_time_invalid',
        'Analysis Server clientRequestTime must be an integer.',
      );
    }
    return AnalysisServerDecodedMessage(
      kind: AnalysisServerMessageKind.request,
      name: method,
      envelope: freezeJsonObject(envelope),
    );
  }

  AnalysisServerDecodedMessage _decodeNotification(
    JsonObject envelope,
    AnalysisServerApiVersion version,
  ) {
    final event = envelope['event'];
    if (event is! String) {
      throw const ToolingCodecError(
        'analysis_server_event_invalid',
        'Analysis Server notification event must be a string.',
      );
    }
    AnalysisServerModelRegistry.instance.validateNotificationParams(
      event,
      envelope['params'],
      version: version,
    );
    return AnalysisServerDecodedMessage(
      kind: AnalysisServerMessageKind.notification,
      name: event,
      envelope: freezeJsonObject(envelope),
    );
  }

  AnalysisServerDecodedMessage _decodeResponse(
    JsonObject envelope,
    String? requestMethod,
    AnalysisServerApiVersion version,
  ) {
    _validateId(envelope['id']);
    if (requestMethod == null) {
      throw const ToolingCodecError(
        'analysis_server_response_method_required',
        'Analysis Server response requires its correlated request method.',
      );
    }
    final error = envelope['error'];
    if (error != null) {
      if (error is! Map<String, Object?> ||
          error['code'] is! String ||
          (error['message'] != null && error['message'] is! String) ||
          (error['stackTrace'] != null && error['stackTrace'] is! String)) {
        throw const ToolingSchemaError(
          'analysis_server_error_invalid',
          'Analysis Server response error is invalid.',
        );
      }
      freezeJsonObject(error);
    } else {
      AnalysisServerModelRegistry.instance.validateResponseResult(
        requestMethod,
        envelope['result'],
        version: version,
      );
    }
    return AnalysisServerDecodedMessage(
      kind: AnalysisServerMessageKind.response,
      name: requestMethod,
      envelope: freezeJsonObject(envelope),
    );
  }

  void _validateId(Object? id) {
    if (id is! String || id.isEmpty) {
      throw const ToolingCodecError(
        'analysis_server_id_invalid',
        'Analysis Server id must be a non-empty string.',
      );
    }
  }
}
