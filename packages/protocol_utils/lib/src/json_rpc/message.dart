import '../errors.dart';
import '../json_value.dart';
import 'id.dart';

const _absent = _Absent();

final class _Absent {
  const _Absent();
}

/// A supported JSON-RPC 2.0 message.
sealed class JsonRpcMessage {
  const JsonRpcMessage();

  /// Unknown envelope fields retained as immutable JSON values.
  JsonObject get extensions;

  /// Converts this message to a deeply immutable JSON object.
  JsonObject toJson();
}

/// A JSON-RPC request.
final class JsonRpcRequest extends JsonRpcMessage {
  factory JsonRpcRequest({
    required JsonRpcId id,
    required String method,
    JsonValue params,
    JsonObject extensions = const <String, Object?>{},
  }) {
    _validateCorrelationId(id);
    return JsonRpcRequest._(
      id: id,
      method: _validateMethod(method),
      params: _freezeParams(params),
      extensions: _freezeExtensions(
        extensions,
        const <String>{'jsonrpc', 'id', 'method', 'params'},
      ),
    );
  }

  const JsonRpcRequest._({
    required this.id,
    required this.method,
    required this.params,
    required this.extensions,
  });

  final JsonRpcId id;
  final String method;

  /// Immutable object/array parameters, or null when omitted.
  final JsonValue params;

  @override
  final JsonObject extensions;

  @override
  JsonObject toJson() => freezeJsonObject(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id.toJson(),
        'method': method,
        if (params != null) 'params': params,
        ...extensions,
      });
}

/// A JSON-RPC notification.
final class JsonRpcNotification extends JsonRpcMessage {
  factory JsonRpcNotification({
    required String method,
    JsonValue params,
    JsonObject extensions = const <String, Object?>{},
  }) {
    return JsonRpcNotification._(
      method: _validateMethod(method),
      params: _freezeParams(params),
      extensions: _freezeExtensions(
        extensions,
        const <String>{'jsonrpc', 'method', 'params'},
      ),
    );
  }

  const JsonRpcNotification._({
    required this.method,
    required this.params,
    required this.extensions,
  });

  final String method;

  /// Immutable object/array parameters, or null when omitted.
  final JsonValue params;

  @override
  final JsonObject extensions;

  @override
  JsonObject toJson() => freezeJsonObject(<String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
        ...extensions,
      });
}

/// A successful JSON-RPC response.
final class JsonRpcSuccessResponse extends JsonRpcMessage {
  factory JsonRpcSuccessResponse({
    required JsonRpcId id,
    required JsonValue result,
    JsonObject extensions = const <String, Object?>{},
  }) {
    _validateCorrelationId(id);
    return JsonRpcSuccessResponse._(
      id: id,
      result: freezeJsonValue(result),
      extensions: _freezeExtensions(
        extensions,
        const <String>{'jsonrpc', 'id', 'result'},
      ),
    );
  }

  const JsonRpcSuccessResponse._({
    required this.id,
    required this.result,
    required this.extensions,
  });

  final JsonRpcId id;
  final JsonValue result;

  @override
  final JsonObject extensions;

  @override
  JsonObject toJson() => freezeJsonObject(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id.toJson(),
        'result': result,
        ...extensions,
      });
}

/// A JSON-RPC error object.
final class JsonRpcError {
  factory JsonRpcError({
    required int code,
    required String message,
    Object? data = _absent,
    JsonObject extensions = const <String, Object?>{},
  }) {
    return JsonRpcError._(
      code: code,
      message: message,
      hasData: !identical(data, _absent),
      data: identical(data, _absent) ? null : freezeJsonValue(data),
      extensions: _freezeExtensions(
        extensions,
        const <String>{'code', 'message', 'data'},
      ),
    );
  }

  const JsonRpcError._({
    required this.code,
    required this.message,
    required this.hasData,
    required this.data,
    required this.extensions,
  });

  final int code;
  final String message;
  final bool hasData;
  final JsonValue data;
  final JsonObject extensions;

  JsonObject toJson() => freezeJsonObject(<String, Object?>{
        'code': code,
        'message': message,
        if (hasData) 'data': data,
        ...extensions,
      });
}

/// A failed JSON-RPC response.
final class JsonRpcErrorResponse extends JsonRpcMessage {
  factory JsonRpcErrorResponse({
    required JsonRpcId id,
    required JsonRpcError error,
    JsonObject extensions = const <String, Object?>{},
  }) {
    return JsonRpcErrorResponse._(
      id: id,
      error: error,
      extensions: _freezeExtensions(
        extensions,
        const <String>{'jsonrpc', 'id', 'error'},
      ),
    );
  }

  const JsonRpcErrorResponse._({
    required this.id,
    required this.error,
    required this.extensions,
  });

  final JsonRpcId id;
  final JsonRpcError error;

  @override
  final JsonObject extensions;

  @override
  JsonObject toJson() => freezeJsonObject(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id.toJson(),
        'error': error.toJson(),
        ...extensions,
      });
}

String _validateMethod(String method) {
  if (method.isEmpty) {
    throw const JsonRpcException(
      'json_rpc_invalid_method',
      'JSON-RPC method must be a non-empty string.',
    );
  }
  return method;
}

void _validateCorrelationId(JsonRpcId id) {
  if (id is JsonRpcNullId) {
    throw const JsonRpcException(
      'json_rpc_invalid_id',
      'Null JSON-RPC id is allowed only on error responses.',
    );
  }
}

JsonValue _freezeParams(JsonValue params) {
  if (params == null) {
    return null;
  }
  if (params is! Map && params is! List<Object?>) {
    throw const JsonRpcException(
      'json_rpc_invalid_params',
      'JSON-RPC params must be an object or array.',
    );
  }
  try {
    return freezeJsonValue(params);
  } on JsonValueException catch (error) {
    throw JsonRpcException(
      'json_rpc_invalid_json_value',
      'JSON-RPC params contain an invalid JSON value.',
      cause: error,
    );
  }
}

JsonObject _freezeExtensions(
  JsonObject extensions,
  Set<String> reservedNames,
) {
  final conflict = extensions.keys
      .where(reservedNames.contains)
      .cast<String?>()
      .firstWhere((_) => true, orElse: () => null);
  if (conflict != null) {
    throw JsonRpcException(
      'json_rpc_reserved_extension',
      'JSON-RPC extension conflicts with reserved field: $conflict.',
    );
  }
  try {
    return freezeJsonObject(extensions);
  } on JsonValueException catch (error) {
    throw JsonRpcException(
      'json_rpc_invalid_json_value',
      'JSON-RPC extension contains an invalid JSON value.',
      cause: error,
    );
  }
}
