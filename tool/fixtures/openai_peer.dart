import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _version = 'phase1-openai-peer-v1';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The OpenAI peer does not accept command-line input.');
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
  final sockets = <WebSocket>{};
  unawaited(_serve(server, sockets, observations));

  _writeJsonLine(<String, Object?>{
    'type': 'ready',
    'version': _version,
    'sourceBlobHash': sourceBlobHash,
    'host': InternetAddress.loopbackIPv4.address,
    'port': server.port,
    'transports': const <String>[
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
      final value = jsonDecode(line);
      if (value is Map<String, Object?> && value['op'] == 'shutdown') {
        _writeJsonLine(<String, Object?>{
          'id': value['id'],
          'ok': true,
        });
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
    for (final socket in sockets.toList()) {
      await socket.close(WebSocketStatus.goingAway, 'peer shutdown');
    }
    await server.close(force: true);
  }

  if (!shutdownRequested) {
    stderr.writeln('Peer input closed without a shutdown command.');
    exitCode = 67;
  }
}

Future<void> _serve(
  HttpServer server,
  Set<WebSocket> sockets,
  _Observations observations,
) async {
  await for (final request in server) {
    unawaited(_handle(request, sockets, observations));
  }
}

Future<void> _handle(
  HttpRequest request,
  Set<WebSocket> sockets,
  _Observations observations,
) async {
  try {
    observations.paths.add(request.uri.path);
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization == 'Bearer fixture-key') {
      observations.authorizationHeaderSeen = true;
    }

    if (request.uri.path == '/v1/realtime') {
      await _handleRealtime(request, sockets, observations);
      return;
    }
    if (request.uri.path == '/observations') {
      await _writeJson(request.response, observations.toJson());
      return;
    }

    Map<String, Object?>? body;
    if (request.headers.contentType?.mimeType == 'application/json') {
      final text = await utf8.decoder.bind(request).join();
      if (text.isNotEmpty) {
        body = jsonDecode(text) as Map<String, Object?>;
      }
    } else {
      await request.drain<void>();
    }

    switch (request.uri.path) {
      case '/v1/chat/completions':
        if (body?['stream'] == true) {
          await _writeSse(request.response, _chatToolEvents);
        } else {
          await _writeJson(request.response, <String, Object?>{
            'id': 'chatcmpl_real_peer',
            'created': 1700000000,
            'model': 'gpt-5.4',
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
      case '/v1/responses':
        if (request.headers.value('x-fixture') == 'missing-output') {
          await _writeJson(request.response, <String, Object?>{
            'id': 'chatcmpl_wrong',
            'object': 'chat.completion',
            'choices': <Object?>[],
          });
        } else if (body?['stream'] == true) {
          await _writeSse(request.response, _responsesTextEvents);
        } else {
          await _writeJson(request.response, <String, Object?>{
            'id': 'resp_real_peer',
            'created_at': 1700000000,
            'model': 'gpt-5.4',
            'output': <Object?>[
              <String, Object?>{
                'type': 'computer_call',
                'id': 'computer_item_real',
                'call_id': 'computer_call_real',
                'status': 'completed',
                'actions': <Object?>[
                  <String, Object?>{
                    'type': 'click',
                    'button': 'left',
                    'x': 12,
                    'y': 34,
                  },
                  <String, Object?>{'type': 'screenshot'},
                ],
                'pending_safety_checks': <Object?>[],
              },
            ],
            'usage': <String, Object?>{
              'input_tokens': 5,
              'output_tokens': 2,
            },
          });
        }
      case '/v1/embeddings':
        await _writeJson(request.response, <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'index': 0,
              'embedding': <Object?>[0.1, 0.2],
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 1,
            'total_tokens': 1,
          },
        });
      case '/v1/images/generations':
        await _writeJson(request.response, <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'b64_json': base64Encode(<int>[1, 2, 3])
            },
          ],
        });
      case '/v1/audio/speech':
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..add(<int>[4, 5, 6]);
        await request.response.close();
      case '/v1/audio/transcriptions':
        await _writeJson(request.response, <String, Object?>{
          'text': 'real transcript',
          'language': 'english',
          'duration': 1.0,
          'segments': <Object?>[],
        });
      case '/v1/files':
        await _writeJson(request.response, <String, Object?>{
          'id': 'file_real',
          'filename': 'fixture.txt',
          'purpose': 'assistants',
          'bytes': 7,
          'created_at': 1700000000,
          'status': 'processed',
        });
      case '/v1/skills':
        await _writeJson(request.response, <String, Object?>{
          'id': 'skill_real',
          'name': 'fixture',
          'description': 'Real peer fixture',
          'latest_version': 'v1',
          'default_version': 'v1',
          'created_at': 1700000000,
          'updated_at': 1700000001,
        });
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

Future<void> _handleRealtime(
  HttpRequest request,
  Set<WebSocket> sockets,
  _Observations observations,
) async {
  if (!WebSocketTransformer.isUpgradeRequest(request)) {
    request.response.statusCode = HttpStatus.upgradeRequired;
    await request.response.close();
    return;
  }
  final requestedProtocols =
      request.headers.value('sec-websocket-protocol') ?? '';
  observations.websocketProtocols = requestedProtocols
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  observations.websocketAuthorizationSeen =
      request.headers.value(HttpHeaders.authorizationHeader) ==
          'Bearer fixture-key';

  final socket = await WebSocketTransformer.upgrade(
    request,
    protocolSelector: (protocols) => protocols.contains('realtime')
        ? 'realtime'
        : (protocols.isEmpty ? null : protocols.first),
  );
  sockets.add(socket);
  socket.listen(
    (message) {
      final value = jsonDecode(message as String) as Map<String, Object?>;
      final type = value['type'] as String?;
      if (type != null) {
        observations.websocketFrameTypes.add(type);
      }
      if (type == 'input_audio_buffer.commit') {
        socket
          ..add(jsonEncode(<String, Object?>{
            'type': 'conversation.item.input_audio_transcription.delta',
            'item_id': 'item_real',
            'delta': 'real ',
          }))
          ..add(jsonEncode(<String, Object?>{
            'type': 'conversation.item.input_audio_transcription.completed',
            'item_id': 'item_real',
            'transcript': 'real transcript',
          }));
      }
    },
    onDone: () => sockets.remove(socket),
    onError: (_) => sockets.remove(socket),
    cancelOnError: true,
  );
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

final class _Observations {
  bool authorizationHeaderSeen = false;
  bool websocketAuthorizationSeen = false;
  List<String> websocketProtocols = <String>[];
  final List<String> websocketFrameTypes = <String>[];
  final Set<String> paths = <String>{};

  Map<String, Object?> toJson() => <String, Object?>{
        'authorizationHeaderSeen': authorizationHeaderSeen,
        'websocketAuthorizationSeen': websocketAuthorizationSeen,
        'websocketProtocols': websocketProtocols,
        'websocketFrameTypes': websocketFrameTypes,
        'paths': paths.toList()..sort(),
      };
}

const _chatToolEvents = <String>[
  '{"id":"chatcmpl_real_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_real","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}',
  '{"id":"chatcmpl_real_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"city\\":\\"Shanghai\\"}"}}]}}]}',
  '{"id":"chatcmpl_real_stream","created":1700000000,"model":"gpt-5.4","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
  '{"choices":[],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}',
  '[DONE]',
];

const _responsesTextEvents = <String>[
  '{"type":"response.created","response":{"id":"resp_real_stream","created_at":1700000000,"model":"gpt-5.4"}}',
  '{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_real"}}',
  '{"type":"response.output_text.delta","item_id":"msg_real","delta":"real-responses-ok"}',
  '{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_real"}}',
  '{"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":1}}}',
];

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
