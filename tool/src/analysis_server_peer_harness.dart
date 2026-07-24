import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class AnalysisServerPeerCommand {
  const AnalysisServerPeerCommand({
    required this.peer,
    required this.release,
    required this.expectedApiVersion,
    required this.dartExecutable,
    required this.workingDirectory,
    required this.workspaceReference,
    required this.sourceReference,
    required this.hoverOffset,
    this.environment = const <String, String>{},
  });

  final String peer;
  final String release;
  final String expectedApiVersion;
  final String dartExecutable;
  final String workingDirectory;
  final String workspaceReference;
  final String sourceReference;
  final int hoverOffset;
  final Map<String, String> environment;
}

final class AnalysisServerPeerReport {
  const AnalysisServerPeerReport({
    required this.peer,
    required this.release,
    required this.apiVersion,
    required this.transport,
    required this.capabilities,
    required this.scenarios,
    required this.errorCount,
    required this.hoverCount,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final String release;
  final String apiVersion;
  final String transport;
  final Map<String, Object?> capabilities;
  final List<String> scenarios;
  final int errorCount;
  final int hoverCount;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'release': release,
        'apiVersion': apiVersion,
        'transport': transport,
        'capabilities': capabilities,
        'scenarios': scenarios,
        'errorCount': errorCount,
        'hoverCount': hoverCount,
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

List<String> validateAnalysisServerPeerReport(
  AnalysisServerPeerReport report,
) {
  final violations = <String>[];
  final expectedVersion = _expectedApiVersions[report.release];
  if (report.peer.isEmpty || expectedVersion == null) {
    violations.add('Analysis Server peer identity is unknown.');
  }
  if (report.apiVersion != expectedVersion) {
    violations.add(
      'Analysis Server API version does not match its exact SDK release.',
    );
  }
  if (report.transport != 'stdio-ndjson') {
    violations.add('Analysis Server peer transport is not stdio NDJSON.');
  }
  if (report.capabilities['supportsUris'] is! bool ||
      report.capabilities['statusSubscription'] != true) {
    violations.add('Analysis Server capability evidence is incomplete.');
  }
  for (final required in const <String>[
    'version',
    'clientCapabilities',
    'setRoots',
    'status',
    'errors',
    'hover',
    'shutdown',
  ]) {
    if (!report.scenarios.contains(required)) {
      violations.add('Analysis Server peer scenario is missing: $required.');
    }
  }
  if (report.errorCount <= 0) {
    violations.add('Analysis Server peer did not publish fixture errors.');
  }
  if (report.hoverCount <= 0) {
    violations.add('Analysis Server peer did not return hover data.');
  }
  if (report.elapsedMilliseconds < 0) {
    violations.add('Analysis Server peer duration is invalid.');
  }
  return List<String>.unmodifiable(violations);
}

Future<AnalysisServerPeerReport> runAnalysisServerPeer(
  AnalysisServerPeerCommand command, {
  Duration deadline = const Duration(seconds: 60),
}) async {
  final stopwatch = Stopwatch()..start();
  final process = await _NdjsonProcess.start(command);
  final connection = AnalysisServerConnection(maxNotifications: 4096);
  final evidence = _AnalysisEvidence();
  final bufferedNotifications = <JsonObject>[];
  final scenarios = <String>[];
  var completed = false;
  try {
    final versionRequest = connection.beginVersionQuery();
    await _sendPending(process, versionRequest);
    final versionResult = await _waitForResponse(
      process,
      versionRequest,
      connection: null,
      evidence: evidence,
      bufferedNotifications: bufferedNotifications,
      stopwatch: stopwatch,
      deadline: deadline,
    );
    if (versionResult is! JsonObject) {
      throw StateError('Analysis Server version result is not an object.');
    }
    connection.completeVersionQuery(
      versionRequest.id,
      versionResult,
      clientCapabilities: const <String, Object?>{
        'requests': <Object?>[],
        'supportsUris': false,
      },
    );
    final apiVersion = connection.capabilities.apiVersion.toString();
    if (apiVersion != command.expectedApiVersion) {
      throw StateError(
        'Analysis Server reported API $apiVersion for SDK ${command.release}.',
      );
    }
    for (final notification in bufferedNotifications) {
      _acceptNotification(connection, evidence, notification);
    }
    scenarios.add('version');

    await _roundTrip(
      process,
      connection,
      evidence,
      method: 'server.setClientCapabilities',
      params: const <String, Object?>{
        'requests': <Object?>[],
        'supportsUris': false,
      },
      stopwatch: stopwatch,
      deadline: deadline,
    );
    scenarios.add('clientCapabilities');

    await _roundTrip(
      process,
      connection,
      evidence,
      method: 'server.setSubscriptions',
      params: const <String, Object?>{
        'subscriptions': <Object?>['STATUS'],
      },
      stopwatch: stopwatch,
      deadline: deadline,
    );

    await _roundTrip(
      process,
      connection,
      evidence,
      method: 'analysis.setAnalysisRoots',
      params: <String, Object?>{
        'included': <Object?>[command.workspaceReference],
        'excluded': const <Object?>[],
      },
      stopwatch: stopwatch,
      deadline: deadline,
    );
    scenarios.add('setRoots');

    await _waitForAnalysis(
      process,
      connection,
      evidence,
      stopwatch: stopwatch,
      deadline: deadline,
    );
    scenarios
      ..add('status')
      ..add('errors');

    final hoverResult = await _roundTrip(
      process,
      connection,
      evidence,
      method: 'analysis.getHover',
      params: <String, Object?>{
        'file': command.sourceReference,
        'offset': command.hoverOffset,
      },
      stopwatch: stopwatch,
      deadline: deadline,
    );
    if (hoverResult is! JsonObject ||
        hoverResult['hovers'] is! List<Object?> ||
        (hoverResult['hovers']! as List<Object?>).isEmpty) {
      throw StateError('Analysis Server returned no hover information.');
    }
    evidence.hoverCount = (hoverResult['hovers']! as List<Object?>).length;
    scenarios.add('hover');

    final shutdown = connection.beginShutdown();
    await _sendPending(process, shutdown);
    final shutdownResult = await _waitForResponse(
      process,
      shutdown,
      connection: connection,
      evidence: evidence,
      stopwatch: stopwatch,
      deadline: deadline,
    );
    connection.completeResponse(
      id: shutdown.id,
      method: shutdown.method,
      result: shutdownResult,
    );
    scenarios.add('shutdown');

    final exitCode = await process.close(_remaining(stopwatch, deadline));
    completed = true;
    if (exitCode != 0) {
      throw StateError('Analysis Server peer exited with code $exitCode.');
    }
    final report = AnalysisServerPeerReport(
      peer: command.peer,
      release: command.release,
      apiVersion: apiVersion,
      transport: 'stdio-ndjson',
      capabilities: const <String, Object?>{
        'supportsUris': false,
        'statusSubscription': true,
      },
      scenarios: List<String>.unmodifiable(scenarios),
      errorCount: evidence.errorCount,
      hoverCount: evidence.hoverCount,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    final violations = validateAnalysisServerPeerReport(report);
    if (violations.isNotEmpty) {
      throw StateError(violations.join(' '));
    }
    return report;
  } finally {
    if (!completed) {
      await process.terminate(_cleanupDeadline(stopwatch, deadline));
    }
  }
}

Future<JsonValue> _roundTrip(
  _NdjsonProcess process,
  AnalysisServerConnection connection,
  _AnalysisEvidence evidence, {
  required String method,
  required Map<String, Object?> params,
  required Stopwatch stopwatch,
  required Duration deadline,
}) async {
  final pending = connection.beginRequest(method, params: params);
  await _sendPending(process, pending);
  final result = await _waitForResponse(
    process,
    pending,
    connection: connection,
    evidence: evidence,
    stopwatch: stopwatch,
    deadline: deadline,
  );
  connection.completeResponse(
    id: pending.id,
    method: pending.method,
    result: result,
  );
  return result;
}

Future<void> _sendPending(
  _NdjsonProcess process,
  AnalysisServerPendingRequest pending,
) =>
    process.send(<String, Object?>{
      'id': pending.id,
      'method': pending.method,
      if (pending.params != null) 'params': pending.params,
    });

Future<JsonValue> _waitForResponse(
  _NdjsonProcess process,
  AnalysisServerPendingRequest pending, {
  required AnalysisServerConnection? connection,
  required _AnalysisEvidence evidence,
  List<JsonObject>? bufferedNotifications,
  required Stopwatch stopwatch,
  required Duration deadline,
}) async {
  while (true) {
    final envelope = await process.next(_remaining(stopwatch, deadline));
    if (envelope['id'] == pending.id && !envelope.containsKey('method')) {
      final error = envelope['error'];
      if (error != null) {
        final code = error is JsonObject ? error['code'] : 'invalid';
        throw StateError(
          'Analysis Server returned error code $code for ${pending.method}.',
        );
      }
      return envelope['result'];
    }
    if (envelope['event'] is String) {
      if (connection == null) {
        bufferedNotifications!.add(envelope);
      } else {
        _acceptNotification(connection, evidence, envelope);
      }
      continue;
    }
    if (envelope['id'] is String && envelope['method'] is String) {
      await process.send(<String, Object?>{
        'id': envelope['id'],
        'error': const <String, Object?>{
          'code': 'UNSUPPORTED_FEATURE',
          'message': 'No matrix handler is registered.',
        },
      });
      continue;
    }
    throw StateError('Analysis Server emitted an unknown envelope.');
  }
}

void _acceptNotification(
  AnalysisServerConnection connection,
  _AnalysisEvidence evidence,
  JsonObject envelope,
) {
  final event = envelope['event'];
  final params = envelope['params'];
  if (event is! String || params != null && params is! JsonObject) {
    throw StateError('Analysis Server notification envelope is malformed.');
  }
  final record = connection.receiveNotification(
    event,
    params as JsonObject? ?? const <String, Object?>{},
  );
  evidence.accept(record);
}

Future<void> _waitForAnalysis(
  _NdjsonProcess process,
  AnalysisServerConnection connection,
  _AnalysisEvidence evidence, {
  required Stopwatch stopwatch,
  required Duration deadline,
}) async {
  while (!evidence.analysisComplete || !evidence.errorsObserved) {
    final envelope = await process.next(_remaining(stopwatch, deadline));
    if (envelope['event'] is String) {
      _acceptNotification(connection, evidence, envelope);
      continue;
    }
    if (envelope['id'] is String && envelope['method'] is String) {
      await process.send(<String, Object?>{
        'id': envelope['id'],
        'error': const <String, Object?>{
          'code': 'UNSUPPORTED_FEATURE',
          'message': 'No matrix handler is registered.',
        },
      });
      continue;
    }
    throw StateError(
      'Analysis Server emitted an unexpected envelope while analyzing.',
    );
  }
}

final class _AnalysisEvidence {
  bool analysisComplete = false;
  bool errorsObserved = false;
  int errorCount = 0;
  int hoverCount = 0;

  void accept(AnalysisServerNotificationRecord record) {
    if (record.event == 'server.status') {
      final analysis = record.params['analysis'];
      if (analysis is JsonObject && analysis['isAnalyzing'] == false) {
        analysisComplete = true;
      }
    } else if (record.event == 'analysis.errors') {
      errorsObserved = true;
      final errors = record.params['errors'];
      if (errors is List<Object?> && errors.length > errorCount) {
        errorCount = errors.length;
      }
    }
  }
}

final class _NdjsonProcess {
  _NdjsonProcess._(
    this.process,
    this._messages,
    this._stderrDone,
    this._stderr,
  );

  static Future<_NdjsonProcess> start(
    AnalysisServerPeerCommand command,
  ) async {
    final process = await Process.start(
      command.dartExecutable,
      const <String>['language-server', '--protocol=analyzer'],
      workingDirectory: command.workingDirectory,
      environment: <String, String>{
        ..._sanitizedEnvironment(),
        ...command.environment,
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
    final messages = StreamIterator<JsonObject>(
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
        final value = jsonDecode(line);
        if (value is! JsonObject) {
          throw const FormatException(
            'Analysis Server line must contain a JSON object.',
          );
        }
        return value;
      }),
    );
    return _NdjsonProcess._(
      process,
      messages,
      stderrDone.future,
      stderr,
    );
  }

  final Process process;
  final StreamIterator<JsonObject> _messages;
  final Future<void> _stderrDone;
  final StringBuffer _stderr;
  bool _stdinClosed = false;

  Future<void> send(JsonObject envelope) async {
    if (_stdinClosed) {
      throw StateError('Analysis Server stdin is closed.');
    }
    process.stdin.writeln(jsonEncode(envelope));
    await process.stdin.flush();
  }

  Future<JsonObject> next(Duration deadline) async {
    final available = await _messages.moveNext().timeout(deadline);
    if (!available) {
      throw StateError(
        'Analysis Server closed before the expected message. '
        'stderr=${_boundedDiagnostic(_stderr.toString())}',
      );
    }
    return _messages.current;
  }

  Future<int> close(Duration deadline) async {
    await _closeStdin();
    final code = await process.exitCode.timeout(deadline);
    await _stderrDone.timeout(deadline);
    await _messages.cancel();
    return code;
  }

  Future<void> terminate(Duration deadline) async {
    await _closeStdin();
    if (await _isRunning) {
      process.kill();
      await process.exitCode.timeout(deadline);
    }
    await _stderrDone.timeout(deadline);
    await _messages.cancel();
  }

  Future<void> _closeStdin() async {
    if (_stdinClosed) {
      return;
    }
    _stdinClosed = true;
    await process.stdin.close();
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
    throw TimeoutException('Analysis Server peer exceeded its row deadline.');
  }
  return remaining;
}

Duration _cleanupDeadline(Stopwatch stopwatch, Duration deadline) {
  final remaining = deadline - stopwatch.elapsed;
  return remaining > const Duration(seconds: 5)
      ? const Duration(seconds: 5)
      : remaining > Duration.zero
          ? remaining
          : const Duration(seconds: 1);
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

String _boundedDiagnostic(String value) {
  final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return normalized.length <= 1024
      ? normalized
      : '${normalized.substring(0, 1024)}<truncated>';
}

const _expectedApiVersions = <String, String>{
  '3.6.0': '1.38.0',
  '3.12.2': '1.40.1',
};
