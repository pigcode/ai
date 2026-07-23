import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _version = 'phase1-ai-core-peer-v1';
const _credentialKeyFragments = <String>{
  'apikey',
  'api_key',
  'authorization',
  'cookie',
  'credential',
  'password',
  'privatekey',
  'private_key',
  'proxy-authorization',
  'secret',
  'token',
};

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The AI Core peer does not accept command-line input.');
    exitCode = 64;
    return;
  }
  if (_credentialEnvironmentKeys().isNotEmpty) {
    stderr.writeln(
      'Credential-like environment variables are not allowed: '
      '${_credentialEnvironmentKeys().join(', ')}',
    );
    exitCode = 65;
    return;
  }

  final sourceBlobHash = _readSourceBlobHash();
  if (sourceBlobHash == null) {
    exitCode = 66;
    return;
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>{};
  final serverDone = Completer<void>();
  unawaited(
    _serveHttp(server, sockets).whenComplete(() {
      if (!serverDone.isCompleted) {
        serverDone.complete();
      }
    }),
  );

  _writeJsonLine(<String, Object?>{
    'type': 'ready',
    'version': _version,
    'sourceBlobHash': sourceBlobHash,
    'host': InternetAddress.loopbackIPv4.address,
    'port': server.port,
    'transports': const <String>[
      'jsonl-stdio',
      'loopback-http',
      'loopback-sse',
      'loopback-websocket',
    ],
  });

  var shutdownRequested = false;
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) {
        continue;
      }
      final shouldShutdown = await _handleStdioLine(line, server, sockets);
      if (shouldShutdown) {
        shutdownRequested = true;
        break;
      }
    }
  } finally {
    for (final socket in sockets.toList()) {
      await socket.close(WebSocketStatus.goingAway, 'peer shutdown');
    }
    await server.close(force: true);
    if (!serverDone.isCompleted) {
      await serverDone.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
  }

  if (!shutdownRequested) {
    stderr.writeln('Peer input closed without a shutdown command.');
    exitCode = 67;
  }
}

Future<bool> _handleStdioLine(
  String line,
  HttpServer server,
  Set<WebSocket> sockets,
) async {
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    _writeJsonLine(<String, Object?>{
      'id': null,
      'ok': false,
      'error': 'invalid_json',
    });
    return false;
  }
  if (decoded is! Map<String, Object?>) {
    _writeJsonLine(<String, Object?>{
      'id': null,
      'ok': false,
      'error': 'invalid_request',
    });
    return false;
  }

  final id = decoded['id'];
  if (_containsCredentialInput(decoded)) {
    _writeJsonLine(<String, Object?>{
      'id': id,
      'ok': false,
      'error': 'credential_input_rejected',
    });
    return false;
  }
  switch (decoded['op']) {
    case 'echo':
      _writeJsonLine(<String, Object?>{
        'id': id,
        'ok': true,
        'value': decoded['value'],
      });
    case 'serverInfo':
      _writeJsonLine(<String, Object?>{
        'id': id,
        'ok': true,
        'host': InternetAddress.loopbackIPv4.address,
        'port': server.port,
        'openWebSockets': sockets.length,
      });
    case 'shutdown':
      _writeJsonLine(<String, Object?>{
        'id': id,
        'ok': true,
        'shutdown': true,
      });
      return true;
    default:
      _writeJsonLine(<String, Object?>{
        'id': id,
        'ok': false,
        'error': 'unknown_operation',
      });
  }
  return false;
}

Future<void> _serveHttp(
  HttpServer server,
  Set<WebSocket> sockets,
) async {
  await for (final request in server) {
    unawaited(_handleHttpRequest(request, sockets));
  }
}

Future<void> _handleHttpRequest(
  HttpRequest request,
  Set<WebSocket> sockets,
) async {
  try {
    switch (request.uri.path) {
      case '/health':
        await _writeJsonResponse(request.response, <String, Object?>{
          'ok': true,
          'version': _version,
        });
      case '/echo':
        final body = await utf8.decoder.bind(request).join();
        Object? decodedBody;
        if (body.isNotEmpty) {
          try {
            decodedBody = jsonDecode(body);
          } on FormatException {
            await _writeJsonResponse(
              request.response,
              const <String, Object?>{
                'ok': false,
                'error': 'invalid_json',
              },
              statusCode: HttpStatus.badRequest,
            );
            return;
          }
        }
        if (_containsCredentialInput(decodedBody)) {
          await _writeJsonResponse(
            request.response,
            const <String, Object?>{
              'ok': false,
              'error': 'credential_input_rejected',
            },
            statusCode: HttpStatus.badRequest,
          );
          return;
        }
        final headerNames = <String>[];
        request.headers.forEach((name, _) => headerNames.add(name));
        headerNames.sort();
        await _writeJsonResponse(request.response, <String, Object?>{
          'ok': true,
          'method': request.method,
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'body': decodedBody,
          'headerNames': headerNames,
        });
      case '/sse':
        final body = await utf8.decoder.bind(request).join();
        Object? decoded;
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('invalid_json');
          await request.response.close();
          return;
        }
        if (decoded is! Map<String, Object?> ||
            decoded['events'] is! List<Object?> ||
            _containsCredentialInput(decoded)) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('invalid_sse_script');
          await request.response.close();
          return;
        }
        request.response.headers
          ..contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          )
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        for (final event in decoded['events'] as List<Object?>) {
          request.response.write('data: ${jsonEncode(event)}\n\n');
          await request.response.flush();
        }
        await request.response.close();
      case '/ws':
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response
            ..statusCode = HttpStatus.upgradeRequired
            ..write('websocket upgrade required');
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen(
          (message) {
            Object? decoded;
            try {
              decoded = jsonDecode(message as String);
            } on Object {
              socket.add(
                jsonEncode(const <String, Object?>{
                  'ok': false,
                  'error': 'invalid_json',
                }),
              );
              return;
            }
            if (_containsCredentialInput(decoded)) {
              socket.add(
                jsonEncode(const <String, Object?>{
                  'ok': false,
                  'error': 'credential_input_rejected',
                }),
              );
              return;
            }
            socket.add(jsonEncode(<String, Object?>{
              'ok': true,
              'value': decoded,
            }));
          },
          onDone: () => sockets.remove(socket),
          onError: (_) => sockets.remove(socket),
          cancelOnError: true,
        );
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  } on Object catch (error) {
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('peer_error: ${error.runtimeType}');
      await request.response.close();
    } on StateError {
      // The response was already committed or closed by the scripted path.
    }
  }
}

Future<void> _writeJsonResponse(
  HttpResponse response,
  Map<String, Object?> body, {
  int statusCode = HttpStatus.ok,
}) async {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await response.close();
}

void _writeJsonLine(Map<String, Object?> value) {
  stdout.writeln(jsonEncode(value));
}

String? _readSourceBlobHash() {
  final sourcePath = Platform.script.toFilePath();
  final result = Process.runSync(
    'git',
    <String>['hash-object', '--', sourcePath],
  );
  if (result.exitCode != 0) {
    stderr.writeln('Unable to hash peer source with git hash-object.');
    final details = (result.stderr as String).trim();
    if (details.isNotEmpty) {
      stderr.writeln(details);
    }
    return null;
  }
  final hash = (result.stdout as String).trim();
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(hash)) {
    stderr.writeln('git hash-object returned an invalid source blob hash.');
    return null;
  }
  return hash;
}

List<String> _credentialEnvironmentKeys() {
  final keys = Platform.environment.keys
      .where((key) => _isCredentialKey(key))
      .toList()
    ..sort();
  return keys;
}

bool _containsCredentialInput(Object? value) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      if (entry.key is String && _isCredentialKey(entry.key as String)) {
        return true;
      }
      if (_containsCredentialInput(entry.value)) {
        return true;
      }
    }
  } else if (value is List<Object?>) {
    return value.any(_containsCredentialInput);
  }
  return false;
}

bool _isCredentialKey(String key) {
  final normalized = key.toLowerCase().replaceAll('-', '_');
  return _credentialKeyFragments.any(
    (fragment) => normalized.contains(fragment.replaceAll('-', '_')),
  );
}
