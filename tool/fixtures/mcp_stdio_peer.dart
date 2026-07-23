import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments.isEmpty ? 'normal' : arguments.single;
  if (!_modes.contains(mode)) {
    stderr.writeln('Unknown MCP stdio fixture mode: $mode');
    exitCode = 64;
    return;
  }
  if (mode == '--exit-before-handshake') {
    stderr.writeln('intentional pre-handshake exit');
    exit(23);
  }
  if (mode == '--linger-after-eof') {
    await stdin.drain<void>();
    await Future<void>.delayed(const Duration(seconds: 30));
    return;
  }
  if (mode == '--stderr-flood') {
    for (var index = 0; index < 256; index++) {
      stderr.add(List<int>.filled(1024, 0x78));
    }
    stderr.writeln('\nstderr flood complete');
    await stderr.flush();
  }

  late McpServer server;
  server = McpServer(
    transport: createMcpStdioTransport(
      byteTransport: _StdioByteTransport(),
    ),
    capabilities: McpServerCapabilities(tools: true),
    handlers: McpHandlerSet(
      requests: <String, McpRequestHandler>{
        'tools/list': (_) => const <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'echo',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
        'tools/call': (invocation) {
          if (mode == '--exit-on-tools-call') {
            stderr.writeln('intentional exit during tools/call');
            exit(17);
          }
          final params = invocation.params! as Map<String, Object?>;
          final arguments = params['arguments'];
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': arguments is Map<String, Object?>
                    ? arguments['text'] ?? ''
                    : '',
              },
            ],
          };
        },
      },
    ),
    serverInfo: const <String, Object?>{
      'name': 'pigcode-fixed-mcp-stdio-peer',
      'version': '1.0.0',
    },
  );
  await server.connection.peer.done;
}

const _modes = <String>{
  'normal',
  '--stderr-flood',
  '--exit-before-handshake',
  '--exit-on-tools-call',
  '--linger-after-eof',
};

final class _StdioByteTransport implements ProtocolByteTransport {
  var _closed = false;

  @override
  Stream<List<int>> get incomingBytes => stdin;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (_closed) {
      throw StateError('MCP fixture stdout is closed.');
    }
    stdout.add(bytes);
    await stdout.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await stdout.close();
  }
}
