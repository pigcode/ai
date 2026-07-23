import 'package:equatable/equatable.dart';

import '../errors.dart';

const _maximumSafeJsonInteger = 9007199254740991;

/// An opaque JSON-RPC request/response identifier.
sealed class JsonRpcId extends Equatable {
  const JsonRpcId();

  /// Validates and converts a JSON value into a supported identifier.
  factory JsonRpcId.fromJson(Object? value) {
    if (value == null) {
      return const JsonRpcNullId();
    }
    if (value is String) {
      return JsonRpcStringId(value);
    }
    if (value is int &&
        value >= -_maximumSafeJsonInteger &&
        value <= _maximumSafeJsonInteger) {
      return JsonRpcIntegerId(value);
    }
    throw const JsonRpcException(
      'json_rpc_invalid_id',
      'JSON-RPC id must be null, a string, or a safe integer.',
    );
  }

  /// The JSON representation of this identifier.
  Object? toJson();
}

/// A string JSON-RPC identifier.
final class JsonRpcStringId extends JsonRpcId {
  factory JsonRpcStringId(String value) {
    if (value.isEmpty) {
      throw const JsonRpcException(
        'json_rpc_invalid_id',
        'JSON-RPC string id must be non-empty.',
      );
    }
    return JsonRpcStringId._(value);
  }

  const JsonRpcStringId._(this.value);

  final String value;

  @override
  String toJson() => value;

  @override
  List<Object?> get props => <Object?>[value];
}

/// An integer JSON-RPC identifier.
final class JsonRpcIntegerId extends JsonRpcId {
  factory JsonRpcIntegerId(int value) {
    if (value < -_maximumSafeJsonInteger || value > _maximumSafeJsonInteger) {
      throw const JsonRpcException(
        'json_rpc_invalid_id',
        'JSON-RPC integer id must be exactly representable by JavaScript.',
      );
    }
    return JsonRpcIntegerId._(value);
  }

  const JsonRpcIntegerId._(this.value);

  final int value;

  @override
  int toJson() => value;

  @override
  List<Object?> get props => <Object?>[value];
}

/// The null identifier used by JSON-RPC error responses.
final class JsonRpcNullId extends JsonRpcId {
  const JsonRpcNullId();

  @override
  Null toJson() => null;

  @override
  List<Object?> get props => const <Object?>[];
}
