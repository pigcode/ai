import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _peerPath = 'tool/fixtures/ai_core_peer.dart';
const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);

Future<void> main() async {
  final expectedHash = _sourceBlobHash();
  final stopwatch = Stopwatch()..start();
  final session = await _PeerSession.start();
  try {
    _expect(
      stopwatch.elapsed < _deadline,
      'Peer missed the five-second startup deadline.',
    );
    _expect(session.ready['type'] == 'ready', 'Missing ready handshake.');
    _expect(
      session.ready['version'] == _peerVersion,
      'Unexpected peer version: ${session.ready['version']}',
    );
    _expect(
      session.ready['sourceBlobHash'] == expectedHash,
      'Peer source blob hash did not fail closed.',
    );
    _expect(
      session.ready['host'] == InternetAddress.loopbackIPv4.address,
      'Peer must bind only to IPv4 loopback.',
    );
    final transports =
        (session.ready['transports'] as List<Object?>).cast<String>().toSet();
    _expect(
      transports.containsAll(const <String>{
        'jsonl-stdio',
        'loopback-http',
        'loopback-sse',
        'loopback-websocket',
      }),
      'Handshake did not advertise all fixed transports.',
    );

    final echo = await session.request(<String, Object?>{
      'id': 'stdio-echo',
      'op': 'echo',
      'value': <String, Object?>{'message': 'hello'},
    });
    _expect(echo['ok'] == true, 'JSONL echo failed: $echo');
    _expect(
      (echo['value'] as Map<String, Object?>)['message'] == 'hello',
      'JSONL echo changed the scripted value.',
    );

    final rejected = await session.request(<String, Object?>{
      'id': 'credential',
      'op': 'echo',
      'value': <String, Object?>{'apiKey': 'not-a-real-key'},
    });
    _expect(
      rejected['error'] == 'credential_input_rejected' &&
          !jsonEncode(rejected).contains('not-a-real-key'),
      'Credential-like JSONL input was not rejected safely.',
    );

    final baseUri = Uri(
      scheme: 'http',
      host: session.ready['host'] as String,
      port: session.ready['port'] as int,
    );
    await _verifyHttp(baseUri);
    await _verifySse(baseUri);
    await _verifyWebSocket(baseUri);

    final shutdown = await session.request(<String, Object?>{
      'id': 'shutdown',
      'op': 'shutdown',
    });
    _expect(
      shutdown['ok'] == true && shutdown['shutdown'] == true,
      'Peer did not acknowledge deterministic shutdown.',
    );
    final exitCode = await session.process.exitCode.timeout(_deadline);
    final diagnostics = await session.stderrOutput;
    _expect(exitCode == 0, 'Peer exited with $exitCode: $diagnostics');
    _expect(
      diagnostics.trim().isEmpty,
      'Peer emitted unexpected diagnostics: $diagnostics',
    );
    stdout.writeln('PASS AI Core peer handshake and transports');
  } on Object catch (error, stackTrace) {
    stderr.writeln('FAIL AI Core peer handshake and transports: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await session.dispose();
  }
}

Future<void> _verifyHttp(Uri baseUri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.postUrl(
      baseUri
          .replace(path: '/echo', queryParameters: <String, String>{'q': '1'}),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'scenario': 'http',
        'value': <String, Object?>{'answer': 42},
      }),
    );
    final response = await request.close().timeout(_deadline);
    final decoded = jsonDecode(
      await utf8.decoder.bind(response).join().timeout(_deadline),
    ) as Map<String, Object?>;
    _expect(
        response.statusCode == HttpStatus.ok, 'HTTP echo did not return 200.');
    _expect(decoded['method'] == 'POST', 'HTTP method was not preserved.');
    _expect(decoded['path'] == '/echo', 'HTTP path was not preserved.');
    _expect(
      (decoded['query'] as Map<String, Object?>)['q'] == '1',
      'HTTP query was not preserved.',
    );
    final body = decoded['body'] as Map<String, Object?>;
    _expect(
      (body['value'] as Map<String, Object?>)['answer'] == 42,
      'HTTP JSON body was not preserved.',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _verifySse(Uri baseUri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.postUrl(baseUri.replace(path: '/sse'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'events': <Object?>[
          <String, Object?>{'type': 'start'},
          <String, Object?>{'type': 'delta', 'text': 'hello'},
          <String, Object?>{'type': 'finish'},
        ],
      }),
    );
    final response = await request.close().timeout(_deadline);
    final body = await utf8.decoder.bind(response).join().timeout(_deadline);
    _expect(
      response.headers.contentType?.mimeType == 'text/event-stream',
      'SSE response content type is wrong.',
    );
    final dataLines = const LineSplitter()
        .convert(body)
        .where((line) => line.startsWith('data: '))
        .map((line) => jsonDecode(line.substring(6)) as Map<String, Object?>)
        .toList();
    _expect(
      dataLines.map((event) => event['type']).join(',') == 'start,delta,finish',
      'SSE event order changed: $dataLines',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _verifyWebSocket(Uri baseUri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  final socket = await WebSocket.connect(
    baseUri.replace(scheme: 'ws', path: '/ws').toString(),
    customClient: client,
  ).timeout(_deadline);
  final iterator = StreamIterator<Object?>(socket);
  try {
    socket.add(
      jsonEncode(<String, Object?>{
        'scenario': 'websocket',
        'value': 'hello',
      }),
    );
    _expect(
      await iterator.moveNext().timeout(_deadline),
      'WebSocket closed before its scripted response.',
    );
    final decoded =
        jsonDecode(iterator.current as String) as Map<String, Object?>;
    _expect(decoded['ok'] == true, 'WebSocket echo failed: $decoded');
    final value = decoded['value'] as Map<String, Object?>;
    _expect(value['value'] == 'hello', 'WebSocket payload changed.');
  } finally {
    await socket.close(WebSocketStatus.normalClosure, 'test complete');
    await iterator.cancel();
    client.close(force: true);
  }
}

String _sourceBlobHash() {
  final result = Process.runSync(
    'git',
    const <String>['hash-object', '--', _peerPath],
  );
  _expect(
    result.exitCode == 0,
    'Unable to hash peer source: ${result.stderr}',
  );
  final hash = (result.stdout as String).trim();
  _expect(
    RegExp(r'^[a-f0-9]{40}$').hasMatch(hash),
    'Invalid peer source blob hash: $hash',
  );
  return hash;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _PeerSession {
  _PeerSession._(
    this.process,
    this.lines,
    this.ready,
    this.stderrOutput,
  );

  final Process process;
  final StreamIterator<String> lines;
  final Map<String, Object?> ready;
  final Future<String> stderrOutput;

  static Future<_PeerSession> start() async {
    final environment = <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };
    final process = await Process.start(
      Platform.resolvedExecutable,
      const <String>[_peerPath],
      workingDirectory: Directory.current.absolute.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    try {
      final hasReady = await lines.moveNext().timeout(_deadline);
      _expect(hasReady, 'Peer exited before its ready handshake.');
      final ready = jsonDecode(lines.current) as Map<String, Object?>;
      return _PeerSession._(process, lines, ready, stderrOutput);
    } on Object {
      process.kill();
      await process.exitCode;
      rethrow;
    }
  }

  Future<Map<String, Object?>> request(Map<String, Object?> request) async {
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();
    final hasResponse = await lines.moveNext().timeout(_deadline);
    _expect(hasResponse, 'Peer stdout closed while awaiting ${request['id']}.');
    return jsonDecode(lines.current) as Map<String, Object?>;
  }

  Future<void> dispose() async {
    await lines.cancel();
    if (await _isRunning(process)) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
    }
  }
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 1));
    return false;
  } on TimeoutException {
    return true;
  }
}
