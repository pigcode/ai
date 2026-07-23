import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('round-trips client and server capability profiles', () {
    final client = McpClientCapabilities(
      roots: true,
      rootsListChanged: true,
      sampling: true,
      samplingContext: true,
      samplingTools: true,
      elicitationForm: true,
      elicitationUrl: true,
      taskCancel: true,
      taskList: true,
      taskSampling: true,
      taskElicitation: true,
    );
    final server = McpServerCapabilities(
      resources: true,
      resourceSubscribe: true,
      resourceListChanged: true,
      prompts: true,
      promptListChanged: true,
      tools: true,
      toolListChanged: true,
      completions: true,
      logging: true,
      taskCancel: true,
      taskList: true,
      taskToolCall: true,
    );

    expect(McpClientCapabilities.fromJson(client.toJson()), client);
    expect(McpServerCapabilities.fromJson(server.toJson()), server);
  });

  test('treats legacy empty elicitation capability as form support', () {
    final capabilities = McpClientCapabilities.fromJson(
      const <String, Object?>{'elicitation': <String, Object?>{}},
    );

    expect(capabilities.elicitationForm, isTrue);
    expect(capabilities.elicitationUrl, isFalse);
  });

  test('rejects advertised capabilities without matching handlers', () async {
    final pair = MemoryTransportPair.create();

    expect(
      () => McpServer(
        transport: pair.right,
        capabilities: McpServerCapabilities(tools: true),
        handlers: McpHandlerSet(),
        serverInfo: const <String, Object?>{
          'name': 'server',
          'version': '1.0.0',
        },
      ),
      throwsA(isA<McpHandlerException>()),
    );
    expect(
      () => McpClient(
        transport: pair.left,
        capabilities: McpClientCapabilities(roots: true),
        handlers: McpHandlerSet(),
        clientInfo: const <String, Object?>{
          'name': 'client',
          'version': '1.0.0',
        },
      ),
      throwsA(isA<McpHandlerException>()),
    );
    await pair.left.close();
    await pair.right.close();
  });
}
