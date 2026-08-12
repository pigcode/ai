import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:pigcode_ai_agent_io/src/exec/process_cleanup_ledger.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

void main() {
  test('cleanup ledger preserves concurrent isolate records atomically',
      () async {
    final root = await Directory.systemTemp.createTemp('ledger-isolates-');
    final path = '${root.path}/ledger.json';
    try {
      await Future.wait<void>(<Future<void>>[
        for (var worker = 0; worker < 12; worker += 1)
          Isolate.run(() async {
            final ledger = ProcessCleanupLedger(path);
            for (var index = 0; index < 20; index += 1) {
              await ledger.record(
                ProcessCleanupRecord(
                  sessionIdentity: 'isolate-$worker',
                  processGroupId: worker * 100000 + index,
                  processIdentity: 'identity-$worker-$index',
                ),
              );
            }
          }),
      ]).timeout(const Duration(seconds: 20));
      expect(await ProcessCleanupLedger(path).all(), hasLength(240));
      expect(await _temporaryFiles(root), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('cleanup ledger preserves concurrent real-process records atomically',
      () async {
    final root = await Directory.systemTemp.createTemp('ledger-processes-');
    final path = '${root.path}/ledger.json';
    final fixture = resolveTestWorkspacePath(
      packageRelative: 'test/fixtures/cleanup_ledger_writer.dart',
      workspaceRelative:
          'packages/agent_io/test/fixtures/cleanup_ledger_writer.dart',
    );
    final processes = <Process>[];
    try {
      for (var worker = 0; worker < 8; worker += 1) {
        processes.add(
          await Process.start(
            Platform.resolvedExecutable,
            <String>[fixture, path, '$worker', '25'],
            runInShell: false,
          ),
        );
      }
      for (final process in processes) {
        process.stdout.drain<void>();
        final errors = process.stderr.transform(utf8.decoder).join();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 20)),
          0,
          reason: await errors,
        );
      }
      expect(await ProcessCleanupLedger(path).all(), hasLength(200));
      expect(await _temporaryFiles(root), isEmpty);
    } finally {
      for (final process in processes) {
        process.kill(ProcessSignal.sigkill);
      }
      await root.delete(recursive: true);
    }
  });
}

Future<List<FileSystemEntity>> _temporaryFiles(Directory root) async =>
    root
        .list()
        .where(
          (entry) =>
              entry.path.contains('.tmp.') || entry.path.endsWith('.guard'),
        )
        .toList();
