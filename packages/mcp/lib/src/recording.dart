import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'codec.dart';
import 'models.dart';

/// One validated, redacted, and reframed MCP message.
final class McpRecordedFrame {
  McpRecordedFrame({
    required this.sequence,
    required this.role,
    required this.responseMethod,
    required JsonObject envelope,
    required List<int> ndjsonBytes,
  })  : envelope = freezeJsonObject(envelope),
        ndjsonBytes = List<int>.unmodifiable(ndjsonBytes);

  final int sequence;
  final McpMessageRole role;
  final String? responseMethod;
  final JsonObject envelope;
  final List<int> ndjsonBytes;

  String get ndjsonLine => utf8.decode(ndjsonBytes);
}

typedef McpReplaySink = FutureOr<void> Function(McpRecordedFrame frame);

/// Bounded MCP recorder that never retains unvalidated or secret-bearing input.
///
/// Replay is deliberately observational: callers receive immutable recorded
/// frames, never live request dispatch.
final class McpRecorder {
  McpRecorder({
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
  final Queue<McpRecordedFrame> _frames = Queue<McpRecordedFrame>();
  var _nextSequence = 0;

  List<McpRecordedFrame> get frames =>
      List<McpRecordedFrame>.unmodifiable(_frames);

  McpRecordedFrame record({
    required McpMessageRole role,
    required String source,
    String? responseMethod,
  }) {
    final decoded = _decode(role, source, responseMethod: responseMethod);
    final redactedEnvelope = _redactObject(decoded.toJson());
    final reframed = _decode(
      role,
      jsonEncode(redactedEnvelope),
      responseMethod: responseMethod,
    );
    final canonical = McpCodec.instance.encode(reframed);
    final ndjsonBytes = utf8.encode('$canonical\n');
    if (ndjsonBytes.length > maxFrameBytes) {
      throw const FramingException(
        'mcp_recording_frame_too_large',
        'Redacted MCP recording exceeds the configured frame limit.',
      );
    }
    final frame = McpRecordedFrame(
      sequence: _nextSequence++,
      role: role,
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

  List<int> fixtureBytes() => List<int>.unmodifiable(<int>[
        for (final frame in _frames) ...frame.ndjsonBytes,
      ]);

  Future<void> replay(McpReplaySink sink) async {
    for (final frame in frames) {
      await Future<void>.sync(() => sink(frame));
    }
  }
}

McpDecodedMessage _decode(
  McpMessageRole role,
  String source, {
  String? responseMethod,
}) =>
    switch (role) {
      McpMessageRole.clientRequest =>
        McpCodec.instance.decodeClientRequest(source),
      McpMessageRole.serverRequest =>
        McpCodec.instance.decodeServerRequest(source),
      McpMessageRole.clientNotification =>
        McpCodec.instance.decodeClientNotification(source),
      McpMessageRole.serverNotification =>
        McpCodec.instance.decodeServerNotification(source),
      McpMessageRole.clientResult => McpCodec.instance.decodeClientResult(
          source,
          responseMethod: _requireResponseMethod(responseMethod),
        ),
      McpMessageRole.serverResult => McpCodec.instance.decodeServerResult(
          source,
          responseMethod: _requireResponseMethod(responseMethod),
        ),
    };

String _requireResponseMethod(String? value) {
  if (value == null || value.isEmpty) {
    throw ArgumentError.value(
      value,
      'responseMethod',
      'MCP result recording requires the correlated request method.',
    );
  }
  return value;
}

JsonObject _redactObject(JsonObject value) => <String, Object?>{
      for (final entry in value.entries)
        entry.key: _redactValue(entry.key, entry.value),
    };

JsonValue _redactValue(String key, Object? value) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (_credentialKeys.any(normalized.contains)) {
    return _replacement(value, '[REDACTED]');
  }
  if (_isPathKey(normalized)) {
    return _replacement(value, '/redacted');
  }
  if (normalized == 'headers' || normalized == 'env') {
    return _redactNameValueCollection(value);
  }
  return _redactNested(value);
}

JsonValue _redactNameValueCollection(Object? value) => switch (value) {
      final Map<String, Object?> object => <String, Object?>{
          for (final entry in object.entries) entry.key: '[REDACTED]',
        },
      final List<Object?> list => <Object?>[
          for (final item in list)
            if (item is Map<String, Object?>)
              <String, Object?>{
                for (final entry in item.entries)
                  entry.key: entry.key.toLowerCase() == 'value'
                      ? '[REDACTED]'
                      : _redactNested(entry.value),
              }
            else
              _redactNested(item),
        ],
      _ => _redactNested(value),
    };

JsonValue _redactNested(Object? value) => switch (value) {
      final Map<String, Object?> object => _redactObject(object),
      final List<Object?> list => <Object?>[
          for (final item in list) _redactNested(item),
        ],
      _ => value,
    };

JsonValue _replacement(Object? value, String replacement) => switch (value) {
      final List<Object?> list => <Object?>[for (final _ in list) replacement],
      final Map<String, Object?> _ => <String, Object?>{},
      null => null,
      _ => replacement,
    };

bool _isPathKey(String normalized) =>
    normalized == 'cwd' ||
    normalized == 'path' ||
    normalized.endsWith('path') ||
    normalized == 'additionaldirectories';

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
