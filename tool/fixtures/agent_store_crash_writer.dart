import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

import '../src/agent_store_writer_fixture.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: agent_store_crash_writer.dart <root> <scenario>');
    exitCode = 64;
    return;
  }
  final root = Directory(arguments[0]);
  final scenario = arguments[1];
  final layout = StoreLayout.open(root);
  var reached = false;

  Future<void> boundary() async {
    if (reached) return;
    reached = true;
    stdout.writeln('BOUNDARY $scenario');
    await stdout.flush();
    await Completer<void>().future;
  }

  final options = FileStoreOptions(
    rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
    retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
    faults: StoreWriterFaults((point, target) async {
      final isJournal = target.path.endsWith('.pigj');
      final isSnapshot = target.path.endsWith('.pigs');
      final isSessionManifest =
          target.parent.path == layout.manifests(fixtureSessionId).path;
      final matches = switch (scenario) {
        'append-before-frame' =>
          isJournal && point == StoreWriterFaultPoint.beforeWrite,
        'append-mid-frame' ||
        'append-mid-multi-event-batch' =>
          isJournal && point == StoreWriterFaultPoint.afterWrite,
        'append-after-trailer-before-flush' =>
          isJournal && point == StoreWriterFaultPoint.beforeFlush,
        'snapshot-mid-write' =>
          isSnapshot && point == StoreWriterFaultPoint.afterWrite,
        'snapshot-after-flush' =>
          isSnapshot && point == StoreWriterFaultPoint.beforePublish,
        'manifest-mid-write' =>
          isSessionManifest && point == StoreWriterFaultPoint.afterWrite,
        'manifest-after-flush' =>
          isSessionManifest && point == StoreWriterFaultPoint.beforePublish,
        _ => false,
      };
      if (matches) await boundary();
    }),
    commitFaults: StoreCommitFaults((point) async {
      final matches = (scenario == 'append-after-flush-before-receipt' &&
              point == StoreCommitPoint.append) ||
          (scenario == 'compact-after-manifest' &&
              point == StoreCommitPoint.compaction);
      if (matches) await boundary();
    }),
    garbageCollectionFaults: StoreGarbageCollectionFaults(
      (point, artifact) async {
        final matches = (scenario == 'compact-mid-retire' &&
                point == StoreGarbageCollectionFaultPoint.beforeRetire) ||
            (scenario == 'compact-mid-gc' &&
                point == StoreGarbageCollectionFaultPoint.beforeDelete);
        if (matches) await boundary();
      },
    ),
  );
  final coordinator = await FileStoreCoordinator.start(layout);
  try {
    final store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
      options: options,
    );
    final session = await store.loadSession(fixtureSessionId);
    switch (scenario) {
      case 'append-before-frame':
      case 'append-mid-frame':
      case 'append-after-trailer-before-flush':
      case 'append-after-flush-before-receipt':
      case 'manifest-mid-write':
      case 'manifest-after-flush':
        await store.append(
          fixtureAppendTransaction(session.head, 8),
        );
      case 'append-mid-multi-event-batch':
        await store.append(
          fixtureMultiEventAppendTransaction(session.head, 8),
        );
      case 'snapshot-mid-write':
      case 'snapshot-after-flush':
        await store.writeSnapshot(
          fixtureSnapshot(session.head),
          expectedHead: session.head,
        );
      case 'compact-after-manifest':
        await store.compact(
          fixtureSessionId,
          expectedHead: session.head,
          throughSequence: 1,
        );
      case 'compact-mid-retire':
      case 'compact-mid-gc':
        await store.garbageCollect(fixtureSessionId);
      default:
        throw ArgumentError.value(scenario, 'scenario');
    }
    throw StateError('Scenario completed without reaching its boundary.');
  } finally {
    await coordinator.close();
  }
}
