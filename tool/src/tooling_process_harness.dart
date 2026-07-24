import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class ToolingProcessCommand {
  const ToolingProcessCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    this.environment = const <String, String>{},
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
}

/// Bounded Content-Length process harness with explicit deadlines and cleanup.
final class ToolingProcessHarness {
  ToolingProcessHarness._(
    this.process,
    this._messages,
    this._stderrDone,
    this._stderr,
  );

  static Future<ToolingProcessHarness> start(
    ToolingProcessCommand command,
  ) async {
    final process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: <String, String>{
        ..._sanitizedEnvironment(),
        ...command.environment,
      },
      includeParentEnvironment: false,
    );
    final stderr = StringBuffer();
    final stderrDone = Completer<void>();
    process.stderr.transform(utf8.decoder).listen(
      (chunk) {
        if (stderr.length < 64 * 1024) {
          final remaining = 64 * 1024 - stderr.length;
          stderr.write(
            chunk.length <= remaining ? chunk : chunk.substring(0, remaining),
          );
        }
      },
      onDone: stderrDone.complete,
      onError: stderrDone.completeError,
      cancelOnError: true,
    );
    final messages = StreamIterator<JsonObject>(
      process.stdout.transform(_ContentLengthJsonDecoder()),
    );
    return ToolingProcessHarness._(
      process,
      messages,
      stderrDone.future,
      stderr,
    );
  }

  final Process process;
  final StreamIterator<JsonObject> _messages;
  final Future<void> _stderrDone;
  final StringBuffer _stderr;
  bool _stdinClosed = false;

  String get boundedStderr => _stderr.toString();

  Future<void> send(JsonObject envelope) async {
    if (_stdinClosed) {
      throw StateError('Tooling process stdin is closed.');
    }
    final body = utf8.encode(jsonEncode(envelope));
    process.stdin.add(<int>[
      ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ]);
    await process.stdin.flush();
  }

  Future<JsonObject> next(Duration deadline) async {
    final available = await _messages.moveNext().timeout(deadline);
    if (!available) {
      throw StateError(
        'Tooling process closed before the expected message: $boundedStderr',
      );
    }
    return _messages.current;
  }

  Future<int> close(Duration deadline) async {
    if (!_stdinClosed) {
      _stdinClosed = true;
      await process.stdin.close();
    }
    final code = await process.exitCode.timeout(deadline);
    await _stderrDone.timeout(deadline);
    await _messages.cancel();
    return code;
  }

  Future<void> terminate(Duration deadline) async {
    if (!_stdinClosed) {
      _stdinClosed = true;
      await process.stdin.close();
    }
    if (await isRunning) {
      process.kill();
      await process.exitCode.timeout(deadline);
    }
    await _messages.cancel();
  }

  Future<bool> get isRunning async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }
}

Map<String, String> _sanitizedEnvironment() => <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };

final class _ContentLengthJsonDecoder
    extends StreamTransformerBase<List<int>, JsonObject> {
  @override
  Stream<JsonObject> bind(Stream<List<int>> stream) async* {
    final framer = ContentLengthFramer();
    await for (final chunk in stream) {
      for (final frame in framer.add(chunk)) {
        final value = jsonDecode(utf8.decode(frame));
        if (value is! JsonObject) {
          throw const FormatException(
            'Tooling peer frame must contain a JSON object.',
          );
        }
        yield value;
      }
    }
    framer.close();
  }
}
