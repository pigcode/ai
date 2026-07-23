import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../errors.dart';
import '../limits.dart';
import 'framer.dart';

/// One decoded Server-Sent Event.
final class SseEvent extends Equatable {
  const SseEvent({
    required this.data,
    this.event,
    this.id,
    this.retry,
  });

  final String data;
  final String? event;
  final String? id;
  final Duration? retry;

  @override
  List<Object?> get props => <Object?>[data, event, id, retry];
}

/// Bounded UTF-8 Server-Sent Events decoder.
final class SseDecoder implements ProtocolFramer<SseEvent> {
  SseDecoder({ProtocolLimits? limits})
      : limits = limits ?? ProtocolLimits.defaults;

  final ProtocolLimits limits;
  final List<int> _line = <int>[];
  final List<String> _dataLines = <String>[];
  int _eventByteCount = 0;
  String? _eventType;
  String? _lastEventId;
  Duration? _eventRetry;
  Duration? _reconnectionDelay;
  bool _pendingCarriageReturn = false;
  bool _closed = false;
  bool _failed = false;

  /// Last valid event ID observed in the stream.
  String? get lastEventId => _lastEventId;

  /// Last valid retry delay observed in the stream.
  Duration? get reconnectionDelay => _reconnectionDelay;

  @override
  int get bufferedByteCount => _line.length + _eventByteCount;

  @override
  bool get isClosed => _closed;

  @override
  List<SseEvent> add(List<int> bytes) {
    _ensureActive();
    final events = <SseEvent>[];
    for (final byte in bytes) {
      _validateByte(byte);
      if (_pendingCarriageReturn) {
        _pendingCarriageReturn = false;
        if (byte == 0x0a) {
          continue;
        }
      }
      if (byte == 0x0d || byte == 0x0a) {
        _finishLine(events);
        _pendingCarriageReturn = byte == 0x0d;
        continue;
      }
      _line.add(byte);
      if (_line.length > limits.maxLineBytes) {
        _fail(
          'sse_line_too_large',
          'SSE line exceeds the configured byte limit.',
        );
      }
    }
    return List<SseEvent>.unmodifiable(events);
  }

  @override
  List<SseEvent> close() {
    _ensureActive();
    _closed = true;
    _pendingCarriageReturn = false;
    if (_line.isNotEmpty ||
        _dataLines.isNotEmpty ||
        _eventByteCount > 0 ||
        _eventType != null ||
        _eventRetry != null) {
      _fail(
        'sse_truncated_event',
        'SSE stream ended before the terminating blank line.',
      );
    }
    return const <SseEvent>[];
  }

  void _finishLine(List<SseEvent> events) {
    if (_line.isEmpty) {
      if (_dataLines.isNotEmpty) {
        events.add(
          SseEvent(
            data: _dataLines.join('\n'),
            event:
                _eventType == null || _eventType!.isEmpty ? null : _eventType,
            id: _lastEventId,
            retry: _eventRetry,
          ),
        );
      }
      _resetEvent();
      return;
    }

    late final String line;
    final lineByteCount = _line.length;
    try {
      line = utf8.decode(_line, allowMalformed: false);
    } on FormatException catch (error) {
      _fail(
        'sse_invalid_utf8',
        'SSE line is not valid UTF-8.',
        cause: error,
      );
    } finally {
      _line.clear();
    }
    if (line.startsWith(':')) {
      return;
    }

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field != 'data' &&
        field != 'event' &&
        field != 'id' &&
        field != 'retry') {
      return;
    }

    _eventByteCount += lineByteCount;
    if (_eventByteCount > limits.maxSseEventBytes) {
      _fail(
        'sse_event_too_large',
        'SSE event exceeds the configured byte limit.',
      );
    }
    switch (field) {
      case 'data':
        _dataLines.add(value);
      case 'event':
        _eventType = value;
      case 'id':
        if (!value.contains('\u0000')) {
          _lastEventId = value;
        }
      case 'retry':
        if (RegExp(r'^[0-9]+$').hasMatch(value)) {
          final milliseconds = int.tryParse(value);
          if (milliseconds != null &&
              milliseconds <= limits.maxSseRetryMilliseconds) {
            final duration = Duration(milliseconds: milliseconds);
            _eventRetry = duration;
            _reconnectionDelay = duration;
          }
        }
    }
  }

  void _resetEvent() {
    _dataLines.clear();
    _eventByteCount = 0;
    _eventType = null;
    _eventRetry = null;
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
    _resetEvent();
    _lastEventId = null;
    _reconnectionDelay = null;
    throw FramingException(code, message, cause: cause);
  }
}
