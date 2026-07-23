import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

const _fixture = '../../tool/fixtures/mcp_stdio_peer.dart';

void main() {
  test('drains bounded stderr and completes a normal caller-owned process',
      () async {
    final process = await _start('--stderr-flood');
    final channel = McpProcessStdioChannel(
      process: process,
      maxStderrBytes: 1024,
    );
    final client = _client(channel);

    await client.initialize();
    final result = await client.callTool(
      McpCallToolRequestParams.fromJson(
        const <String, Object?>{
          'name': 'echo',
          'arguments': <String, Object?>{'text': 'stdio'},
        },
      ),
    );
    expect(result.toJson(), containsPair('content', isNotEmpty));
    expect(channel.adapter.stderrBytes.length, lessThanOrEqualTo(1024));
    expect(channel.adapter.stderrDroppedBytes, greaterThan(0));
    await client.close();
    expect(await process.exitCode, 0);
  });

  test('pre-handshake exit fails initialize and retains bounded diagnostics',
      () async {
    final process = await _start('--exit-before-handshake');
    final channel = McpProcessStdioChannel(
      process: process,
      maxStderrBytes: 256,
    );
    final client = _client(channel);

    await expectLater(
      client.initialize(),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_process_exited',
        ),
      ),
    );
    expect(await process.exitCode, 23);
    expect(channel.adapter.stderrText, contains('pre-handshake'));
  });

  test('process exit fails a pending request', () async {
    final process = await _start('--exit-on-tools-call');
    final channel = McpProcessStdioChannel(process: process);
    final client = _client(channel);
    await client.initialize();

    await expectLater(
      client.callTool(
        McpCallToolRequestParams.fromJson(
          const <String, Object?>{'name': 'echo'},
        ),
      ),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_process_exited',
        ),
      ),
    );
    expect(await process.exitCode, 17);
  });

  test('close closes stdin but never kills the caller-owned process', () async {
    final process = await _start('--linger-after-eof');
    final adapter = McpProcessAdapter(process: process);
    await adapter.close();
    await expectLater(
      adapter.sendBytes(const <int>[0x0a]),
      throwsA(
        isA<ProtocolTransportException>().having(
          (error) => error.code,
          'code',
          'mcp_process_stdin_closed',
        ),
      ),
    );

    var exited = false;
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 100));
      exited = true;
    } on TimeoutException {
      // Expected: process lifetime remains caller-owned.
    }
    expect(exited, isFalse);
    expect(process.kill(), isTrue);
    await process.exitCode;
  });
}

Future<Process> _start(String mode) => Process.start(
      Platform.resolvedExecutable,
      <String>['run', _fixture, mode],
      workingDirectory: Directory.current.absolute.path,
    );

McpClient _client(McpProcessStdioChannel channel) => McpClient(
      transport: channel.transport,
      capabilities: McpClientCapabilities(),
      handlers: McpHandlerSet(),
      clientInfo: const <String, Object?>{
        'name': 'process-adapter-test',
        'version': '1.0.0',
      },
    );
