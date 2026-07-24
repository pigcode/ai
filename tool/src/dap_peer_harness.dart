import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'tooling_process_harness.dart';

abstract interface class DapPeerTransport {
  Future<void> send(JsonObject envelope);
  Future<JsonObject> next(Duration deadline);
  Future<int> close(Duration deadline);
  Future<void> terminate(Duration deadline);
  String get diagnostics;
}

final class DapStdioPeerTransport implements DapPeerTransport {
  DapStdioPeerTransport._(this._process);

  static Future<DapStdioPeerTransport> start(
    ToolingProcessCommand command,
  ) async =>
      DapStdioPeerTransport._(
        await ToolingProcessHarness.start(command),
      );

  final ToolingProcessHarness _process;

  @override
  String get diagnostics => _process.boundedStderr;

  @override
  Future<void> send(JsonObject envelope) => _process.send(envelope);

  @override
  Future<JsonObject> next(Duration deadline) => _process.next(deadline);

  @override
  Future<int> close(Duration deadline) => _process.close(deadline);

  @override
  Future<void> terminate(Duration deadline) => _process.terminate(deadline);
}

final class DapSocketPeerTransport implements DapPeerTransport {
  DapSocketPeerTransport._({
    required Process server,
    required Socket socket,
    required StreamIterator<JsonObject> messages,
    required StringBuffer stderr,
    required String host,
    required int port,
    required bool ownsServer,
  })  : _server = server,
        _socket = socket,
        _messages = messages,
        _stderr = stderr,
        _host = host,
        _port = port,
        _ownsServer = ownsServer;

  static Future<DapSocketPeerTransport> connect({
    required Process server,
    required int port,
    String host = '127.0.0.1',
  }) async {
    final stderr = StringBuffer();
    server.stderr.transform(utf8.decoder).listen((chunk) {
      if (stderr.length < 64 * 1024) {
        stderr.write(chunk);
      }
    });
    final socket = await Socket.connect(host, port);
    return DapSocketPeerTransport._(
      server: server,
      socket: socket,
      messages: StreamIterator<JsonObject>(
        socket.transform(_DapContentLengthJsonDecoder()),
      ),
      stderr: stderr,
      host: host,
      port: port,
      ownsServer: true,
    );
  }

  final Process _server;
  final Socket _socket;
  final StreamIterator<JsonObject> _messages;
  final StringBuffer _stderr;
  final String _host;
  final int _port;
  final bool _ownsServer;
  bool _closed = false;

  Future<DapSocketPeerTransport> openSibling() async {
    final socket = await Socket.connect(_host, _port);
    return DapSocketPeerTransport._(
      server: _server,
      socket: socket,
      messages: StreamIterator<JsonObject>(
        socket.transform(_DapContentLengthJsonDecoder()),
      ),
      stderr: _stderr,
      host: _host,
      port: _port,
      ownsServer: false,
    );
  }

  @override
  String get diagnostics => _stderr.toString();

  @override
  Future<void> send(JsonObject envelope) async {
    if (_closed) {
      throw StateError('DAP socket is closed.');
    }
    final body = utf8.encode(jsonEncode(envelope));
    _socket.add(<int>[
      ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
      ...body,
    ]);
    await _socket.flush();
  }

  @override
  Future<JsonObject> next(Duration deadline) async {
    final available = await _messages.moveNext().timeout(deadline);
    if (!available) {
      throw StateError('DAP socket closed: $diagnostics');
    }
    return _messages.current;
  }

  @override
  Future<int> close(Duration deadline) async {
    if (!_closed) {
      _closed = true;
      await _socket.close();
    }
    if (!_ownsServer) {
      await _messages.cancel();
      return 0;
    }
    var terminatedServer = false;
    if (_ownsServer && await _isRunning(_server)) {
      terminatedServer = true;
      _server.kill();
    }
    final code = await _server.exitCode.timeout(deadline);
    await _messages.cancel();
    return terminatedServer ? 0 : code;
  }

  @override
  Future<void> terminate(Duration deadline) async {
    if (!_closed) {
      _closed = true;
      await _socket.close();
    }
    if (_ownsServer && await _isRunning(_server)) {
      _server.kill();
      await _server.exitCode.timeout(deadline);
    }
    await _messages.cancel();
  }
}

final class DapPeerCommand {
  const DapPeerCommand({
    required this.peer,
    required this.family,
    required this.release,
    required this.transportName,
    required this.transport,
    required this.launchArguments,
    required this.sourcePath,
    required this.breakpointLine,
    this.supportsStartDebugging = false,
  });

  final String peer;
  final String family;
  final String release;
  final String transportName;
  final DapPeerTransport transport;
  final JsonObject launchArguments;
  final String sourcePath;
  final int breakpointLine;
  final bool supportsStartDebugging;
}

final class DapPeerReport {
  const DapPeerReport({
    required this.peer,
    required this.family,
    required this.release,
    required this.transport,
    required this.capabilities,
    required this.scenarios,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final String family;
  final String release;
  final String transport;
  final Map<String, Object?> capabilities;
  final List<String> scenarios;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'family': family,
        'release': release,
        'transport': transport,
        'capabilities': capabilities,
        'scenarios': scenarios,
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

List<String> validateDapPeerReport(DapPeerReport report) {
  final violations = <String>[];
  if (report.peer.isEmpty || report.family.isEmpty || report.release.isEmpty) {
    violations.add('DAP peer identity is incomplete.');
  }
  if (!const <String>{
    'stdio-content-length',
    'tcp-content-length',
  }.contains(report.transport)) {
    violations.add('DAP peer transport is unsupported.');
  }
  if (report.capabilities.isEmpty) {
    violations.add('DAP peer capabilities are empty.');
  }
  for (final required in const <String>[
    'initialize',
    'launch',
    'breakpoint',
    'stopped',
    'stack',
    'continue',
    'disconnect',
  ]) {
    if (!report.scenarios.contains(required)) {
      violations.add('DAP peer scenario is missing: $required.');
    }
  }
  if (report.elapsedMilliseconds < 0) {
    violations.add('DAP peer duration is invalid.');
  }
  return List<String>.unmodifiable(violations);
}

Future<DapPeerReport> runDapPeer(
  DapPeerCommand command, {
  Duration deadline = const Duration(seconds: 90),
}) async {
  final stopwatch = Stopwatch()..start();
  _DapChildSession? childSession;
  Future<void> startDebugging(JsonObject request) async {
    final transport = command.transport;
    if (!command.supportsStartDebugging ||
        transport is! DapSocketPeerTransport) {
      throw UnsupportedError('startDebugging is not supported.');
    }
    childSession = await _startChildSession(
      parent: transport,
      peer: command.peer,
      request: request,
      deadline: deadline,
    );
  }

  final inbox = _DapInbox(
    command.transport,
    command.peer,
    onStartDebugging: startDebugging,
  );
  final scenarios = <String>[];
  var completed = false;
  void stage(String value) {
    stderr.writeln(
      '[dap-peer ${command.peer}] '
      '${stopwatch.elapsedMilliseconds}ms $value',
    );
  }

  try {
    stage('initialize');
    final initialize = await inbox.request(
      seq: 1,
      command: 'initialize',
      arguments: _initializeArguments(
        supportsStartDebugging: command.supportsStartDebugging,
      ),
      deadline: deadline,
    );
    final capabilities = freezeJsonObject(
      initialize['body'] as JsonObject? ?? const <String, Object?>{},
    );
    scenarios.add('initialize');

    stage('launch');
    await command.transport.send(<String, Object?>{
      'seq': 2,
      'type': 'request',
      'command': 'launch',
      'arguments': command.launchArguments,
    });
    await inbox.event('initialized', deadline: deadline);

    stage('setBreakpoints');
    final breakpoints = await inbox.request(
      seq: 3,
      command: 'setBreakpoints',
      arguments: <String, Object?>{
        'source': <String, Object?>{'path': command.sourcePath},
        'breakpoints': <Object?>[
          <String, Object?>{'line': command.breakpointLine},
        ],
        'sourceModified': false,
      },
      deadline: deadline,
    );
    final breakpointBody = breakpoints['body'];
    if (breakpointBody is! JsonObject) {
      throw StateError('DAP peer returned no breakpoint body.');
    }
    stage('breakpoint response ${jsonEncode(breakpointBody)}');
    scenarios.add('breakpoint');

    if (capabilities['supportsConfigurationDoneRequest'] == true) {
      stage('configurationDone');
      await inbox.request(
        seq: 4,
        command: 'configurationDone',
        arguments: const <String, Object?>{},
        deadline: deadline,
      );
    }
    await inbox.response(
      requestSeq: 2,
      command: 'launch',
      deadline: deadline,
    );
    scenarios.add('launch');

    if (command.supportsStartDebugging) {
      await inbox.waitForStartDebugging(deadline);
      if (childSession == null) {
        throw StateError('startDebugging did not create a child session.');
      }
    }
    final debugInbox = childSession?.inbox ?? inbox;
    stage(childSession == null ? 'stopped' : 'child stopped');
    var stopped = await debugInbox.event(
      'stopped',
      deadline: deadline,
      where: command.supportsStartDebugging
          ? null
          : (event) =>
              (event['body'] as JsonObject?)?['reason'] == 'breakpoint',
    );
    var stoppedBody = stopped['body']! as JsonObject;
    var nextSequence = 5;
    if (command.supportsStartDebugging && stoppedBody['reason'] == 'entry') {
      final entryThreadId = (stoppedBody['threadId'] as int?) ?? 1;
      stage('bind child breakpoint');
      final childBreakpoints = await debugInbox.request(
        seq: nextSequence++,
        command: 'setBreakpoints',
        arguments: <String, Object?>{
          'source': <String, Object?>{'path': command.sourcePath},
          'breakpoints': <Object?>[
            <String, Object?>{'line': command.breakpointLine},
          ],
          'sourceModified': false,
        },
        deadline: deadline,
      );
      stage(
        'child breakpoint response '
        '${jsonEncode(childBreakpoints['body'])}',
      );
      stage('continue from entry to breakpoint');
      await debugInbox.request(
        seq: nextSequence++,
        command: 'continue',
        arguments: <String, Object?>{'threadId': entryThreadId},
        deadline: deadline,
      );
      stopped = await debugInbox.event(
        'stopped',
        deadline: deadline,
        where: (event) =>
            (event['body'] as JsonObject?)?['reason'] == 'breakpoint',
      );
      stoppedBody = stopped['body']! as JsonObject;
    }
    if (command.supportsStartDebugging &&
        stoppedBody['reason'] != 'breakpoint') {
      throw StateError(
        'DAP peer stopped for ${stoppedBody['reason']}, not a breakpoint.',
      );
    }
    final threadId = (stoppedBody['threadId'] as int?) ?? 1;
    scenarios.add('stopped');

    stage('stack and variables');
    await debugInbox.request(
      seq: nextSequence++,
      command: 'threads',
      arguments: const <String, Object?>{},
      deadline: deadline,
    );
    final stack = await debugInbox.request(
      seq: nextSequence++,
      command: 'stackTrace',
      arguments: <String, Object?>{
        'threadId': threadId,
        'startFrame': 0,
        'levels': 1,
      },
      deadline: deadline,
    );
    final frames =
        ((stack['body']! as JsonObject)['stackFrames']! as List<Object?>);
    if (frames.isEmpty) {
      throw StateError('DAP peer returned no stack frames.');
    }
    final frameId = (frames.first! as JsonObject)['id']! as int;
    final scopes = await debugInbox.request(
      seq: nextSequence++,
      command: 'scopes',
      arguments: <String, Object?>{'frameId': frameId},
      deadline: deadline,
    );
    final scopeValues =
        ((scopes['body']! as JsonObject)['scopes']! as List<Object?>);
    if (scopeValues.isNotEmpty) {
      final variablesReference =
          (scopeValues.first! as JsonObject)['variablesReference']! as int;
      if (variablesReference > 0) {
        await debugInbox.request(
          seq: nextSequence++,
          command: 'variables',
          arguments: <String, Object?>{
            'variablesReference': variablesReference,
          },
          deadline: deadline,
        );
      }
    }
    scenarios.add('stack');

    stage('continue');
    await debugInbox.request(
      seq: nextSequence++,
      command: 'continue',
      arguments: <String, Object?>{'threadId': threadId},
      deadline: deadline,
    );
    scenarios.add('continue');
    stage('terminated');
    await debugInbox.event('terminated', deadline: deadline);

    if (childSession case final _DapChildSession child) {
      stage('child disconnect');
      await child.inbox.request(
        seq: nextSequence++,
        command: 'disconnect',
        arguments: const <String, Object?>{},
        deadline: deadline,
      );
      await child.transport.close(deadline);
      childSession = null;
    }
    stage('disconnect');
    await inbox.request(
      seq: 10,
      command: 'disconnect',
      arguments: const <String, Object?>{},
      deadline: deadline,
    );
    scenarios.add('disconnect');
    stage('close');
    final exitCode = await command.transport.close(deadline);
    completed = true;
    if (exitCode != 0) {
      throw StateError(
        'DAP peer exited with $exitCode: ${command.transport.diagnostics}',
      );
    }
    final report = DapPeerReport(
      peer: command.peer,
      family: command.family,
      release: command.release,
      transport: command.transportName,
      capabilities: capabilities,
      scenarios: List<String>.unmodifiable(scenarios),
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    final violations = validateDapPeerReport(report);
    if (violations.isNotEmpty) {
      throw StateError(violations.join(' '));
    }
    return report;
  } finally {
    if (childSession case final _DapChildSession child) {
      await child.transport.terminate(deadline);
    }
    if (!completed) {
      await command.transport.terminate(deadline);
    }
  }
}

JsonObject _initializeArguments({
  required bool supportsStartDebugging,
}) =>
    <String, Object?>{
      'clientID': 'pigcode',
      'clientName': 'Pigcode',
      'adapterID': 'pigcode',
      'pathFormat': 'path',
      'linesStartAt1': true,
      'columnsStartAt1': true,
      'supportsRunInTerminalRequest': false,
      'supportsStartDebuggingRequest': supportsStartDebugging,
      'supportsProgressReporting': true,
    };

final class _DapChildSession {
  const _DapChildSession({
    required this.transport,
    required this.inbox,
  });

  final DapSocketPeerTransport transport;
  final _DapInbox inbox;
}

Future<_DapChildSession> _startChildSession({
  required DapSocketPeerTransport parent,
  required String peer,
  required JsonObject request,
  required Duration deadline,
}) async {
  final arguments = request['arguments'];
  if (arguments is! JsonObject || arguments['configuration'] is! JsonObject) {
    throw StateError('startDebugging omitted its configuration.');
  }
  final requestName = arguments['request'] as String? ?? 'launch';
  final child = await parent.openSibling();
  final inbox = _DapInbox(child, '$peer/child');
  try {
    final initialize = await inbox.request(
      seq: 1,
      command: 'initialize',
      arguments: _initializeArguments(supportsStartDebugging: false),
      deadline: deadline,
    );
    final capabilities =
        initialize['body'] as JsonObject? ?? const <String, Object?>{};
    await child.send(<String, Object?>{
      'seq': 2,
      'type': 'request',
      'command': requestName,
      'arguments': arguments['configuration'],
    });
    await inbox.event('initialized', deadline: deadline);
    if (capabilities['supportsConfigurationDoneRequest'] == true) {
      await inbox.request(
        seq: 3,
        command: 'configurationDone',
        arguments: const <String, Object?>{},
        deadline: deadline,
      );
    }
    await inbox.response(
      requestSeq: 2,
      command: requestName,
      deadline: deadline,
    );
    return _DapChildSession(transport: child, inbox: inbox);
  } on Object {
    await child.terminate(deadline);
    rethrow;
  }
}

final class _DapInbox {
  _DapInbox(
    this.transport,
    this.peer, {
    this.onStartDebugging,
  });

  final DapPeerTransport transport;
  final String peer;
  final Future<void> Function(JsonObject request)? onStartDebugging;
  final List<JsonObject> _events = <JsonObject>[];
  final List<JsonObject> _responses = <JsonObject>[];
  bool _startDebuggingHandled = false;

  Future<JsonObject> request({
    required int seq,
    required String command,
    required JsonObject arguments,
    required Duration deadline,
  }) async {
    await transport.send(<String, Object?>{
      'seq': seq,
      'type': 'request',
      'command': command,
      'arguments': arguments,
    });
    return response(
      requestSeq: seq,
      command: command,
      deadline: deadline,
    );
  }

  Future<JsonObject> response({
    required int requestSeq,
    required String command,
    required Duration deadline,
  }) async {
    final queuedIndex = _responses.indexWhere(
      (response) => response['request_seq'] == requestSeq,
    );
    if (queuedIndex >= 0) {
      return _validateResponse(
        _responses.removeAt(queuedIndex),
        command,
      );
    }
    while (true) {
      final envelope = await transport.next(deadline);
      _trace(envelope);
      switch (envelope['type']) {
        case 'event':
          _events.add(envelope);
        case 'request':
          await _rejectReverseRequest(envelope);
        case 'response':
          if (envelope['request_seq'] == requestSeq) {
            return _validateResponse(envelope, command);
          }
          _responses.add(envelope);
        default:
          throw StateError('Unknown DAP peer message type.');
      }
    }
  }

  Future<JsonObject> event(
    String event, {
    required Duration deadline,
    bool Function(JsonObject envelope)? where,
  }) async {
    final queuedIndex = _events.indexWhere(
      (envelope) =>
          envelope['event'] == event && (where == null || where(envelope)),
    );
    if (queuedIndex >= 0) {
      return _validateEvent(_events.removeAt(queuedIndex));
    }
    while (true) {
      final envelope = await transport.next(deadline);
      _trace(envelope);
      switch (envelope['type']) {
        case 'event':
          if (envelope['event'] == event &&
              (where == null || where(envelope))) {
            return _validateEvent(envelope);
          }
          _events.add(envelope);
        case 'request':
          await _rejectReverseRequest(envelope);
        case 'response':
          _responses.add(envelope);
        default:
          throw StateError('Unknown DAP peer message type.');
      }
    }
  }

  Future<void> waitForStartDebugging(Duration deadline) async {
    while (!_startDebuggingHandled) {
      final envelope = await transport.next(deadline);
      _trace(envelope);
      switch (envelope['type']) {
        case 'event':
          _events.add(envelope);
        case 'request':
          await _rejectReverseRequest(envelope);
        case 'response':
          _responses.add(envelope);
        default:
          throw StateError('Unknown DAP peer message type.');
      }
    }
  }

  JsonObject _validateResponse(JsonObject envelope, String command) {
    late final DapDecodedMessage decoded;
    try {
      decoded = DapCodec.instance.decode(
        jsonEncode(envelope),
        requestCommand: command,
      );
    } on Object {
      stderr.writeln(
        '[dap-peer $peer] invalid $command response: '
        '${jsonEncode(envelope)}',
      );
      rethrow;
    }
    if (envelope['success'] != true) {
      throw StateError(
        'DAP $command failed: ${envelope['message']}',
      );
    }
    return decoded.toJson();
  }

  JsonObject _validateEvent(JsonObject envelope) =>
      DapCodec.instance.decode(jsonEncode(envelope)).toJson();

  Future<void> _rejectReverseRequest(JsonObject request) async {
    final handler =
        request['command'] == 'startDebugging' ? onStartDebugging : null;
    if (handler == null) {
      await transport.send(<String, Object?>{
        'seq': 100000 + (request['seq']! as int),
        'type': 'response',
        'request_seq': request['seq'],
        'success': false,
        'command': request['command'],
        'message': '${request['command']} is unsupported.',
      });
      return;
    }
    try {
      await handler(request);
      await transport.send(<String, Object?>{
        'seq': 100000 + (request['seq']! as int),
        'type': 'response',
        'request_seq': request['seq'],
        'success': true,
        'command': request['command'],
      });
      _startDebuggingHandled = true;
    } on Object catch (error) {
      await transport.send(<String, Object?>{
        'seq': 100000 + (request['seq']! as int),
        'type': 'response',
        'request_seq': request['seq'],
        'success': false,
        'command': request['command'],
        'message': '$error',
      });
      rethrow;
    }
  }

  void _trace(JsonObject envelope) {
    final type = envelope['type'];
    if (type == 'event' && envelope['event'] == 'loadedSource') {
      return;
    }
    final name = switch (type) {
      'event' => envelope['event'],
      'request' => envelope['command'],
      'response' => envelope['command'],
      _ => 'unknown',
    };
    final success = type == 'response' ? ' success=${envelope['success']}' : '';
    stderr.writeln('[dap-peer $peer] recv $type $name$success');
  }
}

final class _DapContentLengthJsonDecoder
    extends StreamTransformerBase<Uint8List, JsonObject> {
  @override
  Stream<JsonObject> bind(Stream<Uint8List> stream) async* {
    final framer = ContentLengthFramer();
    await for (final chunk in stream) {
      for (final frame in framer.add(chunk)) {
        yield jsonDecode(utf8.decode(frame)) as JsonObject;
      }
    }
    framer.close();
  }
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
}
