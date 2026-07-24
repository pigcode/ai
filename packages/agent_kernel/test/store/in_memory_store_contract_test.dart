import '../support/in_memory_agent_store.dart';
import '../support/store_contract.dart';

void main() {
  agentStoreContract(() async => InMemoryAgentStore());
}
