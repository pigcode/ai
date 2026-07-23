import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

import 'support/memory_transport.dart';

void main() {
  test('round-trips the complete client capability powerset', () {
    for (var mask = 0; mask < 1 << 4; mask += 1) {
      final capabilities = AcpClientCapabilities(
        readTextFile: mask & 1 != 0,
        writeTextFile: mask & 2 != 0,
        terminal: mask & 4 != 0,
        booleanConfigOptions: mask & 8 != 0,
      );

      expect(
        AcpClientCapabilities.fromJson(capabilities.toJson()),
        capabilities,
      );
    }
  });

  test('round-trips the complete agent capability powerset', () {
    for (var mask = 0; mask < 1 << 12; mask += 1) {
      final capabilities = AcpAgentCapabilities(
        loadSession: mask & 1 != 0,
        promptImage: mask & 2 != 0,
        promptAudio: mask & 4 != 0,
        promptEmbeddedContext: mask & 8 != 0,
        mcpHttp: mask & 16 != 0,
        mcpSse: mask & 32 != 0,
        sessionList: mask & 64 != 0,
        sessionDelete: mask & 128 != 0,
        additionalDirectories: mask & 256 != 0,
        sessionResume: mask & 512 != 0,
        sessionClose: mask & 1024 != 0,
        logout: mask & 2048 != 0,
      );

      expect(
        AcpAgentCapabilities.fromJson(capabilities.toJson()),
        capabilities,
      );
    }
  });

  test('rejects a claimed capability without its handler', () async {
    final pair = MemoryTransportPair.create();

    expect(
      () => AcpAgent(
        transport: pair.right,
        capabilities: AcpAgentCapabilities(sessionList: true),
        handlers: AcpHandlerSet(),
      ),
      throwsA(
        isA<AcpHandlerException>().having(
          (error) => error.code,
          'code',
          'acp_claimed_capability_missing_handler',
        ),
      ),
    );
    expect(
      () => AcpClient(
        transport: pair.left,
        capabilities: AcpClientCapabilities(readTextFile: true),
        handlers: AcpHandlerSet(),
      ),
      throwsA(isA<AcpHandlerException>()),
    );
    await pair.left.close();
    await pair.right.close();
  });
}
