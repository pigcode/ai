import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'codec.dart';
import 'method.dart';

/// One validated, redacted, and Content-Length reframed LSP message.
final class LspRecordedFrame {
  LspRecordedFrame({
    required this.sequence,
    required this.sender,
    required this.responseMethod,
    required JsonObject envelope,
    required List<int> contentLengthBytes,
  })  : envelope = freezeJsonObject(envelope),
        contentLengthBytes = List<int>.unmodifiable(contentLengthBytes);

  final int sequence;
  final LspMessageSender sender;
  final String? responseMethod;
  final JsonObject envelope;
  final List<int> contentLengthBytes;
}

typedef LspReplaySink = FutureOr<void> Function(LspRecordedFrame frame);

/// Bounded LSP recorder that stores only validated and redacted frames.
final class LspRecorder {
  LspRecorder({
    this.maxEntries = 512,
    this.maxFrameBytes = 16 * 1024 * 1024,
  }) {
    if (maxEntries <= 0 || maxFrameBytes <= 0) {
      throw ArgumentError('LSP recording limits must be positive.');
    }
  }

  final int maxEntries;
  final int maxFrameBytes;
  final Queue<LspRecordedFrame> _frames = Queue<LspRecordedFrame>();
  var _nextSequence = 0;

  List<LspRecordedFrame> get frames =>
      List<LspRecordedFrame>.unmodifiable(_frames);

  LspRecordedFrame record({
    required LspMessageSender sender,
    required String source,
    String? responseMethod,
  }) {
    final decoded = LspCodec.instance.decode(
      source,
      sender: sender,
      responseMethod: responseMethod,
    );
    final redacted = _redactObject(decoded.toJson());
    final validated = LspCodec.instance.decode(
      jsonEncode(redacted),
      sender: sender,
      responseMethod: responseMethod,
    );
    final body = utf8.encode(LspCodec.instance.encode(validated));
    final framed = <int>[
      ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ];
    if (framed.length > maxFrameBytes) {
      throw const FramingException(
        'lsp_recording_frame_too_large',
        'Redacted LSP recording exceeds the configured frame limit.',
      );
    }
    final frame = LspRecordedFrame(
      sequence: _nextSequence++,
      sender: sender,
      responseMethod: responseMethod,
      envelope: validated.toJson(),
      contentLengthBytes: framed,
    );
    if (_frames.length == maxEntries) {
      _frames.removeFirst();
    }
    _frames.addLast(frame);
    return frame;
  }

  Future<void> replay(LspReplaySink sink) async {
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
  if (_credentialKeys.any(normalized.contains)) {
    return _replacement(value);
  }
  if (value is Map<String, Object?>) {
    return _redactObject(value);
  }
  if (value is List<Object?>) {
    return <Object?>[
      for (final item in value) _redactValue('', item),
    ];
  }
  return value;
}

JsonValue _replacement(Object? value) => switch (value) {
      List<Object?>() => const <Object?>[],
      Map<Object?, Object?>() => const <String, Object?>{},
      null => null,
      _ => '[REDACTED]',
    };

const _credentialKeys = <String>{
  'apikey',
  'authorization',
  'cookie',
  'credential',
  'password',
  'privatekey',
  'secret',
};
