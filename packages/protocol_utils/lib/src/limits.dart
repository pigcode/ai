/// Immutable memory limits shared by protocol framers.
final class ProtocolLimits {
  ProtocolLimits({
    this.maxMessageBytes = 16 * 1024 * 1024,
    this.maxHeaderBytes = 64 * 1024,
    this.maxLineBytes = 1024 * 1024,
    this.maxSseEventBytes = 4 * 1024 * 1024,
    this.maxSseRetryMilliseconds = 24 * 60 * 60 * 1000,
    this.maxPendingRequests = 256,
    this.maxOutboundMessages = 256,
    this.maxInboundRequests = 128,
    this.maxTombstones = 512,
    this.maxDiagnostics = 256,
  }) {
    _validate(
      maxMessageBytes,
      'maxMessageBytes',
      hardMaxMessageBytes,
    );
    _validate(maxHeaderBytes, 'maxHeaderBytes', hardMaxHeaderBytes);
    _validate(maxLineBytes, 'maxLineBytes', hardMaxLineBytes);
    _validate(
      maxSseEventBytes,
      'maxSseEventBytes',
      hardMaxSseEventBytes,
    );
    _validateDuration(
      maxSseRetryMilliseconds,
      'maxSseRetryMilliseconds',
      hardMaxSseRetryMilliseconds,
    );
    _validateCount(
      maxPendingRequests,
      'maxPendingRequests',
      hardMaxPendingRequests,
    );
    _validateCount(
      maxOutboundMessages,
      'maxOutboundMessages',
      hardMaxOutboundMessages,
    );
    _validateCount(
      maxInboundRequests,
      'maxInboundRequests',
      hardMaxInboundRequests,
    );
    _validateCount(maxTombstones, 'maxTombstones', hardMaxTombstones);
    _validateCount(maxDiagnostics, 'maxDiagnostics', hardMaxDiagnostics);
  }

  /// Absolute ceiling for a framed protocol message.
  static const hardMaxMessageBytes = 64 * 1024 * 1024;

  /// Absolute ceiling for a Content-Length header block.
  static const hardMaxHeaderBytes = 256 * 1024;

  /// Absolute ceiling for one NDJSON or SSE line.
  static const hardMaxLineBytes = 4 * 1024 * 1024;

  /// Absolute ceiling for one accumulated SSE event.
  static const hardMaxSseEventBytes = 16 * 1024 * 1024;

  /// Absolute ceiling for a server-provided SSE retry delay.
  static const hardMaxSseRetryMilliseconds = 7 * 24 * 60 * 60 * 1000;

  /// Absolute ceiling for simultaneously pending outbound requests.
  static const hardMaxPendingRequests = 4096;

  /// Absolute ceiling for queued or active outbound messages.
  static const hardMaxOutboundMessages = 4096;

  /// Absolute ceiling for concurrently executing inbound requests.
  static const hardMaxInboundRequests = 2048;

  /// Absolute ceiling for retained completed-request tombstones.
  static const hardMaxTombstones = 8192;

  /// Absolute ceiling for retained protocol diagnostics.
  static const hardMaxDiagnostics = 4096;

  /// Default limits for callers that do not supply tighter values.
  static final defaults = ProtocolLimits();

  final int maxMessageBytes;
  final int maxHeaderBytes;
  final int maxLineBytes;
  final int maxSseEventBytes;
  final int maxSseRetryMilliseconds;
  final int maxPendingRequests;
  final int maxOutboundMessages;
  final int maxInboundRequests;
  final int maxTombstones;
  final int maxDiagnostics;

  static void _validate(int value, String name, int ceiling) {
    if (value <= 0 || value > ceiling) {
      throw ArgumentError.value(
        value,
        name,
        'Must be between 1 and $ceiling bytes.',
      );
    }
  }

  static void _validateCount(int value, String name, int ceiling) {
    if (value <= 0 || value > ceiling) {
      throw ArgumentError.value(
        value,
        name,
        'Must be between 1 and $ceiling entries.',
      );
    }
  }

  static void _validateDuration(int value, String name, int ceiling) {
    if (value < 0 || value > ceiling) {
      throw ArgumentError.value(
        value,
        name,
        'Must be between 0 and $ceiling milliseconds.',
      );
    }
  }
}
