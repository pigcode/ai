import 'dart:io';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../transport/stdio.dart';
import 'process_adapter.dart';

/// A stdio channel over one caller-owned, already-running process.
final class McpProcessStdioChannel {
  McpProcessStdioChannel({
    required Process process,
    ProtocolLimits? limits,
    int maxStderrBytes = 64 * 1024,
  }) : adapter = McpProcessAdapter(
          process: process,
          maxStderrBytes: maxStderrBytes,
        ) {
    transport = createMcpStdioTransport(
      byteTransport: adapter,
      limits: limits,
    );
  }

  final McpProcessAdapter adapter;
  late final ProtocolMessageTransport<JsonRpcMessage> transport;
}
