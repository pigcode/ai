import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _version = 'phase1-anthropic-peer-v1';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The Anthropic peer does not accept command-line input.');
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
    if (request.headers.value('x-api-key') == 'real-key') {
      observations.apiKeySeen = true;
    }
    if (request.headers.value('anthropic-version') == '2023-06-01') {
      observations.versionSeen = true;
    }
    if (request.headers.value('x-provider-header') == 'real') {
      observations.providerHeaderSeen = true;
    }
    final beta = request.headers.value('anthropic-beta');
    if (beta != null) {
      observations.betas.addAll(
        beta.split(',').map((value) => value.trim()).where(
              (value) => value.isNotEmpty,
            ),
      );
    }

    if (request.uri.path == '/observations') {
      await _writeJson(request.response, observations.toJson());
      return;
    }
    if (request.uri.path == '/v1/files') {
      observations.filesMultipartSeen =
          request.headers.contentType?.mimeType == 'multipart/form-data';
      await request.drain<void>();
      await _writeJson(request.response, <String, Object?>{
        'id': 'file-real',
        'type': 'file',
        'filename': 'real.txt',
        'mime_type': 'text/plain',
        'size_bytes': 4,
        'created_at': '2026-07-23T00:00:00Z',
      });
      return;
    }
    if (request.uri.path == '/v1/skills') {
      observations.skillsMultipartSeen =
          request.headers.contentType?.mimeType == 'multipart/form-data';
      await request.drain<void>();
      await _writeJson(request.response, <String, Object?>{
        'id': 'skill-real',
        'type': 'skill',
        'display_title': 'Real skill',
        'latest_version': null,
        'source': 'custom',
        'created_at': '2026-07-23T00:00:00Z',
        'updated_at': '2026-07-23T00:01:00Z',
      });
      return;
    }
    if (request.uri.path != '/v1/messages') {
      await request.drain<void>();
      await _writeJson(
        request.response,
        <String, Object?>{'error': 'unknown_path'},
        statusCode: HttpStatus.notFound,
      );
      return;
    }

    final text = await utf8.decoder.bind(request).join();
    final body = jsonDecode(text) as Map<String, Object?>;
    _observeBody(body, observations);
    if (request.headers.value('x-fixture') == 'http-error') {
      await _writeJson(
        request.response,
        <String, Object?>{
          'type': 'error',
          'error': <String, Object?>{
            'type': 'rate_limit_error',
            'message': 'real rate limit',
          },
        },
        statusCode: HttpStatus.tooManyRequests,
      );
      return;
    }
    if (request.headers.value('x-fixture') == 'stream-error') {
      await _writeSse(request.response, const <String>[
        '{"type":"error","error":{"type":"overloaded_error",'
            '"message":"real overloaded"}}',
      ]);
      return;
    }
    if (body['stream'] == true) {
      observations.streamRequestCount += 1;
      await _writeSse(request.response, _streamEvents);
      return;
    }
    final tools = body['tools'] as List<Object?>?;
    final usesJsonTool = tools
            ?.whereType<Map<String, Object?>>()
            .any((tool) => tool['name'] == 'json') ??
        false;
    await _writeJson(
      request.response,
      usesJsonTool ? _jsonToolResponse : _generateResponse,
    );
  } on Object catch (error) {
    try {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('peer_error:${error.runtimeType}');
      await request.response.close();
    } on StateError {
      // The response was already committed.
    }
  }
}

void _observeBody(
  Map<String, Object?> body,
  _Observations observations,
) {
  final messages = body['messages'] as List<Object?>?;
  if (messages != null) {
    for (final rawMessage in messages) {
      final message = rawMessage! as Map<String, Object?>;
      final content = message['content'] as List<Object?>?;
      if (content == null) {
        continue;
      }
      for (final rawPart in content) {
        final part = rawPart! as Map<String, Object?>;
        if (part['cache_control'] != null) {
          observations.cacheControlSeen = true;
        }
        if (part['citations'] != null) {
          observations.citationReplaySeen = true;
        }
      }
    }
  }
  if (body['thinking'] is Map<String, Object?>) {
    observations.thinkingSeen = true;
  }
  final tools = body['tools'] as List<Object?>?;
  if (tools != null) {
    final toolMaps = tools.whereType<Map<String, Object?>>().toList();
    if (toolMaps.any((tool) => tool['type'] == 'web_search_20260209') &&
        toolMaps.any((tool) => tool['type'] == 'web_fetch_20260209')) {
      observations.providerToolsSeen = true;
    }
    if (toolMaps.any((tool) => tool['name'] == 'json')) {
      final choice = body['tool_choice'] as Map<String, Object?>?;
      observations.serialJsonToolSeen =
          choice?['disable_parallel_tool_use'] == true;
    }
  }
  if (body['model'] == 'future-model' && body['max_tokens'] == 4096) {
    observations.unknownFallbackSeen = true;
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

const _generateResponse = <String, Object?>{
  'type': 'message',
  'id': 'msg-real',
  'model': 'claude-sonnet-4-5',
  'content': <Object?>[
    <String, Object?>{
      'type': 'server_tool_use',
      'id': 'search-real',
      'name': 'web_search',
      'input': <String, Object?>{'query': 'Dart'},
    },
    <String, Object?>{
      'type': 'web_search_tool_result',
      'tool_use_id': 'search-real',
      'content': <Object?>[
        <String, Object?>{
          'type': 'web_search_result',
          'url': 'https://example.com/dart',
          'title': 'Dart',
          'encrypted_content': 'encrypted-dart',
          'page_age': '1d',
        },
      ],
    },
    <String, Object?>{
      'type': 'server_tool_use',
      'id': 'fetch-real',
      'name': 'web_fetch',
      'input': <String, Object?>{'url': 'https://example.com/doc.pdf'},
    },
    <String, Object?>{
      'type': 'web_fetch_tool_result',
      'tool_use_id': 'fetch-real',
      'content': <String, Object?>{
        'type': 'web_fetch_result',
        'url': 'https://example.com/doc.pdf',
        'retrieved_at': '2026-07-23T00:00:00Z',
        'content': <String, Object?>{
          'type': 'document',
          'title': 'Fetched document',
          'citations': <String, Object?>{'enabled': true},
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': 'JVBERi0=',
          },
        },
      },
    },
    <String, Object?>{
      'type': 'text',
      'text': 'real answer',
      'citations': <Object?>[
        <String, Object?>{
          'type': 'web_search_result_location',
          'cited_text': 'Dart source',
          'url': 'https://example.com/dart',
          'title': 'Dart',
          'encrypted_index': 'real-index',
        },
        <String, Object?>{
          'type': 'char_location',
          'cited_text': 'PDF source',
          'document_index': 0,
          'document_title': null,
          'start_char_index': 1,
          'end_char_index': 4,
        },
      ],
    },
  ],
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': <String, Object?>{'input_tokens': 5, 'output_tokens': 2},
  'container': <String, Object?>{
    'id': 'container-real',
    'expires_at': '2026-07-24T00:00:00Z',
  },
};

const _jsonToolResponse = <String, Object?>{
  'type': 'message',
  'id': 'msg-json-real',
  'model': 'future-model',
  'content': <Object?>[
    <String, Object?>{
      'type': 'tool_use',
      'id': 'json-real',
      'name': 'json',
      'input': <String, Object?>{'ok': true},
    },
  ],
  'stop_reason': 'tool_use',
  'stop_sequence': null,
  'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
};

const _streamEvents = <String>[
  '{"type":"message_start","message":{"id":"msg-stream-real",'
      '"model":"claude-sonnet-4-5","role":"assistant","content":[],'
      '"stop_reason":null,"usage":{"input_tokens":10}}}',
  '{"type":"content_block_start","index":0,"content_block":'
      '{"type":"text","text":""}}',
  '{"type":"content_block_delta","index":0,"delta":'
      '{"type":"text_delta","text":"real streamed answer"}}',
  '{"type":"content_block_delta","index":0,"delta":'
      '{"type":"citations_delta","citation":'
      '{"type":"web_search_result_location","cited_text":"real stream source",'
      '"url":"https://example.com/stream","title":"Stream",'
      '"encrypted_index":"real-stream-index"}}}',
  '{"type":"content_block_stop","index":0}',
  '{"type":"content_block_start","index":1,"content_block":'
      '{"type":"tool_use","id":"toolu-real","name":"get_weather","input":{}}}',
  '{"type":"content_block_delta","index":1,"delta":'
      '{"type":"input_json_delta","partial_json":'
      '"{\\"city\\":\\"Shanghai\\"}"}}',
  '{"type":"content_block_stop","index":1}',
  '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
      '"stop_sequence":null},"usage":{"output_tokens":4}}',
  '{"type":"message_stop"}',
];

final class _Observations {
  bool apiKeySeen = false;
  bool versionSeen = false;
  bool providerHeaderSeen = false;
  bool cacheControlSeen = false;
  bool thinkingSeen = false;
  bool providerToolsSeen = false;
  bool citationReplaySeen = false;
  bool serialJsonToolSeen = false;
  bool unknownFallbackSeen = false;
  bool filesMultipartSeen = false;
  bool skillsMultipartSeen = false;
  int streamRequestCount = 0;
  final Set<String> betas = <String>{};
  final Set<String> paths = <String>{};

  Map<String, Object?> toJson() => <String, Object?>{
        'apiKeySeen': apiKeySeen,
        'versionSeen': versionSeen,
        'providerHeaderSeen': providerHeaderSeen,
        'cacheControlSeen': cacheControlSeen,
        'thinkingSeen': thinkingSeen,
        'providerToolsSeen': providerToolsSeen,
        'citationReplaySeen': citationReplaySeen,
        'serialJsonToolSeen': serialJsonToolSeen,
        'unknownFallbackSeen': unknownFallbackSeen,
        'filesMultipartSeen': filesMultipartSeen,
        'skillsMultipartSeen': skillsMultipartSeen,
        'streamRequestCount': streamRequestCount,
        'betas': betas.toList()..sort(),
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
