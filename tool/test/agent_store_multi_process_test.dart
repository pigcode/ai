import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

import '../src/agent_store_writer_fixture.dart';

const _workerPath = 'tool/fixtures/agent_store_writer.dart';
const _timeout = Duration(seconds: 10);

Future<void> main() async {
  final temporary = Directory.systemTemp.createTempSync(
    'pigcode-agent-store-process-',
  );
  final root = Directory.fromUri(temporary.uri.resolve('store/'))..createSync();
  try {
    final setupCoordinator = await FileStoreCoordinator.start(
      StoreLayout.open(root),
    );
    try {
      final store = await FileAgentStore.open(
        root: root,
        coordinator: setupCoordinator.client,
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        ),
      );
      final empty = await store.loadRoot();
      await store.createSession(fixtureCreateTransaction(empty.head));
    } finally {
      await setupCoordinator.close();
    }

    final first = await _WriterProcess.start(root.path, 1);
    final second = await _WriterProcess.start(root.path, 2);
    try {
      await Future.wait<void>(
        <Future<void>>[first.waitReady(), second.waitReady()],
      ).timeout(_timeout);
      await Future.wait<void>(
        <Future<void>>[first.release(), second.release()],
      );
      final results = await Future.wait<String>(
        <Future<String>>[first.waitResult(), second.waitResult()],
      ).timeout(_timeout);
      await Future.wait<int>(
        <Future<int>>[first.waitExit(), second.waitExit()],
      ).timeout(_timeout);

      _expect(
        results.where((line) => line.contains(' ok ')).length == 1,
        'Expected exactly one process append success: $results',
      );
      _expect(
        results
                .where((line) => line.contains(' error sequenceConflict'))
                .length ==
            1,
        'Expected exactly one stale process conflict: $results',
      );
    } finally {
      first.killIfRunning();
      second.killIfRunning();
    }

    final verifyCoordinator = await FileStoreCoordinator.start(
      StoreLayout.open(root),
    );
    try {
      final store = await FileAgentStore.open(
        root: root,
        coordinator: verifyCoordinator.client,
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        ),
      );
      final events = await store.readEvents(fixtureSessionId);
      _expect(
        events.events.map((event) => event.sequence).join(',') == '1,2',
        'Journal is not the complete winning prefix.',
      );
    } finally {
      await verifyCoordinator.close();
    }
    stdout.writeln('PASS agent Store multi-process CAS');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

final class _WriterProcess {
  _WriterProcess._(
    this.process,
    this._lines,
    this._stderr,
  );

  final Process process;
  final StreamIterator<String> _lines;
  final StringBuffer _stderr;
  bool _exited = false;

  static Future<_WriterProcess> start(String root, int variant) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[_workerPath, root, '$variant'],
      workingDirectory: Directory.current.absolute.path,
    );
    final stderr = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    return _WriterProcess._(
      process,
      StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      stderr,
    );
  }

  Future<void> waitReady() async {
    final line = await _nextLine();
    _expect(line.startsWith('READY '), 'Worker did not become ready: $line');
  }

  Future<void> release() async {
    process.stdin.writeln('GO');
    await process.stdin.flush();
    await process.stdin.close();
  }

  Future<String> waitResult() async {
    final line = await _nextLine();
    _expect(
        line.startsWith('RESULT '), 'Worker returned invalid result: $line');
    return line;
  }

  Future<int> waitExit() async {
    final code = await process.exitCode;
    await _lines.cancel();
    _exited = true;
    _expect(
      code == 0,
      'Worker exited $code: ${_stderr.toString()}',
    );
    return code;
  }

  void killIfRunning() {
    if (!_exited) process.kill(ProcessSignal.sigkill);
  }

  Future<String> _nextLine() async {
    final available = await _lines.moveNext().timeout(_timeout);
    if (!available) {
      throw StateError(
        'Worker closed stdout: ${_stderr.toString()}',
      );
    }
    return _lines.current;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
