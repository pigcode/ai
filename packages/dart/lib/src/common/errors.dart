import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Stable error categories shared by all Dart tooling protocol surfaces.
enum ToolingErrorFamily {
  transport,
  framing,
  codec,
  schema,
  protocolState,
  version,
  capability,
  remote,
  proposal,
  resourceLimit,
}

/// Base error for the portable Dart tooling package.
abstract class DartToolingError extends ProtocolException {
  const DartToolingError(
    super.code,
    super.message, {
    required this.family,
    super.cause,
  });

  final ToolingErrorFamily family;

  @override
  String toString() => 'DartToolingError(${family.name}, $code)';
}

final class ToolingTransportError extends DartToolingError {
  const ToolingTransportError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.transport);
}

final class ToolingFramingError extends DartToolingError {
  const ToolingFramingError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.framing);
}

final class ToolingCodecError extends DartToolingError {
  const ToolingCodecError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.codec);
}

final class ToolingSchemaError extends DartToolingError {
  const ToolingSchemaError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.schema);
}

final class ToolingProtocolStateError extends DartToolingError {
  const ToolingProtocolStateError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.protocolState);
}

final class ToolingVersionError extends DartToolingError {
  const ToolingVersionError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.version);
}

final class ToolingCapabilityError extends DartToolingError {
  const ToolingCapabilityError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.capability);
}

final class ToolingRemoteError extends DartToolingError {
  const ToolingRemoteError(
    super.code,
    super.message, {
    required this.remoteCode,
    super.cause,
  }) : super(family: ToolingErrorFamily.remote);

  final Object remoteCode;
}

final class ToolingProposalError extends DartToolingError {
  const ToolingProposalError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.proposal);
}

final class ToolingResourceLimitError extends DartToolingError {
  const ToolingResourceLimitError(super.code, super.message, {super.cause})
      : super(family: ToolingErrorFamily.resourceLimit);
}
