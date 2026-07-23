import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-01
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-02
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-03
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-04
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-05
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-06
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-07
  // Compatibility fixture (scripted-peer): P1-ANTHROPIC-08
  test('public provider preserves prompt, tools, citations and model policy',
      () async {
    final peer = _ScriptedAnthropicPeer();
    final provider = _provider(peer);
    final model = provider.messages('claude-sonnet-4-5');

    expect(model.provider, 'fixture.messages');
    expect(provider.chat('claude-sonnet-4-5').provider, 'fixture.messages');
    expect(
      () => createAnthropic(apiKey: 'fixture-key', baseUrl: ''),
      throwsA(isA<InvalidArgumentError>()),
    );

    final generated = await model.doGenerate(
      LanguageModelCallOptions(
        prompt: const <LanguageModelMessage>[
          UserMessage(<UserContentPart>[
            TextPart(
              'Find and fetch the source.',
              providerOptions: <String, JsonObject>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        tools: <LanguageModelTool>[
          anthropicTools.webSearch_20260209(maxUses: 1),
          anthropicTools.webFetch_20260209(
            maxUses: 1,
            citations: const AnthropicWebFetchCitations(enabled: true),
          ),
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
          ),
        ],
        toolChoice: const ToolChoiceAuto(),
        headers: const <String, String>{
          'anthropic-beta': 'fixture-user-beta',
        },
        providerOptions: const <String, JsonObject>{
          'fixture': <String, Object?>{
            'thinking': <String, Object?>{
              'type': 'enabled',
              'budgetTokens': 1024,
            },
            'disableParallelToolUse': true,
          },
        },
      ),
    );

    final request = peer.requests.first;
    expect(
      request.url.toString(),
      'https://peer.invalid/v1/messages',
    );
    expect(request.headers['x-api-key'], 'fixture-key');
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(request.headers['x-provider-header'], 'fixture');
    expect(
      request.headers['anthropic-beta'],
      contains('fixture-user-beta'),
    );
    final body = peer.jsonBodies.first;
    expect(body['model'], 'claude-sonnet-4-5');
    expect(body['thinking'], <String, Object?>{
      'type': 'enabled',
      'budget_tokens': 1024,
    });
    final messages = body['messages']! as List<Object?>;
    final userContent =
        (messages.first! as JsonObject)['content']! as List<Object?>;
    expect(
      (userContent.first! as JsonObject)['cache_control'],
      <String, Object?>{'type': 'ephemeral'},
    );
    final tools = (body['tools']! as List<Object?>).cast<JsonObject>();
    expect(
      tools.map((tool) => tool['type']),
      containsAll(<Object?>['web_search_20260209', 'web_fetch_20260209']),
    );
    expect(body['tool_choice'], <String, Object?>{
      'type': 'auto',
      'disable_parallel_tool_use': true,
    });

    expect(generated.finishReason.unified, FinishReasonType.stop);
    expect(generated.finishReason.raw, 'end_turn');
    expect(generated.usage.inputTokens.total, 5);
    expect(generated.usage.outputTokens.total, 2);
    expect(generated.content.whereType<ToolCall>(), hasLength(2));
    expect(generated.content.whereType<ToolResult>(), hasLength(2));
    expect(generated.content.whereType<SourceContent>(), hasLength(3));
    final generatedText = generated.content.whereType<TextContent>().single;
    expect(generatedText.providerMetadata, <String, JsonObject>{
      'anthropic': <String, Object?>{
        'citations': <Object?>[
          <String, Object?>{
            'type': 'web_search_result_location',
            'cited_text': 'Dart source',
            'url': 'https://example.com/dart',
            'title': 'Dart',
            'encrypted_index': 'enc-index',
          },
        ],
      },
    });
    expect(
      generated.providerMetadata?['anthropic']?['container'],
      <String, Object?>{
        'expiresAt': '2026-07-24T00:00:00Z',
        'id': 'container-fixture',
        'skills': null,
      },
    );
    expect(
      generated.providerMetadata?['fixture']?['container'],
      generated.providerMetadata?['anthropic']?['container'],
    );
    expect(
      forwardAnthropicContainerIdFromLastStep(
        <ProviderMetadata?>[generated.providerMetadata],
        providerKey: 'fixture',
      ),
      <String, JsonObject>{
        'anthropic': <String, Object?>{
          'container': <String, Object?>{'id': 'container-fixture'},
        },
        'fixture': <String, Object?>{
          'container': <String, Object?>{'id': 'container-fixture'},
        },
      },
    );

    await model.doGenerate(
      LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            TextPart(
              generatedText.text,
              providerOptions: generatedText.providerMetadata,
            ),
          ]),
          const UserMessage(<UserContentPart>[
            TextPart('What happened before that?'),
          ]),
        ],
      ),
    );
    final replayMessages = peer.jsonBodies[1]['messages']! as List<Object?>;
    final replayContent =
        (replayMessages.first! as JsonObject)['content']! as List<Object?>;
    expect(
      (replayContent.first! as JsonObject)['citations'],
      (generatedText.providerMetadata!['anthropic']!['citations']),
    );

    final futureResult = await provider.messages('future-model').doGenerate(
          const LanguageModelCallOptions(
            prompt: <LanguageModelMessage>[
              UserMessage(<UserContentPart>[TextPart('Return JSON')]),
            ],
            responseFormat: ResponseFormatJson(
              schema: JsonSchema(<String, Object?>{'type': 'object'}),
            ),
            providerOptions: <String, JsonObject>{
              'fixture': <String, Object?>{
                'structuredOutputMode': 'jsonTool',
                'disableParallelToolUse': false,
              },
            },
          ),
        );
    expect(futureResult.content, const <LanguageModelContent>[
      TextContent('{"ok":true}'),
    ]);
    expect(
      futureResult.warnings.whereType<CompatibilityWarning>(),
      contains(
        isA<CompatibilityWarning>()
            .having(
              (warning) => warning.feature,
              'feature',
              'maxOutputTokens',
            )
            .having(
              (warning) => warning.details,
              'details',
              contains('limited to 4096'),
            ),
      ),
    );
    expect(
      futureResult.warnings.whereType<UnsupportedWarning>(),
      contains(
        isA<UnsupportedWarning>().having(
          (warning) => warning.feature,
          'feature',
          'providerOptions.anthropic.disableParallelToolUse',
        ),
      ),
    );
    expect(peer.jsonBodies[2]['max_tokens'], 4096);
    expect(peer.jsonBodies[2]['tool_choice'], <String, Object?>{
      'type': 'any',
      'disable_parallel_tool_use': true,
    });

    await expectLater(
      model.doGenerate(
        const LanguageModelCallOptions(
          prompt: <LanguageModelMessage>[
            UserMessage(<UserContentPart>[TextPart('fail')]),
          ],
          headers: <String, String>{'x-fixture': 'http-error'},
        ),
      ),
      throwsA(
        isA<ApiCallError>()
            .having(
              (error) => error.message,
              'message',
              'scripted rate limit',
            )
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });

  test(
      'public streaming model preserves citation, usage, tool and error events',
      () async {
    final peer = _ScriptedAnthropicPeer();
    final model = _provider(peer).messages('claude-sonnet-4-5');

    final result = await model.doStream(
      const LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          UserMessage(<UserContentPart>[TextPart('stream')]),
        ],
        tools: <LanguageModelTool>[
          FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
          ),
        ],
      ),
    );
    final parts = await result.stream.toList();
    expect(
      parts.whereType<TextDelta>().map((part) => part.delta).join(),
      'streamed answer',
    );
    expect(
      parts.whereType<ReasoningDelta>().map((part) => part.delta).join(),
      'thinking',
    );
    expect(
      parts.whereType<TextEnd>().single.providerMetadata,
      <String, JsonObject>{
        'anthropic': <String, Object?>{
          'citations': <Object?>[
            <String, Object?>{
              'type': 'web_search_result_location',
              'cited_text': 'stream source',
              'url': 'https://example.com/stream',
              'title': 'Stream',
              'encrypted_index': 'stream-index',
            },
          ],
        },
      },
    );
    expect(parts.whereType<SourceContent>(), hasLength(1));
    expect(
      parts.whereType<ToolCall>().single,
      const ToolCall(
        toolCallId: 'toolu-stream',
        toolName: 'get_weather',
        input: '{"city":"Shanghai"}',
      ),
    );
    final finish = parts.whereType<FinishPart>().single;
    expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    expect(finish.finishReason.raw, 'tool_use');
    expect(finish.usage.inputTokens.total, 10);
    expect(finish.usage.outputTokens.total, 4);

    await expectLater(
      model.doStream(
        const LanguageModelCallOptions(
          prompt: <LanguageModelMessage>[
            UserMessage(<UserContentPart>[TextPart('stream error')]),
          ],
          headers: <String, String>{'x-fixture': 'stream-error'},
        ),
      ),
      throwsA(
        isA<ApiCallError>()
            .having((error) => error.message, 'message', 'scripted overloaded')
            .having((error) => error.statusCode, 'statusCode', 529)
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });

  test('public files and skills resources preserve multipart metadata',
      () async {
    final peer = _ScriptedAnthropicPeer();
    final provider = _provider(peer);

    final file = await provider.files().uploadFile(
          const FilesUploadOptions(
            data: FileDataText('fixture'),
            mediaType: 'text/plain',
            filename: 'fixture.txt',
          ),
        );
    final skill = await provider.skills().uploadSkill(
          const SkillsUploadOptions(
            displayTitle: 'Fixture skill',
            files: <SkillFile>[
              SkillFile(
                path: 'SKILL.md',
                data: FileDataText('# Fixture'),
              ),
            ],
          ),
        );

    expect(file.providerReference, <String, String>{
      'anthropic': 'file-scripted',
    });
    expect(file.providerMetadata?['anthropic']?['createdAt'],
        '2026-07-23T00:00:00Z');
    expect(skill.providerReference, <String, String>{
      'anthropic': 'skill-scripted',
    });
    expect(skill.displayTitle, 'Fixture skill');
    expect(peer.multipartPaths, <String>[
      '/v1/files',
      '/v1/skills',
    ]);
    expect(peer.requests[0].headers['anthropic-beta'],
        contains('files-api-2025-04-14'));
    expect(peer.requests[1].headers['anthropic-beta'],
        contains('skills-2025-10-02'));
  });
}

AnthropicProvider _provider(http.Client client) {
  return createAnthropic(
    apiKey: 'fixture-key',
    baseUrl: 'https://peer.invalid/v1/',
    headers: const <String, String>{'x-provider-header': 'fixture'},
    name: 'fixture.messages',
    client: client,
  );
}

final class _ScriptedAnthropicPeer extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final jsonBodies = <JsonObject>[];
  final multipartPaths = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.MultipartRequest) {
      multipartPaths.add(request.url.path);
      if (request.url.path == '/v1/files') {
        return _jsonResponse(<String, Object?>{
          'id': 'file-scripted',
          'type': 'file',
          'filename': 'fixture.txt',
          'mime_type': 'text/plain',
          'size_bytes': 7,
          'created_at': '2026-07-23T00:00:00Z',
        });
      }
      return _jsonResponse(<String, Object?>{
        'id': 'skill-scripted',
        'type': 'skill',
        'display_title': 'Fixture skill',
        'latest_version': null,
        'source': 'custom',
        'created_at': '2026-07-23T00:00:00Z',
        'updated_at': '2026-07-23T00:01:00Z',
      });
    }

    final body = jsonDecode((request as http.Request).body) as JsonObject;
    jsonBodies.add(body);
    if (request.headers['x-fixture'] == 'http-error') {
      return _jsonResponse(
        <String, Object?>{
          'type': 'error',
          'error': <String, Object?>{
            'type': 'rate_limit_error',
            'message': 'scripted rate limit',
          },
        },
        statusCode: 429,
      );
    }
    if (request.headers['x-fixture'] == 'stream-error') {
      return _sseResponse(
        'data: {"type":"error","error":{"type":"overloaded_error",'
        '"message":"scripted overloaded"}}\n\n',
      );
    }
    if (body['stream'] == true) {
      return _sseResponse(_streamResponse);
    }
    final tools = body['tools'] as List<Object?>?;
    final usesJsonTool =
        tools?.whereType<JsonObject>().any((tool) => tool['name'] == 'json') ??
            false;
    return _jsonResponse(
      usesJsonTool ? _jsonToolResponse : _generateResponse,
    );
  }
}

const _generateResponse = <String, Object?>{
  'type': 'message',
  'id': 'msg-scripted',
  'model': 'claude-sonnet-4-5',
  'content': <Object?>[
    <String, Object?>{
      'type': 'server_tool_use',
      'id': 'search-scripted',
      'name': 'web_search',
      'input': <String, Object?>{'query': 'Dart'},
    },
    <String, Object?>{
      'type': 'web_search_tool_result',
      'tool_use_id': 'search-scripted',
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
      'id': 'fetch-scripted',
      'name': 'web_fetch',
      'input': <String, Object?>{'url': 'https://example.com/doc.pdf'},
    },
    <String, Object?>{
      'type': 'web_fetch_tool_result',
      'tool_use_id': 'fetch-scripted',
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
      'text': 'scripted answer',
      'citations': <Object?>[
        <String, Object?>{
          'type': 'web_search_result_location',
          'cited_text': 'Dart source',
          'url': 'https://example.com/dart',
          'title': 'Dart',
          'encrypted_index': 'enc-index',
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
    'id': 'container-fixture',
    'expires_at': '2026-07-24T00:00:00Z',
  },
};

const _jsonToolResponse = <String, Object?>{
  'type': 'message',
  'id': 'msg-json-scripted',
  'model': 'future-model',
  'content': <Object?>[
    <String, Object?>{
      'type': 'tool_use',
      'id': 'json-scripted',
      'name': 'json',
      'input': <String, Object?>{'ok': true},
    },
  ],
  'stop_reason': 'tool_use',
  'stop_sequence': null,
  'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
};

const _streamResponse =
    'data: {"type":"message_start","message":{"id":"msg-stream",'
    '"model":"claude-sonnet-4-5","role":"assistant","content":[],'
    '"stop_reason":null,"usage":{"input_tokens":10}}}\n\n'
    'data: {"type":"content_block_start","index":0,"content_block":'
    '{"type":"text","text":""}}\n\n'
    'data: {"type":"content_block_delta","index":0,"delta":'
    '{"type":"text_delta","text":"streamed answer"}}\n\n'
    'data: {"type":"content_block_delta","index":0,"delta":'
    '{"type":"citations_delta","citation":'
    '{"type":"web_search_result_location","cited_text":"stream source",'
    '"url":"https://example.com/stream","title":"Stream",'
    '"encrypted_index":"stream-index"}}}\n\n'
    'data: {"type":"content_block_stop","index":0}\n\n'
    'data: {"type":"content_block_start","index":1,"content_block":'
    '{"type":"thinking","thinking":"","signature":""}}\n\n'
    'data: {"type":"content_block_delta","index":1,"delta":'
    '{"type":"thinking_delta","thinking":"thinking"}}\n\n'
    'data: {"type":"content_block_delta","index":1,"delta":'
    '{"type":"signature_delta","signature":"signature-stream"}}\n\n'
    'data: {"type":"content_block_stop","index":1}\n\n'
    'data: {"type":"content_block_start","index":2,"content_block":'
    '{"type":"tool_use","id":"toolu-stream","name":"get_weather",'
    '"input":{}}}\n\n'
    'data: {"type":"content_block_delta","index":2,"delta":'
    '{"type":"input_json_delta","partial_json":"{\\"city\\":'
    '\\"Shanghai\\"}"}}\n\n'
    'data: {"type":"content_block_stop","index":2}\n\n'
    'data: {"type":"message_delta","delta":{"stop_reason":"tool_use",'
    '"stop_sequence":null},"usage":{"output_tokens":4}}\n\n'
    'data: {"type":"message_stop"}\n\n';

http.StreamedResponse _jsonResponse(
  JsonObject value, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(value))),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _sseResponse(String value) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(value)),
    200,
    headers: const <String, String>{'content-type': 'text/event-stream'},
  );
}
