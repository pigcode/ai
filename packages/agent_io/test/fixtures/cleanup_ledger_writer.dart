import 'dart:io';

import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) exit(64);
  final ledger = ProcessCleanupLedger(arguments[0]);
  final worker = int.parse(arguments[1]);
  final count = int.parse(arguments[2]);
  for (var index = 0; index < count; index += 1) {
    await ledger.record(
      ProcessCleanupRecord(
        sessionIdentity: 'worker-$worker',
        processGroupId: worker * 100000 + index,
        processIdentity: 'identity-$worker-$index',
      ),
    );
  }
}
