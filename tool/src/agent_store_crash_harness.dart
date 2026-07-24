import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'agent_store_writer_fixture.dart';

const agentStoreCrashScenarios = <String>[
  'append-before-frame',
  'append-mid-frame',
  'append-mid-multi-event-batch',
  'append-after-trailer-before-flush',
  'append-after-flush-before-receipt',
  'snapshot-mid-write',
  'snapshot-after-flush',
  'manifest-mid-write',
  'manifest-after-flush',
  'compact-after-manifest',
  'compact-mid-retire',
  'compact-mid-gc',
];

const _crashWorkerPath = 'tool/fixtures/agent_store_crash_writer.dart';
const _deadline = Duration(seconds: 10);

final class AgentStoreCrashReport {
  AgentStoreCrashReport({
    required this.scenario,
    required this.sessionSequence,
    required this.historyFloorSequence,
    required this.eventCount,
    required this.rootDigest,
    required this.sessionDigest,
    required Map<String, String> artifactDigests,
  }) : artifactDigests = Map<String, String>.unmodifiable(artifactDigests);

  final String scenario;
  final int sessionSequence;
  final int historyFloorSequence;
  final int eventCount;
  final String rootDigest;
  final String sessionDigest;
  final Map<String, String> artifactDigests;

  Map<String, Object?> toJson() => <String, Object?>{
        'artifactDigests': artifactDigests,
        'eventCount': eventCount,
        'historyFloorSequence': historyFloorSequence,
        'rootDigest': rootDigest,
        'scenario': scenario,
        'sessionDigest': sessionDigest,
        'sessionSequence': sessionSequence,
      };
}

Future<List<AgentStoreCrashReport>> runAgentStoreCrashMatrix(
  Iterable<String> scenarios,
) async {
  final reports = <AgentStoreCrashReport>[];
  for (final scenario in scenarios) {
    if (!agentStoreCrashScenarios.contains(scenario)) {
      throw ArgumentError.value(scenario, 'scenario');
    }
    reports.add(await runAgentStoreCrashScenario(scenario));
  }
  return reports;
}

Future<AgentStoreCrashReport> runAgentStoreCrashScenario(
  String scenario,
) async {
  final temporary = Directory.systemTemp.createTempSync(
    'pigcode-agent-store-crash-',
  );
  final root = Directory.fromUri(temporary.uri.resolve('store/'))..createSync();
  try {
    final prepared = await _prepare(root, scenario);
    final child = await _CrashProcess.start(root.path, scenario);
    try {
      await child.waitBoundary().timeout(_deadline);
      await child.killAndWait().timeout(_deadline);
    } finally {
      child.killIfRunning();
    }
    return await _verify(root, scenario, prepared);
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<_PreparedCrashStore> _prepare(
  Directory root,
  String scenario,
) async {
  final coordinator = await FileStoreCoordinator.start(
    StoreLayout.open(root),
  );
  try {
    final store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
      ),
    );
    final empty = await store.loadRoot();
    await store.createSession(fixtureCreateTransaction(empty.head));
    final appendExpected = (await store.loadSession(fixtureSessionId)).head;
    AgentStoreHead? compactExpected;
    if (scenario.startsWith('compact-')) {
      await store.append(fixtureAppendTransaction(appendExpected, 1));
      final appendHead = (await store.loadSession(fixtureSessionId)).head;
      final snapshotReceipt = await store.writeSnapshot(
        fixtureSnapshot(appendHead, variant: 1),
        expectedHead: appendHead,
      );
      compactExpected = snapshotReceipt.afterHead;
      if (scenario == 'compact-mid-retire' || scenario == 'compact-mid-gc') {
        await store.compact(
          fixtureSessionId,
          expectedHead: compactExpected,
          throughSequence: appendHead.sequence,
        );
        final compactHead = (await store.loadSession(fixtureSessionId)).head;
        await store.writeSnapshot(
          fixtureSnapshot(compactHead, variant: 2),
          expectedHead: compactHead,
        );
        if (scenario == 'compact-mid-gc') {
          await store.garbageCollect(fixtureSessionId);
        }
      }
    }
    return _PreparedCrashStore(
      appendExpected: appendExpected,
      compactExpected: compactExpected,
    );
  } finally {
    await coordinator.close();
  }
}

Future<AgentStoreCrashReport> _verify(
  Directory root,
  String scenario,
  _PreparedCrashStore prepared,
) async {
  final coordinator = await FileStoreCoordinator.start(
    StoreLayout.open(root),
  );
  try {
    final store = await FileAgentStore.open(
      root: root,
      coordinator: coordinator.client,
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        retentionPolicy: StoreRetentionPolicy.pruneThroughSnapshot,
      ),
    );
    if (scenario.startsWith('append-') || scenario.startsWith('manifest-')) {
      final transaction = scenario == 'append-mid-multi-event-batch'
          ? fixtureMultiEventAppendTransaction(prepared.appendExpected, 8)
          : fixtureAppendTransaction(prepared.appendExpected, 8);
      final beforeRetry = await store.loadSession(fixtureSessionId);
      final committedBeforeReceipt =
          scenario == 'append-after-flush-before-receipt';
      if (committedBeforeReceipt) {
        _expect(
          beforeRetry.head.sequence == transaction.events.last.sequence,
          '$scenario lost a flushed append.',
        );
      } else {
        _expect(
          beforeRetry.head.sequence == prepared.appendExpected.sequence,
          '$scenario exposed an uncommitted append.',
        );
      }
      await store.append(transaction);
      final page = await store.readEvents(fixtureSessionId);
      _expect(
        page.events.length == transaction.events.length + 1,
        '$scenario retry duplicated or lost a batch.',
      );
    } else if (scenario.startsWith('snapshot-')) {
      final before = await store.loadSession(fixtureSessionId);
      if (before.snapshot == null) {
        await store.writeSnapshot(
          fixtureSnapshot(prepared.appendExpected),
          expectedHead: prepared.appendExpected,
        );
      }
      _expect(
        (await store.loadSession(fixtureSessionId)).snapshot != null,
        '$scenario has no recoverable snapshot generation.',
      );
    } else if (scenario == 'compact-after-manifest') {
      final recovered = await store.loadSession(fixtureSessionId);
      _expect(
        recovered.head.historyFloorSequence == 1,
        'Flushed compaction generation was not recovered.',
      );
      await store.compact(
        fixtureSessionId,
        expectedHead: prepared.compactExpected!,
        throughSequence: 1,
      );
    } else {
      await store.loadSession(fixtureSessionId);
      await store.garbageCollect(fixtureSessionId);
      await store.loadSession(fixtureSessionId);
    }

    final rootState = await store.loadRoot();
    final session = await store.loadSession(fixtureSessionId);
    final events = await store.readEvents(
      fixtureSessionId,
      after: AgentStoreCursor(session.head.historyFloorSequence),
    );
    return AgentStoreCrashReport(
      scenario: scenario,
      sessionSequence: session.head.sequence,
      historyFloorSequence: session.head.historyFloorSequence,
      eventCount: events.events.length,
      rootDigest: rootState.head.stateDigest,
      sessionDigest: session.head.stateDigest,
      artifactDigests: _artifactDigests(root),
    );
  } finally {
    await coordinator.close();
  }
}

Map<String, String> _artifactDigests(Directory root) {
  final result = <String, String>{};
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path.substring(0, root.absolute.path.length - 1)
      : root.absolute.path;
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final file in files) {
    final filePath = file.absolute.path;
    final prefix = '$rootPath${Platform.pathSeparator}';
    if (!filePath.startsWith(prefix)) {
      throw StateError('Crash artifact escaped its temporary Store root.');
    }
    result[filePath.substring(prefix.length)] =
        storeHex(storeSha256(file.readAsBytesSync()));
  }
  return result;
}

final class _PreparedCrashStore {
  const _PreparedCrashStore({
    required this.appendExpected,
    required this.compactExpected,
  });

  final AgentStoreHead appendExpected;
  final AgentStoreHead? compactExpected;
}

final class _CrashProcess {
  _CrashProcess._(
    this.process,
    this.scenario,
    this._stdout,
    this._stderr,
  );

  final Process process;
  final String scenario;
  final StreamIterator<String> _stdout;
  final StringBuffer _stderr;
  bool _exited = false;

  static Future<_CrashProcess> start(String root, String scenario) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[_crashWorkerPath, root, scenario],
      workingDirectory: Directory.current.absolute.path,
    );
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    return _CrashProcess._(
      process,
      scenario,
      StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      errors,
    );
  }

  Future<void> waitBoundary() async {
    final hasLine = await _stdout.moveNext();
    if (!hasLine || _stdout.current != 'BOUNDARY $scenario') {
      final line = hasLine ? _stdout.current : '<closed>';
      throw StateError('Crash worker missed boundary: $line $_stderr');
    }
  }

  Future<void> killAndWait() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await _stdout.cancel();
    _exited = true;
  }

  void killIfRunning() {
    if (!_exited) process.kill(ProcessSignal.sigkill);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
