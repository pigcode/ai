import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'codec.dart';
import 'models.dart';

/// One validated, redacted, and reframed ACP message.
final class AcpRecordedFrame {
  AcpRecordedFrame({
    required this.sequence,
    required this.root,
    required this.responseMethod,
    required JsonObject envelope,
    required List<int> ndjsonBytes,
  })  : envelope = freezeJsonObject(envelope),
        ndjsonBytes = List<int>.unmodifiable(ndjsonBytes);

  final int sequence;
  final AcpMessageRoot root;
  final String? responseMethod;
  final JsonObject envelope;
  final List<int> ndjsonBytes;

  String get ndjsonLine => utf8.decode(ndjsonBytes);
}

typedef AcpReplaySink = FutureOr<void> Function(AcpRecordedFrame frame);

/// Bounded ACP recorder that never persists unvalidated or secret-bearing input.
final class AcpRecorder {
  AcpRecorder({
    this.maxEntries = 512,
    this.maxFrameBytes = 16 * 1024 * 1024,
  }) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
    if (maxFrameBytes <= 0) {
      throw ArgumentError.value(
        maxFrameBytes,
        'maxFrameBytes',
        'Must be positive.',
      );
    }
  }

  final int maxEntries;
  final int maxFrameBytes;
  final Queue<AcpRecordedFrame> _frames = Queue<AcpRecordedFrame>();
  var _nextSequence = 0;

  List<AcpRecordedFrame> get frames =>
      List<AcpRecordedFrame>.unmodifiable(_frames);

  AcpRecordedFrame record({
    required AcpMessageRoot root,
    required String source,
    String? responseMethod,
  }) {
    final decoded = _decode(
      root,
      source,
      responseMethod: responseMethod,
    );
    final redactedEnvelope = _redactObject(decoded.toJson(), parentKey: null);
    final redactedSource = jsonEncode(redactedEnvelope);
    final reframed = _decode(
      root,
      redactedSource,
      responseMethod: responseMethod,
    );
    final canonical = AcpCodec.instance.encode(reframed);
    final ndjsonBytes = utf8.encode('$canonical\n');
    if (ndjsonBytes.length > maxFrameBytes) {
      throw const FramingException(
        'acp_recording_frame_too_large',
        'Redacted ACP recording exceeds the configured frame limit.',
      );
    }
    final frame = AcpRecordedFrame(
      sequence: _nextSequence++,
      root: root,
      responseMethod: responseMethod,
      envelope: reframed.toJson(),
      ndjsonBytes: ndjsonBytes,
    );
    if (_frames.length == maxEntries) {
      _frames.removeFirst();
    }
    _frames.addLast(frame);
    return frame;
  }

  List<int> fixtureBytes() => List<int>.unmodifiable(
        <int>[
          for (final frame in _frames) ...frame.ndjsonBytes,
        ],
      );

  Future<void> replay(AcpReplaySink sink) async {
    for (final frame in frames) {
      await Future<void>.sync(() => sink(frame));
    }
  }
}

AcpDecodedMessage _decode(
  AcpMessageRoot root,
  String source, {
  String? responseMethod,
}) =>
    switch (root) {
      AcpMessageRoot.agent => AcpCodec.instance.decodeAgentMessage(
          source,
          responseMethod: responseMethod,
        ),
      AcpMessageRoot.client => AcpCodec.instance.decodeClientMessage(
          source,
          responseMethod: responseMethod,
        ),
      AcpMessageRoot.protocolLevel =>
        AcpCodec.instance.decodeProtocolMessage(source),
    };

JsonObject _redactObject(JsonObject value, {required String? parentKey}) =>
    <String, Object?>{
      for (final entry in value.entries)
        entry.key: _redactValue(entry.key, entry.value),
    };

JsonValue _redactValue(String key, Object? value) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (_credentialKeys.any(normalized.contains)) {
    return _replacement(value, '[REDACTED]');
  }
  if (_pathKeys.contains(normalized)) {
    return _replacement(value, '/redacted');
  }
  if ((normalized == 'headers' || normalized == 'env') && value is List) {
    return <Object?>[
      for (final item in value)
        if (item is Map<String, Object?>)
          <String, Object?>{
            for (final entry in item.entries)
              entry.key: entry.key.toLowerCase() == 'value'
                  ? '[REDACTED]'
                  : _redactNested(entry.value),
          }
        else
          _redactNested(item),
    ];
  }
  return _redactNested(value);
}

JsonValue _redactNested(Object? value) => switch (value) {
      final Map<String, Object?> object =>
        _redactObject(object, parentKey: null),
      final List<Object?> list => <Object?>[
          for (final item in list) _redactNested(item)
        ],
      _ => value,
    };

JsonValue _replacement(Object? value, String replacement) => switch (value) {
      final List<Object?> list => <Object?>[for (final _ in list) replacement],
      final Map<String, Object?> _ => <String, Object?>{},
      null => null,
      _ => replacement,
    };

const _credentialKeys = <String>{
  'apikey',
  'authorization',
  'cookie',
  'credential',
  'password',
  'privatekey',
  'secret',
  'token',
};

const _pathKeys = <String>{
  'additionaldirectories',
  'cwd',
  'path',
};
