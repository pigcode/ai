import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';

const _fixture = 'tool/fixtures/mcp_stdio_peer.dart';

Future<void> main() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const <String>['run', _fixture],
    workingDirectory: Directory.current.absolute.path,
  );
  final channel = McpProcessStdioChannel(process: process);
  final client = McpClient(
    transport: channel.transport,
    capabilities: McpClientCapabilities(),
    handlers: McpHandlerSet(),
    clientInfo: const <String, Object?>{
      'name': 'pigcode-mcp-stdio-harness',
      'version': '1.0.0',
    },
  );
  try {
    final negotiated = await client.initialize();
    _expect(
      negotiated.protocolVersion == '2025-11-25',
      'MCP stdio peer negotiated the wrong protocol version.',
    );
    final result = await client.callTool(
      McpCallToolRequestParams.fromJson(
        const <String, Object?>{
          'name': 'echo',
          'arguments': <String, Object?>{'text': 'interop 🐷'},
        },
      ),
    );
    _expect(
      result.toJson().toString().contains('interop 🐷'),
      'MCP stdio peer returned the wrong tool result.',
    );
    await client.close();
    final code = await process.exitCode;
    _expect(code == 0, 'MCP stdio peer exited with $code.');
    _expect(
      channel.adapter.stderrText.isEmpty,
      'MCP stdio peer wrote unexpected stderr.',
    );
    stdout.writeln('PASS MCP Dart stdio real process');
  } finally {
    if (!channel.adapter.isClosed) {
      await channel.adapter.close();
    }
    if (await _isRunning(process)) {
      process.kill();
      await process.exitCode;
    }
  }
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
