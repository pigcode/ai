import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import '../src/agent_store_writer_fixture.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: agent_store_writer.dart <root> <variant>');
    exitCode = 64;
    return;
  }
  final root = Directory(arguments[0]);
  final variant = int.parse(arguments[1]);
  final coordinator = await FileStoreCoordinator.start(
    StoreLayout.open(root),
  );
  try {
    final store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
      ),
    );
    final expected = (await store.loadSession(fixtureSessionId)).head;
    stdout.writeln('READY $variant');
    final line = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    if (line != 'GO') {
      throw StateError('Unexpected barrier command.');
    }
    try {
      final receipt = await store.append(
        fixtureAppendTransaction(expected, variant),
      );
      stdout.writeln('RESULT $variant ok ${receipt.afterHead.sequence}');
    } on AgentStoreException catch (error) {
      stdout.writeln('RESULT $variant error ${error.code.name}');
    }
  } finally {
    await coordinator.close();
  }
}
