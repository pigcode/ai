import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'codec.dart';

final class DapRecordedFrame {
  DapRecordedFrame({
    required this.sequence,
    required this.requestCommand,
    required JsonObject envelope,
    required List<int> contentLengthBytes,
  })  : envelope = freezeJsonObject(envelope),
        contentLengthBytes = List<int>.unmodifiable(contentLengthBytes);

  final int sequence;
  final String? requestCommand;
  final JsonObject envelope;
  final List<int> contentLengthBytes;
}

typedef DapReplaySink = FutureOr<void> Function(DapRecordedFrame frame);

final class DapRecorder {
  DapRecorder({
    this.maxEntries = 512,
    this.maxFrameBytes = 16 * 1024 * 1024,
  }) {
    if (maxEntries <= 0 || maxFrameBytes <= 0) {
      throw ArgumentError('DAP recording limits must be positive.');
    }
  }

  final int maxEntries;
  final int maxFrameBytes;
  final Queue<DapRecordedFrame> _frames = Queue<DapRecordedFrame>();
  var _nextSequence = 0;

  List<DapRecordedFrame> get frames =>
      List<DapRecordedFrame>.unmodifiable(_frames);

  DapRecordedFrame record({
    required String source,
    String? requestCommand,
  }) {
    final decoded = DapCodec.instance.decode(
      source,
      requestCommand: requestCommand,
    );
    final redacted = _redactObject(decoded.toJson());
    final validated = DapCodec.instance.decode(
      jsonEncode(redacted),
      requestCommand: requestCommand,
    );
    final body = utf8.encode(DapCodec.instance.encode(validated));
    final framed = <int>[
      ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ];
    if (framed.length > maxFrameBytes) {
      throw const FramingException(
        'dap_recording_frame_too_large',
        'Redacted DAP recording exceeds the configured frame limit.',
      );
    }
    final frame = DapRecordedFrame(
      sequence: _nextSequence++,
      requestCommand: requestCommand,
      envelope: validated.toJson(),
      contentLengthBytes: framed,
    );
    if (_frames.length == maxEntries) {
      _frames.removeFirst();
    }
    _frames.addLast(frame);
    return frame;
  }

  Future<void> replay(DapReplaySink sink) async {
    for (final frame in frames) {
      await Future<void>.sync(() => sink(frame));
    }
  }
}

JsonObject _redactObject(JsonObject value) => freezeJsonObject(
      <String, Object?>{
        for (final entry in value.entries)
          entry.key: _redactValue(entry.key, entry.value),
      },
    );

JsonValue _redactValue(String key, Object? value) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (_sensitiveKeys.contains(normalized)) {
    return value is Map
        ? const <String, Object?>{}
        : value is List
            ? const <Object?>[]
            : value == null
                ? null
                : '[REDACTED]';
  }
  return switch (value) {
    final Map<String, Object?> object => _redactObject(object),
    final List<Object?> list => <Object?>[
        for (final item in list) _redactValue('', item),
      ],
    _ => value,
  };
}

const _sensitiveKeys = <String>{
  'env',
  'environment',
  'password',
  'secret',
  'token',
};
