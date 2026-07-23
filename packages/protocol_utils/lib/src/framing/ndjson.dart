import 'dart:convert';

import '../errors.dart';
import '../limits.dart';
import 'framer.dart';

/// Policy for empty NDJSON records.
enum NdjsonEmptyLinePolicy {
  /// Ignore empty records between delimited JSON values.
  ignore,

  /// Reject an empty record as an invalid frame.
  reject,
}

/// Bounded newline-delimited UTF-8 text framing.
final class NdjsonFramer implements ProtocolFramer<String> {
  NdjsonFramer({
    ProtocolLimits? limits,
    this.emptyLinePolicy = NdjsonEmptyLinePolicy.ignore,
  }) : limits = limits ?? ProtocolLimits.defaults;

  final ProtocolLimits limits;
  final NdjsonEmptyLinePolicy emptyLinePolicy;
  final List<int> _line = <int>[];
  bool _pendingCarriageReturn = false;
  bool _closed = false;
  bool _failed = false;

  @override
  int get bufferedByteCount => _line.length;

  @override
  bool get isClosed => _closed;

  @override
  List<String> add(List<int> bytes) {
    _ensureActive();
    final frames = <String>[];
    for (final byte in bytes) {
      _validateByte(byte);
      if (_pendingCarriageReturn) {
        _pendingCarriageReturn = false;
        if (byte == 0x0a) {
          continue;
        }
      }
      if (byte == 0x0d || byte == 0x0a) {
        final frame = _finishLine();
        if (frame != null) {
          frames.add(frame);
        }
        _pendingCarriageReturn = byte == 0x0d;
        continue;
      }
      _line.add(byte);
      if (_line.length > limits.maxMessageBytes ||
          _line.length > limits.maxLineBytes) {
        _fail(
          'ndjson_frame_too_large',
          'NDJSON frame exceeds the configured byte limit.',
        );
      }
    }
    return List<String>.unmodifiable(frames);
  }

  @override
  List<String> close() {
    _ensureActive();
    _closed = true;
    _pendingCarriageReturn = false;
    if (_line.isNotEmpty) {
      _fail(
        'ndjson_truncated_frame',
        'NDJSON stream ended before a line delimiter.',
      );
    }
    return const <String>[];
  }

  String? _finishLine() {
    if (_line.isEmpty) {
      return switch (emptyLinePolicy) {
        NdjsonEmptyLinePolicy.ignore => null,
        NdjsonEmptyLinePolicy.reject => _fail(
            'ndjson_empty_frame',
            'NDJSON stream contains an empty frame.',
          ),
      };
    }
    try {
      return utf8.decode(_line, allowMalformed: false);
    } on FormatException catch (error) {
      _fail(
        'ndjson_invalid_utf8',
        'NDJSON frame is not valid UTF-8.',
        cause: error,
      );
    } finally {
      _line.clear();
    }
  }

  void _validateByte(int byte) {
    if (byte < 0 || byte > 0xff) {
      _fail(
        'framing_invalid_byte',
        'Framing input contains a value outside the byte range.',
      );
    }
  }

  void _ensureActive() {
    if (_failed) {
      throw const FramingException(
        'framer_unusable',
        'Framer is unusable after a previous failure.',
      );
    }
    if (_closed) {
      throw const FramingException(
        'framer_closed',
        'Framer is already closed.',
      );
    }
  }

  Never _fail(String code, String message, {Object? cause}) {
    _failed = true;
    _closed = false;
    _pendingCarriageReturn = false;
    _line.clear();
    throw FramingException(code, message, cause: cause);
  }
}
