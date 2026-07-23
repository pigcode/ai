import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// A value failed the pinned ACP stable-v1 schema.
final class AcpSchemaException extends ProtocolException {
  const AcpSchemaException(
    super.code,
    super.message, {
    this.definition,
    this.root,
    this.instancePath,
    super.cause,
  });

  final String? definition;
  final String? root;
  final String? instancePath;

  @override
  String toString() => 'AcpSchemaException($code): $message';
}

/// An envelope violated ACP stable role or method rules.
final class AcpCodecException extends ProtocolException {
  const AcpCodecException(
    super.code,
    super.message, {
    this.method,
    super.cause,
  });

  final String? method;

  @override
  String toString() => 'AcpCodecException($code): $message';
}

/// ACP connection lifecycle was used out of order.
final class AcpStateException extends ProtocolException {
  const AcpStateException(super.code, super.message);

  @override
  String toString() => 'AcpStateException($code): $message';
}

/// ACP wire protocol version 1 could not be negotiated.
final class AcpVersionException extends ProtocolException {
  const AcpVersionException({
    required this.receivedVersion,
  }) : super(
          'acp_protocol_version_mismatch',
          'ACP peer did not negotiate protocol version 1.',
        );

  final int? receivedVersion;

  @override
  String toString() => 'AcpVersionException($code)';
}

/// An optional ACP operation lacks a negotiated capability.
final class AcpCapabilityException extends ProtocolException {
  const AcpCapabilityException(
    super.code,
    super.message, {
    required this.method,
  });

  final String method;

  @override
  String toString() => 'AcpCapabilityException($code): $method';
}

/// Advertised capabilities and registered handlers are inconsistent.
final class AcpHandlerException extends ProtocolException {
  AcpHandlerException(
    super.code,
    super.message, {
    required Iterable<String> methods,
  }) : methods = List<String>.unmodifiable(methods);

  final List<String> methods;

  @override
  String toString() => 'AcpHandlerException($code)';
}
