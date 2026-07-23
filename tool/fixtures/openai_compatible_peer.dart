import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _version = 'phase1-openai-compatible-peer-v1';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'The OpenAI-compatible peer does not accept command-line input.',
    );
    exitCode = 64;
    return;
  }

  final sourceBlobHash = _readSourceBlobHash();
  if (sourceBlobHash == null) {
    exitCode = 66;
    return;
  }

  final observations = _Observations();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(_serve(server, observations));
  _writeJsonLine(<String, Object?>{
    'type': 'ready',
    'version': _version,
    'sourceBlobHash': sourceBlobHash,
    'host': InternetAddress.loopbackIPv4.address,
    'port': server.port,
    'transports': const <String>['loopback-http', 'loopback-sse'],
  });

  var shutdownRequested = false;
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) {
        continue;
      }
      final value = jsonDecode(line);
      if (value is Map<String, Object?> && value['op'] == 'shutdown') {
        _writeJsonLine(<String, Object?>{'id': value['id'], 'ok': true});
        shutdownRequested = true;
        break;
      }
      _writeJsonLine(<String, Object?>{
        'id': value is Map<String, Object?> ? value['id'] : null,
        'ok': false,
        'error': 'unknown_operation',
      });
    }
  } finally {
    await server.close(force: true);
  }

  if (!shutdownRequested) {
    stderr.writeln('Peer input closed without a shutdown command.');
    exitCode = 67;
  }
}

Future<void> _serve(HttpServer server, _Observations observations) async {
  await for (final request in server) {
    unawaited(_handle(request, observations));
  }
}

Future<void> _handle(
  HttpRequest request,
  _Observations observations,
) async {
  try {
    observations.paths.add(request.uri.path);
    if (request.headers.value(HttpHeaders.authorizationHeader) ==
        'Bearer real-key') {
      observations.authorizationHeaderSeen = true;
    }
    if (request.headers.value('x-provider-header') == 'real') {
      observations.providerHeaderSeen = true;
    }
    if (request.uri.queryParameters['tenant'] == 'real') {
      observations.querySeen = true;
    }

    if (request.uri.path == '/observations') {
      await _writeJson(request.response, observations.toJson());
      return;
    }

    final text = await utf8.decoder.bind(request).join();
    final body = text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
    if (body['future_option'] == 'real-passthrough') {
      observations.unknownOptionSeen = true;
    }
    if (body['user'] == 'real-user' &&
        body['reasoning_effort'] == 'vendor-real') {
      observations.customOptionsSeen = true;
    }

    switch (request.uri.path) {
      case '/v1/chat/completions':
        if (request.headers.value('x-fixture') == 'stream-error') {
          await _writeSse(request.response, const <String>[
            '{"error":{"message":"real stream failure",'
                '"code":"REAL_STREAM_FAILURE","detail":{"retry":false}}}',
          ]);
        } else if (body['stream'] == true) {
          observations.streamRequestCount += 1;
          await _writeSse(request.response, _chatEvents);
        } else {
          await _writeJson(request.response, <String, Object?>{
            'id': 'chatcmpl-real',
            'created': 1700000000,
            'model': 'chat-model',
            'vendor_trace': 'trace-real',
            'choices': <Object?>[
              <String, Object?>{
                'index': 0,
                'message': <String, Object?>{
                  'role': 'assistant',
                  'content': 'real-chat-ok',
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': <String, Object?>{
              'prompt_tokens': 4,
              'completion_tokens': 1,
              'total_tokens': 5,
            },
          });
        }
      case '/v1/embeddings':
        if (request.headers.value('x-fixture') == 'embedding-error') {
          await _writeJson(
            request.response,
            <String, Object?>{
              'error': <String, Object?>{
                'message': 'real embedding failure',
                'code': 'REAL_RATE_LIMIT',
              },
            },
            statusCode: HttpStatus.tooManyRequests,
          );
        } else {
          await _writeJson(request.response, <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'index': 0,
                'embedding': <Object?>[0.5, 0.6],
              },
              <String, Object?>{
                'index': 1,
                'embedding': <Object?>[0.7, 0.8],
              },
            ],
            'usage': <String, Object?>{
              'prompt_tokens': 9,
              'total_tokens': 9,
            },
            'providerMetadata': <String, Object?>{
              'vendor-extension': <String, Object?>{'region': 'real'},
            },
          });
        }
      default:
        await _writeJson(
          request.response,
          <String, Object?>{'error': 'unknown_path'},
          statusCode: HttpStatus.notFound,
        );
    }
  } on Object catch (error) {
    try {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('peer_error:${error.runtimeType}');
      await request.response.close();
    } on StateError {
      // The response was already committed by the scripted path.
    }
  }
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, Object?> value, {
  int statusCode = HttpStatus.ok,
}) async {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(value));
  await response.close();
}

Future<void> _writeSse(
  HttpResponse response,
  List<String> events,
) async {
  response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType('text', 'event-stream');
  for (final event in events) {
    response.write('data: $event\n\n');
    await response.flush();
  }
  await response.close();
}

const _chatEvents = <String>[
  '{"id":"chatcmpl-real-stream","created":1700000000,'
      '"model":"chat-model","choices":[{"index":0,"delta":'
      '{"role":"assistant","content":"real-stream-ok"}}]}',
  '{"id":"chatcmpl-real-stream","created":1700000000,'
      '"model":"chat-model","choices":[{"index":0,"delta":{},'
      '"finish_reason":"stop"}]}',
  '{"id":"chatcmpl-real-stream","created":1700000000,'
      '"model":"chat-model","choices":[],"usage":{"prompt_tokens":6,'
      '"completion_tokens":2,"total_tokens":8}}',
  '[DONE]',
];

final class _Observations {
  bool authorizationHeaderSeen = false;
  bool providerHeaderSeen = false;
  bool querySeen = false;
  bool unknownOptionSeen = false;
  bool customOptionsSeen = false;
  int streamRequestCount = 0;
  final Set<String> paths = <String>{};

  Map<String, Object?> toJson() => <String, Object?>{
        'authorizationHeaderSeen': authorizationHeaderSeen,
        'providerHeaderSeen': providerHeaderSeen,
        'querySeen': querySeen,
        'unknownOptionSeen': unknownOptionSeen,
        'customOptionsSeen': customOptionsSeen,
        'streamRequestCount': streamRequestCount,
        'paths': paths.toList()..sort(),
      };
}

void _writeJsonLine(Map<String, Object?> value) {
  stdout.writeln(jsonEncode(value));
}

String? _readSourceBlobHash() {
  final result = Process.runSync(
    'git',
    <String>['hash-object', '--', Platform.script.toFilePath()],
  );
  if (result.exitCode != 0) {
    stderr.writeln('Unable to hash peer source with git hash-object.');
    return null;
  }
  final hash = (result.stdout as String).trim();
  return RegExp(r'^[a-f0-9]{40}$').hasMatch(hash) ? hash : null;
}
