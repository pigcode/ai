/// Base exception for portable protocol utilities.
class ProtocolException implements Exception {
  const ProtocolException(
    this.code,
    this.message, {
    this.cause,
  });

  /// Stable machine-readable error code.
  final String code;

  /// Human-readable error description.
  final String message;

  /// Optional underlying exception. It is not included in [toString].
  final Object? cause;

  @override
  String toString() => 'ProtocolException($code): $message';
}

/// A value could not be represented as immutable JSON data.
final class JsonValueException extends ProtocolException {
  const JsonValueException(
    super.code,
    super.message, {
    super.cause,
  });

  @override
  String toString() => 'JsonValueException($code): $message';
}

/// A JSON-RPC envelope violated the supported JSON-RPC 2.0 contract.
final class JsonRpcException extends ProtocolException {
  const JsonRpcException(
    super.code,
    super.message, {
    super.cause,
  });

  @override
  String toString() => 'JsonRpcException($code): $message';
}

/// A bounded byte framer could not continue safely.
final class FramingException extends ProtocolException {
  const FramingException(
    super.code,
    super.message, {
    super.cause,
  });

  @override
  String toString() => 'FramingException($code): $message';
}

/// A caller-supplied transport failed or closed.
final class ProtocolTransportException extends ProtocolException {
  const ProtocolTransportException(
    super.code,
    super.message, {
    super.cause,
  });

  @override
  String toString() => 'ProtocolTransportException($code): $message';
}

/// Protocol work was cancelled through a protocol cancellation signal.
final class ProtocolCancellationException extends ProtocolException {
  const ProtocolCancellationException({this.reason})
      : super(
          'protocol_cancelled',
          'Protocol operation was cancelled.',
        );

  final Object? reason;

  @override
  String toString() => 'ProtocolCancellationException($code)';
}

/// Protocol work exceeded its caller-supplied deadline.
final class ProtocolTimeoutException extends ProtocolException {
  const ProtocolTimeoutException()
      : super(
          'protocol_timeout',
          'Protocol operation exceeded its deadline.',
        );

  @override
  String toString() => 'ProtocolTimeoutException($code)';
}

/// A JSON-RPC peer lifecycle or capacity contract was violated.
final class JsonRpcPeerException extends ProtocolException {
  const JsonRpcPeerException(
    super.code,
    super.message, {
    super.cause,
  });

  @override
  String toString() => 'JsonRpcPeerException($code): $message';
}

/// An error response returned by the remote JSON-RPC peer.
final class JsonRpcRemoteException extends ProtocolException {
  const JsonRpcRemoteException({
    required this.remoteCode,
    required this.remoteMessage,
    required this.hasData,
    this.data,
  }) : super(
          'json_rpc_remote_error',
          'Remote JSON-RPC request failed.',
        );

  final int remoteCode;
  final String remoteMessage;
  final bool hasData;
  final Object? data;

  @override
  String toString() => 'JsonRpcRemoteException($remoteCode)';
}

/// A request handler can throw this to return an intentional JSON-RPC error.
final class JsonRpcHandlerException implements Exception {
  const JsonRpcHandlerException({
    required this.code,
    required this.message,
    this.data,
    this.hasData = false,
  });

  final int code;
  final String message;
  final Object? data;
  final bool hasData;

  @override
  String toString() => 'JsonRpcHandlerException($code)';
}
