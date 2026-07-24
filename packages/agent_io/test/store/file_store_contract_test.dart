import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../../../agent_kernel/test/support/store_contract.dart';

void main() {
  late Directory temporary;
  late FileStoreCoordinator coordinator;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync(
      'pigcode-file-store-contract-',
    );
    final root = Directory.fromUri(temporary.uri.resolve('store/'))
      ..createSync();
    coordinator = await FileStoreCoordinator.start(
      StoreLayout.open(root),
    );
  });

  tearDown(() async {
    await coordinator.close();
    temporary.deleteSync(recursive: true);
  });

  agentStoreContract(
    () => FileAgentStore.open(
      root: Directory.fromUri(temporary.uri.resolve('store/')),
      coordinator: coordinator.client,
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
      ),
    ),
    mutationDurability: AgentStoreDurability.processCrashFlush,
    unsupportedDurability: AgentStoreDurability.memory,
    compactionAdvancesHistoryFloor: false,
  );
}
