import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class McpSchemaException extends ProtocolException {
  const McpSchemaException(
    super.code,
    super.message, {
    this.definition,
    this.role,
    this.instancePath,
    super.cause,
  });

  final String? definition;
  final String? role;
  final String? instancePath;

  @override
  String toString() => 'McpSchemaException($code): $message';
}

final class McpCodecException extends ProtocolException {
  const McpCodecException(
    super.code,
    super.message, {
    this.method,
    super.cause,
  });

  final String? method;

  @override
  String toString() => 'McpCodecException($code): $message';
}

final class McpStateException extends ProtocolException {
  const McpStateException(super.code, super.message);

  @override
  String toString() => 'McpStateException($code): $message';
}

final class McpVersionException extends ProtocolException {
  const McpVersionException({required this.receivedVersion})
      : super(
          'mcp_protocol_version_mismatch',
          'MCP peer did not negotiate exact version 2025-11-25.',
        );

  final String? receivedVersion;

  @override
  String toString() => 'McpVersionException($code)';
}

final class McpCapabilityException extends ProtocolException {
  const McpCapabilityException(
    super.code,
    super.message, {
    required this.method,
  });

  final String method;

  @override
  String toString() => 'McpCapabilityException($code): $method';
}

final class McpHandlerException extends ProtocolException {
  McpHandlerException(
    super.code,
    super.message, {
    required Iterable<String> methods,
  }) : methods = List<String>.unmodifiable(methods);

  final List<String> methods;

  @override
  String toString() => 'McpHandlerException($code)';
}
