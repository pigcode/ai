import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../store/file_store_test_support.dart';

void main() {
  test('P3-TM-DOS-01 domain JSON depth, collection, and string are bounded',
      () {
    expect(
      () => DomainJson.freeze(
        <String, Object?>{
          'nested': <String, Object?>{
            'tooDeep': <String, Object?>{},
          },
        },
        limits: const DomainJsonLimits(maxDepth: 1),
      ),
      throwsA(
        isA<DomainJsonException>().having(
          (error) => error.code,
          'code',
          DomainJsonErrorCode.depthLimit,
        ),
      ),
    );
    expect(
      () => DomainJson.freeze(
        <Object?>[1, 2],
        limits: const DomainJsonLimits(maxCollectionLength: 1),
      ),
      throwsA(isA<DomainJsonException>()),
    );
    expect(
      () => DomainJson.freeze(
        'ab',
        limits: const DomainJsonLimits(maxStringCodeUnits: 1),
      ),
      throwsA(isA<DomainJsonException>()),
    );
  });

  test('P3-TM-DOS-02 segment count fails before a Journal append', () async {
    final fixture = await FileStoreFixture.create(
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        limits: StoreLimits(maximumSegmentCount: 1),
      ),
    );
    try {
      await fixture.createSession();
      final before = (await fixture.store.loadSession(fileTestSessionId)).head;
      final segments =
          StoreLayout.open(fixture.root).segments(fileTestSessionId);
      final countBefore = segments.listSync().length;

      await expectLater(
        fixture.store.append(fileAppendTransaction(before)),
        storeError(AgentStoreErrorCode.resourceLimit),
      );
      expect(segments.listSync(), hasLength(countBefore));
    } finally {
      await fixture.dispose();
    }
  });

  test('P3-TM-DOS-03 event body and batch rate are bounded', () {
    final commandId = fileCommandId(7);
    final bodyLimited = JournalFrameCodec(
      limits: const StoreLimits(maximumEventBodyBytes: 1),
    );
    expect(
      () => bodyLimited.encodeSegment(
        sessionId: fileTestSessionId,
        startSequence: 1,
        previousSegmentFinalDigest: Uint8List(32),
        batches: <JournalBatch>[
          JournalBatch(
            transactionMetadata: const <String, Object?>{},
            events: <AgentEvent>[
              fileEvent(
                1,
                commandId: commandId,
                type: AgentEventType.sessionCreated,
              ),
            ],
          ),
        ],
        seal: true,
      ),
      throwsA(
        isA<StoreFormatException>().having(
          (error) => error.code,
          'code',
          StoreFormatErrorCode.bodyTooLarge,
        ),
      ),
    );

    final rateLimited = JournalFrameCodec(
      limits: const StoreLimits(maximumBatchEventCount: 1),
    );
    expect(
      () => rateLimited.encodeSegment(
        sessionId: fileTestSessionId,
        startSequence: 1,
        previousSegmentFinalDigest: Uint8List(32),
        batches: <JournalBatch>[
          JournalBatch(
            transactionMetadata: const <String, Object?>{},
            events: <AgentEvent>[
              fileEvent(
                1,
                commandId: commandId,
                type: AgentEventType.sessionCreated,
              ),
              fileEvent(
                2,
                commandId: commandId,
                type: AgentEventType.sessionCapabilitiesPinned,
              ),
            ],
          ),
        ],
        seal: true,
      ),
      throwsA(isA<StoreFormatException>()),
    );
  });

  test('P3-TM-DOS-04 replay page and recovery bytes are bounded', () async {
    final fixture = await FileStoreFixture.create();
    try {
      await fixture.createSession();
      final pageLimited = await fixture.open(
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
          limits: StoreLimits(maximumReplayPageEvents: 1),
        ),
      );
      await expectLater(
        pageLimited.readEvents(fileTestSessionId, limit: 2),
        storeError(AgentStoreErrorCode.resourceLimit),
      );

      final recoveryLimited = await fixture.open(
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
          limits: StoreLimits(maximumRecoveryBytes: 1),
        ),
      );
      await expectLater(
        recoveryLimited.loadSession(fileTestSessionId),
        storeError(AgentStoreErrorCode.resourceLimit),
      );
    } finally {
      await fixture.dispose();
    }
  });

  test('P3-TM-DOS-05 registry limit fails before allocation', () async {
    final fixture = await FileStoreFixture.create(
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        limits: StoreLimits(maximumRegistryEntries: 2),
      ),
    );
    try {
      final empty = await fixture.store.loadRoot();
      await expectLater(
        fixture.store.createSession(fileCreateTransaction(empty.head)),
        storeError(AgentStoreErrorCode.resourceLimit),
      );
      expect((await fixture.store.loadRoot()).sessionIds, isEmpty);
    } finally {
      await fixture.dispose();
    }
  });

  test('P3-TM-DOS-06 lock acquisition has a typed deadline', () async {
    final temporary =
        Directory.systemTemp.createTempSync('store-lock-security-');
    final lockFile = File.fromUri(temporary.uri.resolve('store.lock'));
    final worker = await _LockWorker.start(temporary, lockFile);
    try {
      await worker.waitReady();
      await expectLater(
        StoreLock.acquire(
          lockFile,
          timeout: const Duration(milliseconds: 10),
        ),
        storeError(AgentStoreErrorCode.storeBusy),
      );
    } finally {
      await worker.close();
      temporary.deleteSync(recursive: true);
    }
  });
}

final class _LockWorker {
  _LockWorker._(this.process, this._lines, this._errors);

  final Process process;
  final StreamIterator<String> _lines;
  final StringBuffer _errors;

  static Future<_LockWorker> start(
    Directory temporary,
    File lockFile,
  ) async {
    final script = File.fromUri(temporary.uri.resolve('lock_worker.dart'))
      ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = File(arguments.single);
  final handle = await file.open(mode: FileMode.append);
  await handle.lock(FileLock.exclusive);
  stdout.writeln('READY');
  await stdout.flush();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await handle.unlock();
  await handle.close();
}
''');
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[script.path, lockFile.path],
    );
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    return _LockWorker._(
      process,
      StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      errors,
    );
  }

  Future<void> waitReady() async {
    final hasLine = await _lines.moveNext().timeout(const Duration(seconds: 5));
    if (!hasLine || _lines.current != 'READY') {
      throw StateError('Lock worker failed to start: $_errors');
    }
  }

  Future<void> close() async {
    process.stdin.writeln('CLOSE');
    await process.stdin.flush();
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 5));
    await _lines.cancel();
    if (code != 0) {
      throw StateError('Lock worker failed: $_errors');
    }
  }
}
