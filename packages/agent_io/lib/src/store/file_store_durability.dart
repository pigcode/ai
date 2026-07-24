import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'file_store_options.dart';

AgentStoreDurability requireFileStoreDurability(
  AgentStoreDurability requested,
  FileStoreOptions options,
) {
  switch (requested) {
    case AgentStoreDurability.processCrashFlush:
      return AgentStoreDurability.processCrashFlush;
    case AgentStoreDurability.buffered:
      if (options.allowBufferedDurability) {
        return AgentStoreDurability.buffered;
      }
    case AgentStoreDurability.memory:
      break;
  }
  throw const AgentStoreException(
    AgentStoreErrorCode.durabilityUnsupported,
    'FileAgentStore cannot provide the requested durability.',
  );
}
