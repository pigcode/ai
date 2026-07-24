import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';

final class VmServicePeerCommand {
  const VmServicePeerCommand({
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

final class VmServicePeerReport {
  const VmServicePeerReport({
    required this.peer,
    required this.release,
    required this.sdkRevision,
    required this.wireVersion,
    required this.transport,
    required this.observedProtocols,
    required this.scenarios,
    required this.sentinelKind,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final String release;
  final String sdkRevision;
  final String wireVersion;
  final String transport;
  final List<String> observedProtocols;
  final List<String> scenarios;
  final String sentinelKind;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'release': release,
        'sdkRevision': sdkRevision,
        'wireVersion': wireVersion,
        'transport': transport,
        'observedProtocols': observedProtocols,
        'scenarios': scenarios,
        'sentinelKind': sentinelKind,
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

List<String> validateVmServicePeerReport(VmServicePeerReport report) {
  final violations = <String>[];
  final expected = switch (report.release) {
    '3.6.0' => (
        revision: vmServiceMinimumSourceIdentity.sourceRevision,
        version: vmServiceMinimumRuntimeVersion.toString(),
      ),
    '3.12.2' => (
        revision: vmServiceCurrentSourceIdentity.sourceRevision,
        version: vmServiceCurrentRuntimeVersion.toString(),
      ),
    _ => null,
  };
  if (report.peer.isEmpty ||
      expected == null ||
      report.sdkRevision != expected.revision) {
    violations.add('VM Service peer SDK identity is invalid.');
  }
  if (expected == null || report.wireVersion != expected.version) {
    violations.add('VM Service peer wire version is invalid.');
  }
  if (report.transport != 'websocket-json-rpc') {
    violations.add('VM Service peer transport is invalid.');
  }
  if (report.observedProtocols.isEmpty ||
      report.observedProtocols.any((protocol) => protocol.isEmpty)) {
    violations.add('VM Service observed protocol snapshot is empty.');
  }
  for (final required in const <String>[
    'machineEvent',
    'version',
    'supportedProtocols',
    'vm',
    'stream',
    'isolate',
    'object',
    'temporaryIdExpired',
    'disconnect',
    'cleanup',
  ]) {
    if (!report.scenarios.contains(required)) {
      violations.add('VM Service peer scenario is missing: $required.');
    }
  }
  if (report.sentinelKind != 'Expired') {
    violations.add('VM Service peer did not observe an Expired Sentinel.');
  }
  if (report.elapsedMilliseconds < 0) {
    violations.add('VM Service peer duration is invalid.');
  }
  return List<String>.unmodifiable(violations);
}

Future<VmServicePeerReport> runVmServicePeer(
  VmServicePeerCommand command, {
  Duration deadline = const Duration(seconds: 45),
}) async {
  final stopwatch = Stopwatch()..start();
  final fixture = await _FixtureProcess.start(command);
  _JsonRpcSocket? rpc;
  var completed = false;
  final scenarios = <String>[];
  try {
    final machineEvent = await fixture.nextMachineEvent(
      _remaining(stopwatch, deadline),
    );
    final params = machineEvent['params'];
    if (machineEvent['event'] != 'vmService.started' ||
        params is! Map<String, Object?> ||
        params['webSocketUri'] is! String ||
        params['isolateId'] is! String ||
        params['objectId'] is! String) {
      throw StateError('VM Service fixture machine event is malformed.');
    }
    final webSocketUri = Uri.parse(params['webSocketUri']! as String);
    if (webSocketUri.scheme != 'ws' && webSocketUri.scheme != 'wss') {
      throw StateError('VM Service fixture URI is not WebSocket.');
    }
    final fixtureIsolateId = params['isolateId']! as String;
    final fixtureObjectId = params['objectId']! as String;
    scenarios.add('machineEvent');

    Map<String, Object?>? version;
    Object? connectionFailure;
    for (var attempt = 0; attempt < 3 && version == null; attempt++) {
      try {
        rpc = await _JsonRpcSocket.connect(
          webSocketUri,
          _remaining(stopwatch, deadline),
        );
        version = await rpc.request(
          'getVersion',
          const <String, Object?>{},
          _remaining(stopwatch, deadline),
        );
      } on Object catch (error) {
        connectionFailure = error;
        if (rpc != null) {
          await rpc.close(const Duration(seconds: 2));
          rpc = null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (version == null || rpc == null) {
      throw StateError(
        'VM Service initial handshake failed: $connectionFailure.',
      );
    }
    if (version['type'] != 'Version' ||
        version['major'] is! int ||
        version['minor'] is! int) {
      throw StateError('VM Service getVersion response is malformed.');
    }
    final wireVersion = '${version['major']}.${version['minor']}';
    scenarios.add('version');

    final protocolList = await rpc.request(
      'getSupportedProtocols',
      const <String, Object?>{},
      _remaining(stopwatch, deadline),
    );
    final protocols = protocolList['protocols'];
    if (protocolList['type'] != 'ProtocolList' ||
        protocols is! List<Object?> ||
        protocols.isEmpty) {
      throw StateError('VM Service ProtocolList response is malformed.');
    }
    final observedProtocols = protocols.map((value) {
      if (value is! Map<String, Object?> ||
          value['protocolName'] is! String ||
          value['major'] is! int ||
          value['minor'] is! int) {
        throw StateError('VM Service Protocol entry is malformed.');
      }
      return '${value['protocolName']}@${value['major']}.${value['minor']}';
    }).toList(growable: false);
    scenarios.add('supportedProtocols');

    final vm = await rpc.request(
      'getVM',
      const <String, Object?>{},
      _remaining(stopwatch, deadline),
    );
    final isolateRefs = vm['isolates'];
    if (vm['type'] != 'VM' ||
        isolateRefs is! List<Object?> ||
        !isolateRefs.whereType<Map<String, Object?>>().any(
              (isolate) => isolate['id'] == fixtureIsolateId,
            )) {
      throw StateError('VM Service getVM did not expose the fixture isolate.');
    }
    scenarios.add('vm');

    await rpc.request(
      'streamListen',
      const <String, Object?>{'streamId': 'Extension'},
      _remaining(stopwatch, deadline),
    );
    await fixture.sendLine('event');
    final event = await rpc.nextNotification(
      'streamNotify',
      _remaining(stopwatch, deadline),
    );
    final eventParams = event['params'];
    final eventBody =
        eventParams is Map<String, Object?> ? eventParams['event'] : null;
    if (eventParams is! Map<String, Object?> ||
        eventParams['streamId'] != 'Extension' ||
        eventBody is! Map<String, Object?> ||
        eventBody['kind'] != 'Extension' ||
        eventBody['extensionKind'] != 'pigcode.matrix') {
      throw StateError('VM Service Extension stream event is malformed.');
    }
    await rpc.request(
      'streamCancel',
      const <String, Object?>{'streamId': 'Extension'},
      _remaining(stopwatch, deadline),
    );
    scenarios.add('stream');

    final isolate = await rpc.request(
      'getIsolate',
      <String, Object?>{'isolateId': fixtureIsolateId},
      _remaining(stopwatch, deadline),
    );
    final rootLib = isolate['rootLib'];
    if (isolate['type'] != 'Isolate' ||
        rootLib is! Map<String, Object?> ||
        rootLib['id'] is! String) {
      throw StateError('VM Service getIsolate response is malformed.');
    }
    scenarios.add('isolate');

    final object = await rpc.request(
      'getObject',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'objectId': fixtureObjectId,
      },
      _remaining(stopwatch, deadline),
    );
    if (object['type'] == 'Sentinel') {
      throw StateError('VM Service retained fixture object was unavailable.');
    }
    scenarios.add('object');

    final idZone = await rpc.request(
      'createIdZone',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'backingBufferKind': 'Ring',
        'idAssignmentPolicy': 'AlwaysAllocate',
        'capacity': 8,
      },
      _remaining(stopwatch, deadline),
    );
    final idZoneId = idZone['id'];
    if (idZone['type'] != 'IdZone' || idZoneId is! String) {
      throw StateError('VM Service did not create a temporary ID zone.');
    }
    final zonedObject = await rpc.request(
      'getObject',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'objectId': fixtureObjectId,
        'idZoneId': idZoneId,
      },
      _remaining(stopwatch, deadline),
    );
    final elements = zonedObject['elements'];
    final firstElement = elements is List<Object?> && elements.isNotEmpty
        ? elements.first
        : null;
    final temporaryObjectId =
        firstElement is Map<String, Object?> ? firstElement['id'] : null;
    if (temporaryObjectId is! String) {
      throw StateError(
        'VM Service ID zone did not allocate a nested Instance ID.',
      );
    }
    await rpc.request(
      'invalidateIdZone',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'idZoneId': idZoneId,
      },
      _remaining(stopwatch, deadline),
    );
    final sentinel = await rpc.request(
      'getObject',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'objectId': temporaryObjectId,
      },
      _remaining(stopwatch, deadline),
    );
    final sentinelKind = sentinel['kind'];
    if (sentinel['type'] != 'Sentinel' || sentinelKind != 'Expired') {
      throw StateError(
        'VM Service temporary ID did not expire after invalidation: $sentinel.',
      );
    }
    await rpc.request(
      'deleteIdZone',
      <String, Object?>{
        'isolateId': fixtureIsolateId,
        'idZoneId': idZoneId,
      },
      _remaining(stopwatch, deadline),
    );
    scenarios.add('temporaryIdExpired');

    await rpc.close(_remaining(stopwatch, deadline));
    rpc = null;
    scenarios.add('disconnect');
    await fixture.sendLine('shutdown');
    await fixture.closeStdin();
    final exit = await fixture.waitForExit(_remaining(stopwatch, deadline));
    if (exit != 0) {
      throw StateError('VM Service fixture exited with code $exit.');
    }
    scenarios.add('cleanup');
    completed = true;

    final identity = command.release == '3.6.0'
        ? vmServiceMinimumSourceIdentity
        : vmServiceCurrentSourceIdentity;
    final report = VmServicePeerReport(
      peer: command.peer,
      release: command.release,
      sdkRevision: identity.sourceRevision,
      wireVersion: wireVersion,
      transport: 'websocket-json-rpc',
      observedProtocols: List<String>.unmodifiable(observedProtocols),
      scenarios: List<String>.unmodifiable(scenarios),
      sentinelKind: sentinelKind as String,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    final violations = validateVmServicePeerReport(report);
    if (violations.isNotEmpty) {
      throw StateError(violations.join(' '));
    }
    return report;
  } finally {
    if (!completed) {
      if (rpc != null) {
        await rpc.close(const Duration(seconds: 3));
      }
      await fixture.terminate(const Duration(seconds: 5));
    }
  }
}

final class _JsonRpcSocket {
  _JsonRpcSocket._(this._socket, this._messages);

  static Future<_JsonRpcSocket> connect(Uri uri, Duration deadline) async {
    final socket = await WebSocket.connect(uri.toString()).timeout(deadline);
    return _JsonRpcSocket._(
      socket,
      StreamIterator<Map<String, Object?>>(
        socket.map((message) {
          if (message is! String) {
            throw StateError('VM Service WebSocket message must be text.');
          }
          final decoded = jsonDecode(message);
          if (decoded is! Map<String, Object?>) {
            throw StateError('VM Service message must be a JSON object.');
          }
          return decoded;
        }),
      ),
    );
  }

  final WebSocket _socket;
  final StreamIterator<Map<String, Object?>> _messages;
  int _nextId = 1;
  bool _closed = false;
  final List<Map<String, Object?>> _notifications = <Map<String, Object?>>[];

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params,
    Duration deadline,
  ) async {
    if (_closed) {
      throw StateError('VM Service WebSocket is closed.');
    }
    final id = '${_nextId++}';
    _socket.add(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final stopwatch = Stopwatch()..start();
    while (true) {
      final message = await _next(_remaining(stopwatch, deadline));
      if (message['id'] == id && message['method'] == null) {
        final error = message['error'];
        if (error != null) {
          throw StateError('VM Service $method returned $error.');
        }
        final result = message['result'];
        if (result is! Map<String, Object?>) {
          throw StateError('VM Service $method result is not an object.');
        }
        return result;
      }
      if (message['method'] is String) {
        _notifications.add(message);
        continue;
      }
      throw StateError('VM Service received an unexpected response.');
    }
  }

  Future<Map<String, Object?>> nextNotification(
    String method,
    Duration deadline,
  ) async {
    for (var index = 0; index < _notifications.length; index++) {
      if (_notifications[index]['method'] == method) {
        return _notifications.removeAt(index);
      }
    }
    final stopwatch = Stopwatch()..start();
    while (true) {
      final message = await _next(_remaining(stopwatch, deadline));
      if (message['method'] == method) {
        return message;
      }
      if (message['method'] is String) {
        _notifications.add(message);
        continue;
      }
      throw StateError('VM Service received an unexpected response.');
    }
  }

  Future<Map<String, Object?>> _next(Duration deadline) async {
    final available = await _messages.moveNext().timeout(deadline);
    if (!available) {
      throw StateError(
        'VM Service WebSocket closed unexpectedly '
        '(code=${_socket.closeCode}, reason=${_socket.closeReason}).',
      );
    }
    return _messages.current;
  }

  Future<void> close(Duration deadline) async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _socket.close().timeout(deadline);
    await _messages.cancel();
  }
}

final class _FixtureProcess {
  _FixtureProcess._(
    this._process,
    this._stdout,
    this._stderrDone,
    this._stderr,
  );

  static Future<_FixtureProcess> start(VmServicePeerCommand command) async {
    final process = await Process.start(
      command.dartExecutable,
      <String>[
        '--no-dds',
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        command.fixturePath,
      ],
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
    return _FixtureProcess._(
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

  final Process _process;
  final StreamIterator<String> _stdout;
  final Future<void> _stderrDone;
  final StringBuffer _stderr;
  bool _stdinClosed = false;
  bool _terminated = false;

  Future<Map<String, Object?>> nextMachineEvent(Duration deadline) async {
    final stopwatch = Stopwatch()..start();
    while (await _stdout.moveNext().timeout(_remaining(stopwatch, deadline))) {
      try {
        final decoded = jsonDecode(_stdout.current);
        if (decoded is Map<String, Object?>) {
          return decoded;
        }
      } on FormatException {
        // VM startup banners are ignored; only fixture JSON is authoritative.
      }
    }
    throw StateError(
      'VM Service fixture closed before a machine event. '
      'stderr=${_bounded(_stderr.toString())}',
    );
  }

  Future<void> sendLine(String line) async {
    if (_stdinClosed) {
      throw StateError('VM Service fixture stdin is closed.');
    }
    _process.stdin.writeln(line);
    await _process.stdin.flush();
  }

  Future<void> closeStdin() async {
    if (_stdinClosed) {
      return;
    }
    _stdinClosed = true;
    await _process.stdin.close();
  }

  Future<int> waitForExit(Duration deadline) async {
    final exit = await _process.exitCode.timeout(deadline);
    await _stderrDone.timeout(deadline);
    await _stdout.cancel();
    _terminated = true;
    return exit;
  }

  Future<void> terminate(Duration deadline) async {
    if (_terminated) {
      return;
    }
    await closeStdin();
    if (await _isRunning) {
      _process.kill(ProcessSignal.sigterm);
      try {
        await _process.exitCode.timeout(deadline);
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode.timeout(deadline);
      }
    }
    await _stderrDone.timeout(deadline);
    await _stdout.cancel();
    _terminated = true;
  }

  Future<bool> get _isRunning async {
    try {
      await _process.exitCode.timeout(Duration.zero);
      return false;
    } on TimeoutException {
      return true;
    }
  }
}

Duration _remaining(Stopwatch stopwatch, Duration deadline) {
  final remaining = deadline - stopwatch.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('VM Service peer exceeded its row deadline.');
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
