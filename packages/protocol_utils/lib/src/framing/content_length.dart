import 'dart:convert';

import '../errors.dart';
import '../limits.dart';
import 'framer.dart';

const _headerTerminator = <int>[0x0d, 0x0a, 0x0d, 0x0a];

/// Bounded ASCII-header/Content-Length byte framing.
final class ContentLengthFramer implements ProtocolFramer<List<int>> {
  ContentLengthFramer({ProtocolLimits? limits})
      : limits = limits ?? ProtocolLimits.defaults;

  final ProtocolLimits limits;
  final List<int> _header = <int>[];
  final List<int> _body = <int>[];
  int? _expectedBodyBytes;
  bool _closed = false;
  bool _failed = false;

  @override
  int get bufferedByteCount => _header.length + _body.length;

  @override
  bool get isClosed => _closed;

  @override
  List<List<int>> add(List<int> bytes) {
    _ensureActive();
    final frames = <List<int>>[];
    for (final byte in bytes) {
      _validateByte(byte);
      if (_expectedBodyBytes == null) {
        _addHeaderByte(byte, frames);
      } else {
        _body.add(byte);
        if (_body.length == _expectedBodyBytes) {
          frames.add(List<int>.unmodifiable(_body));
          _body.clear();
          _expectedBodyBytes = null;
        }
      }
    }
    return List<List<int>>.unmodifiable(frames);
  }

  @override
  List<List<int>> close() {
    _ensureActive();
    _closed = true;
    if (_expectedBodyBytes != null) {
      _fail(
        'content_length_truncated_body',
        'Content-Length stream ended before the declared body length.',
      );
    }
    if (_header.isNotEmpty) {
      _fail(
        'content_length_truncated_header',
        'Content-Length stream ended before the header terminator.',
      );
    }
    return const <List<int>>[];
  }

  void _addHeaderByte(int byte, List<List<int>> frames) {
    if (byte != 0x0d && byte != 0x0a && (byte < 0x20 || byte > 0x7e)) {
      _fail(
        'content_length_invalid_header',
        'Content-Length headers must contain ASCII text.',
      );
    }
    _header.add(byte);
    if (_header.length > limits.maxHeaderBytes) {
      _fail(
        'content_length_header_too_large',
        'Content-Length header exceeds the configured byte limit.',
      );
    }
    if (!_endsWithHeaderTerminator()) {
      return;
    }

    final expected = _parseHeader();
    _header.clear();
    if (expected > limits.maxMessageBytes) {
      _fail(
        'content_length_body_too_large',
        'Declared Content-Length exceeds the configured message limit.',
      );
    }
    if (expected == 0) {
      frames.add(const <int>[]);
      return;
    }
    _expectedBodyBytes = expected;
  }

  int _parseHeader() {
    final text = ascii.decode(
      _header.sublist(0, _header.length - _headerTerminator.length),
      allowInvalid: false,
    );
    int? contentLength;
    for (final line in text.split('\r\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        _fail(
          'content_length_invalid_header',
          'Content-Length header line is malformed.',
        );
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (name != 'content-length') {
        continue;
      }
      if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
        _fail(
          'content_length_invalid',
          'Content-Length must be a non-negative decimal integer.',
        );
      }
      final parsed = int.tryParse(value);
      if (parsed == null) {
        _fail(
          'content_length_invalid',
          'Content-Length is outside the supported integer range.',
        );
      }
      if (contentLength != null) {
        _fail(
          contentLength == parsed
              ? 'content_length_duplicate'
              : 'content_length_conflict',
          contentLength == parsed
              ? 'Content-Length header must occur exactly once.'
              : 'Content-Length headers declare conflicting values.',
        );
      }
      contentLength = parsed;
    }
    if (contentLength == null) {
      _fail(
        'content_length_missing',
        'Content-Length header is required.',
      );
    }
    return contentLength;
  }

  bool _endsWithHeaderTerminator() {
    if (_header.length < _headerTerminator.length) {
      return false;
    }
    final offset = _header.length - _headerTerminator.length;
    for (var index = 0; index < _headerTerminator.length; index += 1) {
      if (_header[offset + index] != _headerTerminator[index]) {
        return false;
      }
    }
    return true;
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
    _header.clear();
    _body.clear();
    _expectedBodyBytes = null;
    throw FramingException(code, message, cause: cause);
  }
}
