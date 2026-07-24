import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class DapSchemaException extends ProtocolException {
  const DapSchemaException(
    super.code,
    super.message, {
    this.definition,
    this.instancePath,
    super.cause,
  });

  final String? definition;
  final String? instancePath;

  @override
  String toString() => 'DapSchemaException($code): $message';
}

final class DapCodecException extends ProtocolException {
  const DapCodecException(
    super.code,
    super.message, {
    this.name,
    super.cause,
  });

  final String? name;

  @override
  String toString() => 'DapCodecException($code): $message';
}

final class DapStateException extends ProtocolException {
  const DapStateException(super.code, super.message);

  @override
  String toString() => 'DapStateException($code): $message';
}

final class DapCapabilityException extends ProtocolException {
  const DapCapabilityException(
    super.code,
    super.message, {
    required this.command,
  });

  final String command;

  @override
  String toString() => 'DapCapabilityException($code): $command';
}

final class DapCorrelationException extends ProtocolException {
  const DapCorrelationException(super.code, super.message);

  @override
  String toString() => 'DapCorrelationException($code): $message';
}

final class DapResourceLimitException extends ProtocolException {
  const DapResourceLimitException(super.code, super.message);

  @override
  String toString() => 'DapResourceLimitException($code): $message';
}

final class DapDebugStateException extends ProtocolException {
  const DapDebugStateException(super.code, super.message);

  @override
  String toString() => 'DapDebugStateException($code): $message';
}

final class DapProgressException extends ProtocolException {
  const DapProgressException(super.code, super.message);

  @override
  String toString() => 'DapProgressException($code): $message';
}

final class DapCancellationException extends ProtocolException {
  const DapCancellationException(super.code, super.message);

  @override
  String toString() => 'DapCancellationException($code): $message';
}

final class DapProposalException extends ProtocolException {
  const DapProposalException(
    super.code,
    super.message, {
    required this.command,
    super.cause,
  });

  final String command;

  @override
  String toString() => 'DapProposalException($code): $command';
}
