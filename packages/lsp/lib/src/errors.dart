import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// A value failed the pinned LSP 3.18 meta-model.
final class LspSchemaException extends ProtocolException {
  const LspSchemaException(
    super.code,
    super.message, {
    this.definition,
    this.instancePath,
    super.cause,
  });

  final String? definition;
  final String? instancePath;

  @override
  String toString() => 'LspSchemaException($code): $message';
}

/// An envelope violated LSP method, direction, or payload rules.
final class LspCodecException extends ProtocolException {
  const LspCodecException(
    super.code,
    super.message, {
    this.method,
    super.cause,
  });

  final String? method;

  @override
  String toString() => 'LspCodecException($code): $message';
}

/// The LSP connection lifecycle was used out of order.
final class LspStateException extends ProtocolException {
  const LspStateException(super.code, super.message);

  @override
  String toString() => 'LspStateException($code): $message';
}

/// An operation is unavailable in the current capability snapshot.
final class LspCapabilityException extends ProtocolException {
  const LspCapabilityException(
    super.code,
    super.message, {
    required this.method,
  });

  final String method;

  @override
  String toString() => 'LspCapabilityException($code): $method';
}

/// A dynamic registration operation was inconsistent.
final class LspRegistrationException extends ProtocolException {
  const LspRegistrationException(
    super.code,
    super.message, {
    required this.registrationId,
  });

  final String registrationId;

  @override
  String toString() => 'LspRegistrationException($code): $registrationId';
}

/// A reverse-request handler was missing or registered twice.
final class LspHandlerException extends ProtocolException {
  const LspHandlerException(
    super.code,
    super.message, {
    required this.method,
  });

  final String method;

  @override
  String toString() => 'LspHandlerException($code): $method';
}

/// LSP work-done or partial-result token state was inconsistent.
final class LspProgressException extends ProtocolException {
  const LspProgressException(super.code, super.message);

  @override
  String toString() => 'LspProgressException($code): $message';
}

/// LSP cancellation correlation or tombstone state was inconsistent.
final class LspCancellationException extends ProtocolException {
  const LspCancellationException(super.code, super.message);

  @override
  String toString() => 'LspCancellationException($code): $message';
}

/// Versioned LSP document state was stale or malformed.
final class LspDocumentException extends ProtocolException {
  const LspDocumentException(
    super.code,
    super.message, {
    this.uri,
  });

  final String? uri;

  @override
  String toString() => 'LspDocumentException($code): $message';
}

/// A privileged reverse request failed its typed proposal boundary.
final class LspProposalException extends ProtocolException {
  const LspProposalException(
    super.code,
    super.message, {
    required this.method,
    super.cause,
  });

  final String method;

  @override
  String toString() => 'LspProposalException($code): $method';
}
