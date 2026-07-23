import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Adapts an already-running, caller-owned process to protocol bytes.
///
/// The adapter never spawns, kills, restarts, or waits on behalf of ownership
/// policy. Closing it closes stdin and its stream subscriptions only.
final class McpProcessAdapter implements ProtocolByteTransport {
  McpProcessAdapter({
    required this.process,
    this.maxStderrBytes = 64 * 1024,
  }) {
    if (maxStderrBytes <= 0 ||
        maxStderrBytes > ProtocolLimits.hardMaxMessageBytes) {
      throw ArgumentError.value(
        maxStderrBytes,
        'maxStderrBytes',
        'Must be between 1 and '
            '${ProtocolLimits.hardMaxMessageBytes} bytes.',
      );
    }
    _stdoutSubscription = process.stdout.listen(
      _incoming.add,
      onError: _handleStdoutError,
      onDone: _handleStdoutDone,
    );
    _stderrSubscription = process.stderr.listen(
      _captureStderr,
      onError: (_) {
        // Stderr is diagnostic-only and cannot change protocol state.
      },
    );
  }

  final Process process;
  final int maxStderrBytes;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>(sync: true);
  final List<int> _stderr = <int>[];
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  var _stderrDroppedBytes = 0;
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  Future<int> get exitCode => process.exitCode;

  List<int> get stderrBytes => List<int>.unmodifiable(_stderr);

  String get stderrText => utf8.decode(_stderr, allowMalformed: true);

  int get stderrDroppedBytes => _stderrDroppedBytes;

  bool get isClosed => _closed;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (_closed) {
      throw const ProtocolTransportException(
        'mcp_process_stdin_closed',
        'MCP process adapter stdin is closed.',
      );
    }
    try {
      process.stdin.add(bytes);
      await process.stdin.flush();
    } on Object catch (error) {
      throw ProtocolTransportException(
        'mcp_process_stdin_failed',
        'Failed to write MCP bytes to caller-owned process stdin.',
        cause: error,
      );
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    // dart:io process sink closure and stream cancellation may not complete
    // until the process itself exits. Process lifetime remains caller-owned,
    // so request closure/cancellation without awaiting those futures.
    unawaited(process.stdin.close().catchError((_) {}));
    unawaited(_stdoutSubscription.cancel());
    unawaited(_stderrSubscription.cancel());
    if (!_incoming.isClosed) {
      // A single-subscription controller's close future also waits for a
      // listener that may never attach. Closing the adapter must not depend on
      // downstream subscription state.
      unawaited(_incoming.close());
    }
  }

  void _captureStderr(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    if (bytes.length >= maxStderrBytes) {
      _stderrDroppedBytes += _stderr.length + bytes.length - maxStderrBytes;
      _stderr
        ..clear()
        ..addAll(bytes.sublist(bytes.length - maxStderrBytes));
      return;
    }
    final overflow = _stderr.length + bytes.length - maxStderrBytes;
    if (overflow > 0) {
      _stderr.removeRange(0, overflow);
      _stderrDroppedBytes += overflow;
    }
    _stderr.addAll(bytes);
  }

  void _handleStdoutError(Object error, StackTrace stackTrace) {
    if (_closed || _incoming.isClosed) {
      return;
    }
    _incoming.addError(
      ProtocolTransportException(
        'mcp_process_stdout_failed',
        'Failed to read MCP bytes from caller-owned process stdout.',
        cause: error,
      ),
      stackTrace,
    );
  }

  Future<void> _handleStdoutDone() async {
    if (_closed || _incoming.isClosed) {
      return;
    }
    final code = await process.exitCode;
    if (_closed || _incoming.isClosed) {
      return;
    }
    if (code != 0) {
      _incoming.addError(
        ProtocolTransportException(
          'mcp_process_exited',
          'Caller-owned MCP process exited before transport close.',
          cause: code,
        ),
      );
    }
    await _incoming.close();
  }
}
