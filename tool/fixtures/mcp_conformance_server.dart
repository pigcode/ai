import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: mcp_conformance_server.dart');
    exitCode = 64;
    return;
  }
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = httpServer.port;
  final random = Random.secure();
  final endpoint = McpHttpEndpoint(
    path: '/mcp',
    allowedHosts: <String>{
      '127.0.0.1:$port',
      'localhost:$port',
    },
    allowedOrigins: <String>{
      'http://127.0.0.1:$port',
      'http://localhost:$port',
    },
    acceptedProtocolVersions: const <String>[
      '2025-11-25',
      '2025-03-26',
    ],
    maxSseEventsPerSideChannelResponse: 1,
    createSessionId: () => base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', ''),
    serverFactory: (transport) {
      late final McpServer server;
      server = McpServer(
        transport: transport,
        capabilities: McpServerCapabilities(
          resources: true,
          resourceSubscribe: true,
          resourceListChanged: true,
          prompts: true,
          promptListChanged: true,
          tools: true,
          toolListChanged: true,
          completions: true,
          logging: true,
        ),
        handlers: _handlers(() => server),
        serverInfo: const <String, Object?>{
          'name': 'pigcode-ai-mcp-conformance-server',
          'version': '0.0.1',
        },
      );
      return server;
    },
  );
  final adapter = McpIoHttpServerAdapter(endpoint);
  final subscription = httpServer.listen(
    (request) async {
      try {
        await adapter.handle(request);
      } on Object catch (error) {
        stderr.writeln('MCP HTTP adapter error: ${error.runtimeType}');
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } on Object {
          // The response may already have started.
        }
      }
    },
  );
  stdout.writeln('http://127.0.0.1:$port/mcp');
  await stdout.flush();

  final stop = ProcessSignal.sigterm.watch().first;
  await stop;
  await subscription.cancel();
  await endpoint.close();
  await httpServer.close(force: true);
}

const _testPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
    '/x8AAusB9Wl2nWQAAAAASUVORK5CYII=';
const _testWav = 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

McpHandlerSet _handlers(McpServer Function() server) => McpHandlerSet(
      requests: <String, McpRequestHandler>{
        'logging/setLevel': (_) => const <String, Object?>{},
        'completion/complete': (_) => const <String, Object?>{
              'completion': <String, Object?>{
                'values': <Object?>[],
                'hasMore': false,
              },
            },
        'tools/list': (_) => const <String, Object?>{
              'tools': _tools,
            },
        'tools/call': (invocation) => _callTool(invocation, server()),
        'resources/list': (_) => const <String, Object?>{
              'resources': <Object?>[
                <String, Object?>{
                  'name': 'static-text',
                  'uri': 'test://static-text',
                  'mimeType': 'text/plain',
                },
                <String, Object?>{
                  'name': 'static-binary',
                  'uri': 'test://static-binary',
                  'mimeType': 'image/png',
                },
              ],
            },
        'resources/templates/list': (_) => const <String, Object?>{
              'resourceTemplates': <Object?>[
                <String, Object?>{
                  'name': 'test-template',
                  'uriTemplate': 'test://template/{id}/data',
                },
              ],
            },
        'resources/read': _readResource,
        'resources/subscribe': (_) => const <String, Object?>{},
        'resources/unsubscribe': (_) => const <String, Object?>{},
        'prompts/list': (_) => const <String, Object?>{
              'prompts': <Object?>[
                <String, Object?>{
                  'name': 'test_simple_prompt',
                  'description': 'A simple conformance prompt.',
                },
                <String, Object?>{
                  'name': 'test_prompt_with_arguments',
                  'description': 'A parameterized conformance prompt.',
                  'arguments': <Object?>[
                    <String, Object?>{
                      'name': 'arg1',
                      'required': true,
                    },
                    <String, Object?>{
                      'name': 'arg2',
                      'required': true,
                    },
                  ],
                },
                <String, Object?>{
                  'name': 'test_prompt_with_embedded_resource',
                  'description': 'A prompt containing an embedded resource.',
                  'arguments': <Object?>[
                    <String, Object?>{
                      'name': 'resourceUri',
                      'required': true,
                    },
                  ],
                },
                <String, Object?>{
                  'name': 'test_prompt_with_image',
                  'description': 'A prompt containing an image.',
                },
              ],
            },
        'prompts/get': _getPrompt,
      },
    );

const _tools = <Object?>[
  <String, Object?>{
    'name': 'test_simple_text',
    'description': 'Returns simple text.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_image_content',
    'description': 'Returns image content.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_audio_content',
    'description': 'Returns audio content.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_embedded_resource',
    'description': 'Returns an embedded resource.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_multiple_content_types',
    'description': 'Returns mixed content.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_tool_with_logging',
    'description': 'Emits log notifications.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_error_handling',
    'description': 'Returns a tool error.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_tool_with_progress',
    'description': 'Emits progress notifications.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_sampling',
    'description': 'Requests sampling from the client.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'prompt': <String, Object?>{'type': 'string'},
      },
      'required': <Object?>['prompt'],
    },
  },
  <String, Object?>{
    'name': 'test_elicitation',
    'description': 'Requests elicitation from the client.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'message': <String, Object?>{'type': 'string'},
      },
      'required': <Object?>['message'],
    },
  },
  <String, Object?>{
    'name': 'test_elicitation_sep1034_defaults',
    'description': 'Requests elicitation with primitive defaults.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'test_elicitation_sep1330_enums',
    'description': 'Requests elicitation with enum variants.',
    'inputSchema': <String, Object?>{'type': 'object'},
  },
  <String, Object?>{
    'name': 'json_schema_2020_12_tool',
    'description': 'Tool with JSON Schema 2020-12 features',
    'inputSchema': <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      r'$defs': <String, Object?>{
        'address': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'street': <String, Object?>{'type': 'string'},
            'city': <String, Object?>{'type': 'string'},
          },
        },
      },
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'address': <String, Object?>{r'$ref': r'#/$defs/address'},
      },
      'additionalProperties': false,
    },
  },
];

Future<Map<String, Object?>> _callTool(
  McpRequestInvocation invocation,
  McpServer server,
) async {
  final params = invocation.params! as Map<String, Object?>;
  final name = params['name']! as String;
  final arguments =
      params['arguments'] as Map<String, Object?>? ?? const <String, Object?>{};
  switch (name) {
    case 'test_simple_text':
      return _textResult('This is a simple text response for testing.');
    case 'test_image_content':
      return <String, Object?>{
        'content': <Object?>[
          const <String, Object?>{
            'type': 'image',
            'data': _testPng,
            'mimeType': 'image/png',
          },
        ],
      };
    case 'test_audio_content':
      return <String, Object?>{
        'content': <Object?>[
          const <String, Object?>{
            'type': 'audio',
            'data': _testWav,
            'mimeType': 'audio/wav',
          },
        ],
      };
    case 'test_embedded_resource':
      return <String, Object?>{
        'content': <Object?>[
          const <String, Object?>{
            'type': 'resource',
            'resource': <String, Object?>{
              'uri': 'test://embedded-resource',
              'mimeType': 'text/plain',
              'text': 'This is an embedded resource content.',
            },
          },
        ],
      };
    case 'test_multiple_content_types':
      return <String, Object?>{
        'content': <Object?>[
          const <String, Object?>{
            'type': 'text',
            'text': 'Multiple content types test:',
          },
          const <String, Object?>{
            'type': 'image',
            'data': _testPng,
            'mimeType': 'image/png',
          },
          const <String, Object?>{
            'type': 'resource',
            'resource': <String, Object?>{
              'uri': 'test://mixed-content-resource',
              'mimeType': 'application/json',
              'text': '{"test":"data","value":123}',
            },
          },
        ],
      };
    case 'test_tool_with_logging':
      for (final message in const <String>[
        'Tool execution started',
        'Tool processing data',
        'Tool execution completed',
      ]) {
        await server.logMessage(
          McpLoggingMessageNotificationParams.fromJson(
            <String, Object?>{
              'level': 'info',
              'logger': 'pigcode-conformance',
              'data': message,
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return _textResult('Tool execution completed.');
    case 'test_error_handling':
      return <String, Object?>{
        'isError': true,
        'content': <Object?>[
          const <String, Object?>{
            'type': 'text',
            'text': 'This tool intentionally returns an error for testing',
          },
        ],
      };
    case 'test_tool_with_progress':
      final meta = params['_meta'] as Map<String, Object?>?;
      final token = meta?['progressToken'];
      if (token != null) {
        for (final progress in const <int>[0, 50, 100]) {
          await server.notifyProgress(
            McpProgressNotificationParams.fromJson(
              <String, Object?>{
                'progressToken': token,
                'progress': progress,
                'total': 100,
              },
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      return _textResult('Progress tool completed.');
    case 'test_sampling':
      final sampled = await server.createMessage(
        McpCreateMessageRequestParams.fromJson(
          <String, Object?>{
            'messages': <Object?>[
              <String, Object?>{
                'role': 'user',
                'content': <String, Object?>{
                  'type': 'text',
                  'text': arguments['prompt']! as String,
                },
              },
            ],
            'maxTokens': 100,
          },
        ),
        timeout: const Duration(seconds: 5),
      );
      final sampledJson = sampled.toJson()! as Map<String, Object?>;
      final content = sampledJson['content']! as Map<String, Object?>;
      return _textResult('LLM response: ${content['text'] ?? content}');
    case 'test_elicitation':
      final elicited = await server.elicit(
        McpElicitRequestParams.fromJson(
          <String, Object?>{
            'message': arguments['message']! as String,
            'requestedSchema': const <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'username': <String, Object?>{
                  'type': 'string',
                  'description': "User's response",
                },
                'email': <String, Object?>{
                  'type': 'string',
                  'description': "User's email address",
                },
              },
              'required': <Object?>['username', 'email'],
            },
          },
        ),
        timeout: const Duration(seconds: 5),
      );
      return _textResult('User response: ${jsonEncode(elicited.toJson())}');
    case 'test_elicitation_sep1034_defaults':
      final elicited = await server.elicit(
        McpElicitRequestParams.fromJson(
          const <String, Object?>{
            'message': 'Test primitive default values.',
            'requestedSchema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'name': <String, Object?>{
                  'type': 'string',
                  'default': 'John Doe',
                },
                'age': <String, Object?>{
                  'type': 'integer',
                  'default': 30,
                },
                'score': <String, Object?>{
                  'type': 'number',
                  'default': 95.5,
                },
                'status': <String, Object?>{
                  'type': 'string',
                  'enum': <Object?>['active', 'inactive', 'pending'],
                  'default': 'active',
                },
                'verified': <String, Object?>{
                  'type': 'boolean',
                  'default': true,
                },
              },
              'required': <Object?>[],
            },
          },
        ),
        timeout: const Duration(seconds: 5),
      );
      return _textResult(
        'Elicitation completed: ${jsonEncode(elicited.toJson())}',
      );
    case 'test_elicitation_sep1330_enums':
      final elicited = await server.elicit(
        McpElicitRequestParams.fromJson(
          const <String, Object?>{
            'message': 'Test enum schema variants.',
            'requestedSchema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'untitledSingle': <String, Object?>{
                  'type': 'string',
                  'enum': <Object?>['option1', 'option2', 'option3'],
                },
                'titledSingle': <String, Object?>{
                  'type': 'string',
                  'oneOf': <Object?>[
                    <String, Object?>{
                      'const': 'value1',
                      'title': 'First Option',
                    },
                    <String, Object?>{
                      'const': 'value2',
                      'title': 'Second Option',
                    },
                  ],
                },
                'legacyEnum': <String, Object?>{
                  'type': 'string',
                  'enum': <Object?>['opt1', 'opt2', 'opt3'],
                  'enumNames': <Object?>[
                    'Option One',
                    'Option Two',
                    'Option Three',
                  ],
                },
                'untitledMulti': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    'type': 'string',
                    'enum': <Object?>['option1', 'option2', 'option3'],
                  },
                },
                'titledMulti': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    'anyOf': <Object?>[
                      <String, Object?>{
                        'const': 'value1',
                        'title': 'First Choice',
                      },
                      <String, Object?>{
                        'const': 'value2',
                        'title': 'Second Choice',
                      },
                    ],
                  },
                },
              },
              'required': <Object?>[],
            },
          },
        ),
        timeout: const Duration(seconds: 5),
      );
      return _textResult(
        'Elicitation completed: ${jsonEncode(elicited.toJson())}',
      );
    default:
      return _textResult(arguments['text']?.toString() ?? 'hello');
  }
}

Map<String, Object?> _textResult(String text) => <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    };

Map<String, Object?> _readResource(McpRequestInvocation invocation) {
  final params = invocation.params! as Map<String, Object?>;
  final uri = params['uri']! as String;
  if (uri == 'test://static-binary') {
    return <String, Object?>{
      'contents': <Object?>[
        const <String, Object?>{
          'uri': 'test://static-binary',
          'mimeType': 'image/png',
          'blob': _testPng,
        },
      ],
    };
  }
  if (uri == 'test://template/123/data') {
    return <String, Object?>{
      'contents': <Object?>[
        const <String, Object?>{
          'uri': 'test://template/123/data',
          'mimeType': 'application/json',
          'text': '{"id":"123","templateTest":true,"data":"Data for ID: 123"}',
        },
      ],
    };
  }
  return <String, Object?>{
    'contents': <Object?>[
      <String, Object?>{
        'uri': uri,
        'mimeType': 'text/plain',
        'text': 'This is the content of the static text resource.',
      },
    ],
  };
}

Map<String, Object?> _getPrompt(McpRequestInvocation invocation) {
  final params = invocation.params! as Map<String, Object?>;
  final name = params['name']! as String;
  final arguments =
      params['arguments'] as Map<String, Object?>? ?? const <String, Object?>{};
  switch (name) {
    case 'test_prompt_with_arguments':
      return _promptMessages(<Object?>[
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'text',
            'text': "Prompt with arguments: arg1='${arguments['arg1']}', "
                "arg2='${arguments['arg2']}'",
          },
        },
      ]);
    case 'test_prompt_with_embedded_resource':
      return _promptMessages(<Object?>[
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'resource',
            'resource': <String, Object?>{
              'uri': arguments['resourceUri']! as String,
              'mimeType': 'text/plain',
              'text': 'Embedded resource content for testing.',
            },
          },
        },
        const <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'text',
            'text': 'Please process the embedded resource above.',
          },
        },
      ]);
    case 'test_prompt_with_image':
      return _promptMessages(const <Object?>[
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'image',
            'data': _testPng,
            'mimeType': 'image/png',
          },
        },
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'text',
            'text': 'Please analyze the image above.',
          },
        },
      ]);
    default:
      return _promptMessages(const <Object?>[
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'text',
            'text': 'This is a simple prompt for testing.',
          },
        },
      ]);
  }
}

Map<String, Object?> _promptMessages(List<Object?> messages) =>
    <String, Object?>{'messages': messages};
