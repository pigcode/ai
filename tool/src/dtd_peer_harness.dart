import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';

final class DtdPeerCommand {
  const DtdPeerCommand({
    required this.peer,
    required this.release,
    required this.dartExecutable,
    required this.fixturePath,
    required this.workingDirectory,
    this.environment = const <String, String>{},
  });

  final String peer;
  final String release;
  final String dartExecutable;
  final String fixturePath;
  final String workingDirectory;
  final Map<String, String> environment;
}

final class DtdPeerReport {
  const DtdPeerReport({
    required this.peer,
    required this.release,
    required this.sdkRevision,
    required this.inventoryDigest,
    required this.transport,
    required this.scenarios,
    required this.observedErrorCodes,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final String release;
  final String sdkRevision;
  final String inventoryDigest;
  final String transport;
  final List<String> scenarios;
  final Set<int> observedErrorCodes;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'release': release,
        'sdkRevision': sdkRevision,
        'inventoryDigest': inventoryDigest,
        'transport': transport,
        'scenarios': scenarios,
        'observedErrorCodes': observedErrorCodes.toList()..sort(),
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

List<String> validateDtdPeerReport(DtdPeerReport report) {
  final violations = <String>[];
  final expectedRevision = switch (report.release) {
    '3.6.0' => dtdMinimumSourceIdentity.sourceRevision,
    '3.12.2' => dtdCurrentSourceIdentity.sourceRevision,
    _ => null,
  };
  if (report.peer.isEmpty ||
      expectedRevision == null ||
      report.sdkRevision != expectedRevision) {
    violations.add('DTD peer SDK identity is invalid.');
  }
  if (report.inventoryDigest != dtdInventorySha256) {
    violations.add('DTD peer inventory digest is invalid.');
  }
  if (report.transport != 'websocket-json-rpc') {
    violations.add('DTD peer transport is invalid.');
  }
  for (final required in const <String>[
    'machineEvent',
    'stream',
    'service',
    'fileSystemDenied',
    'invalidRootSecret',
    'cleanup',
  ]) {
    if (!report.scenarios.contains(required)) {
      violations.add('DTD peer scenario is missing: $required.');
    }
  }
  if (!report.observedErrorCodes.contains(142)) {
    violations.add('DTD peer did not observe permission denial.');
  }
  if (report.elapsedMilliseconds < 0) {
    violations.add('DTD peer duration is invalid.');
  }
  return List<String>.unmodifiable(violations);
}

Future<DtdPeerReport> runDtdPeer(
  DtdPeerCommand command, {
  Duration deadline = const Duration(seconds: 60),
}) async {
  final stopwatch = Stopwatch()..start();
  final devTools = await _ManagedProcess.start(
    command.dartExecutable,
    const <String>[
      'devtools',
      '--machine',
      '--no-launch-browser',
      '--port=0',
      '--print-dtd',
    ],
    workingDirectory: command.workingDirectory,
    environment: command.environment,
  );
  _ManagedProcess? fixture;
  final scenarios = <String>[];
  var completed = false;
  try {
    final daemonUri = await _waitForDtdMachineEvent(
      devTools,
      _remaining(stopwatch, deadline),
    );
    scenarios.add('machineEvent');

    fixture = await _ManagedProcess.start(
      command.dartExecutable,
      <String>[command.fixturePath],
      workingDirectory: command.workingDirectory,
      environment: command.environment,
    );
    await fixture.sendLine(daemonUri.toString());
    await fixture.closeStdin();
    final fixtureReport = await fixture.nextJson(
      _remaining(stopwatch, deadline),
    );
    final fixtureExit = await fixture.waitForExit(
      _remaining(stopwatch, deadline),
    );
    if (fixtureExit != 0) {
      throw StateError('DTD client fixture exited with code $fixtureExit.');
    }
    final fixtureScenarios = fixtureReport['scenarios'];
    final errorCodes = fixtureReport['observedErrorCodes'];
    if (fixtureScenarios is! List<Object?> ||
        fixtureScenarios.any((scenario) => scenario is! String) ||
        errorCodes is! List<Object?> ||
        errorCodes.any((code) => code is! int)) {
      throw StateError('DTD client fixture report is malformed.');
    }
    scenarios.addAll(fixtureScenarios.cast<String>());

    await devTools.terminate(const Duration(seconds: 5));
    scenarios.add('cleanup');
    completed = true;

    final sourceIdentity = command.release == '3.6.0'
        ? dtdMinimumSourceIdentity
        : dtdCurrentSourceIdentity;
    final report = DtdPeerReport(
      peer: command.peer,
      release: command.release,
      sdkRevision: sourceIdentity.sourceRevision,
      inventoryDigest: dtdInventorySha256,
      transport: 'websocket-json-rpc',
      scenarios: List<String>.unmodifiable(scenarios),
      observedErrorCodes: Set<int>.unmodifiable(errorCodes.cast<int>()),
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    final violations = validateDtdPeerReport(report);
    if (violations.isNotEmpty) {
      throw StateError(violations.join(' '));
    }
    return report;
  } finally {
    if (!completed) {
      if (fixture != null) {
        await fixture.terminate(const Duration(seconds: 5));
      }
      await devTools.terminate(const Duration(seconds: 5));
    }
  }
}

Future<Uri> _waitForDtdMachineEvent(
  _ManagedProcess process,
  Duration deadline,
) async {
  final stopwatch = Stopwatch()..start();
  while (true) {
    final envelope = await process.nextJson(_remaining(stopwatch, deadline));
    if (envelope['event'] != 'server.dtdStarted') {
      continue;
    }
    final params = envelope['params'];
    final value = params is Map<String, Object?> ? params['uri'] : null;
    if (value is! String) {
      throw StateError('server.dtdStarted event has no URI.');
    }
    final uri = Uri.parse(value);
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw StateError('server.dtdStarted URI is not WebSocket.');
    }
    return uri;
  }
}

final class _ManagedProcess {
  _ManagedProcess._(
    this.process,
    this._stdout,
    this._stderrDone,
    this._stderr,
  );

  static Future<_ManagedProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: <String, String>{
        ..._sanitizedEnvironment(),
        ...environment,
      },
      includeParentEnvironment: false,
    );
    final stderr = StringBuffer();
    final stderrDone = Completer<void>();
    process.stderr.transform(utf8.decoder).listen(
      (chunk) {
        if (stderr.length < 16 * 1024) {
          final remaining = 16 * 1024 - stderr.length;
          stderr.write(
            chunk.length <= remaining ? chunk : chunk.substring(0, remaining),
          );
        }
      },
      onDone: stderrDone.complete,
      onError: stderrDone.completeError,
      cancelOnError: true,
    );
    return _ManagedProcess._(
      process,
      StreamIterator<String>(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.trim().isNotEmpty),
      ),
      stderrDone.future,
      stderr,
    );
  }

  final Process process;
  final StreamIterator<String> _stdout;
  final Future<void> _stderrDone;
  final StringBuffer _stderr;
  bool _stdinClosed = false;
  bool _terminated = false;

  Future<void> sendLine(String line) async {
    if (_stdinClosed) {
      throw StateError('Managed process stdin is closed.');
    }
    process.stdin.writeln(line);
    await process.stdin.flush();
  }

  Future<Map<String, Object?>> nextJson(Duration deadline) async {
    final available = await _stdout.moveNext().timeout(deadline);
    if (!available) {
      throw StateError(
        'Managed process closed before a machine event. '
        'stderr=${_bounded(_stderr.toString())}',
      );
    }
    final decoded = jsonDecode(_stdout.current);
    if (decoded is! Map<String, Object?>) {
      throw StateError('Machine event must be a JSON object.');
    }
    return decoded;
  }

  Future<void> closeStdin() async {
    if (_stdinClosed) {
      return;
    }
    _stdinClosed = true;
    await process.stdin.close();
  }

  Future<int> waitForExit(Duration deadline) async {
    final code = await process.exitCode.timeout(deadline);
    await _stderrDone.timeout(deadline);
    await _stdout.cancel();
    _terminated = true;
    return code;
  }

  Future<void> terminate(Duration deadline) async {
    if (_terminated) {
      return;
    }
    await closeStdin();
    if (await _isRunning) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(deadline);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(deadline);
      }
    }
    await _stderrDone.timeout(deadline);
    await _stdout.cancel();
    _terminated = true;
  }

  Future<bool> get _isRunning async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }
}

Duration _remaining(Stopwatch stopwatch, Duration deadline) {
  final remaining = deadline - stopwatch.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('DTD peer exceeded its row deadline.');
  }
  return remaining;
}

Map<String, String> _sanitizedEnvironment() => <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };

String _bounded(String value) {
  final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return normalized.length <= 1024
      ? normalized
      : '${normalized.substring(0, 1024)}<truncated>';
}
