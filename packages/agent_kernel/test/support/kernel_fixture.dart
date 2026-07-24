import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'in_memory_agent_store.dart';
import 'virtual_agent_clock.dart';

final class KernelFixture {
  KernelFixture({InMemoryAgentStore? store})
      : store = store ?? InMemoryAgentStore() {
    var counter = 0;
    kernel = AgentKernel(
      store: this.store,
      idGenerator: OpaqueIdGenerator(
        byteSource: (length) {
          final bytes = List<int>.filled(length, 0);
          bytes[length - 1] = counter++;
          return bytes;
        },
      ),
      clock: VirtualAgentClock(DateTime.utc(2026, 7, 24)),
      durability: AgentStoreDurability.memory,
    );
  }

  final InMemoryAgentStore store;
  late final AgentKernel kernel;

  Future<(AgentCommandReceipt, CreateSessionCommand)> createSession({
    CommandId? commandId,
    String definitionRef = 'agent:test',
    Map<String, Object?> capabilities = const <String, Object?>{
      'run': true,
    },
  }) async {
    final root = await store.loadRoot();
    final command = CreateSessionCommand(
      commandId: commandId ?? createCommandId,
      expectedRootHead: root.head,
      definitionRef: AgentDefinitionRef(definitionRef),
      capabilitySnapshot: CapabilitySnapshot(capabilities),
    );
    return (await kernel.createSession(command), command);
  }
}

final createCommandId = CommandId.parse('cmd_00000000000000000000000000000000');
final startCommandId = CommandId.parse('cmd_10000000000000000000000000000000');
final secondStartCommandId =
    CommandId.parse('cmd_20000000000000000000000000000000');
