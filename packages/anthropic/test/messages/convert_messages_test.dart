import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

/// 把单条 user 消息转换后取出唯一 user 消息的 content 数组。
List<Map<String, Object?>> _userContent(UserMessage message) {
  final result = convertToAnthropicMessages(
    prompt: <LanguageModelMessage>[message],
    sendReasoning: false,
  );
  return (result.messages.single['content'] as List<Object?>)
      .cast<Map<String, Object?>>();
}

/// 把单条 tool 消息转换后取出唯一 user 消息的 content 数组。
List<Map<String, Object?>> _toolContent(ToolMessage message) {
  final result = convertToAnthropicMessages(
    prompt: <LanguageModelMessage>[message],
    sendReasoning: false,
  );
  return (result.messages.single['content'] as List<Object?>)
      .cast<Map<String, Object?>>();
}

void main() {
  group('convertToAnthropicMessages — 分块与 system', () {
    test('返回形状:system / messages / betas / warnings', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const SystemMessage('be nice'),
        ],
        sendReasoning: false,
      );
      expect(result, isA<AnthropicPromptResult>());
      expect(result.system, isA<List<Map<String, Object?>>?>());
      expect(result.messages, isA<List<Map<String, Object?>>>());
      expect(result.betas, isA<Set<String>>());
      expect(result.warnings, isA<List<Warning>>());
    });

    test('首个 system 块进顶层,无 cache_control 时不出现该字段', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const SystemMessage('be nice'),
        ],
        sendReasoning: false,
      );
      expect(result.system, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'be nice'},
      ]);
      // 无 cache_control 时 key 不出现(对应上游 undefined 序列化消失)。
      expect(result.system!.single.containsKey('cache_control'), isFalse);
      expect(result.messages, isEmpty);
      expect(result.betas, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('连续 system 消息合并进同一顶层块', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const SystemMessage('a'),
          const SystemMessage('b'),
          const UserMessage(<UserContentPart>[TextPart('hello')]),
        ],
        sendReasoning: false,
      );
      expect(result.system, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'a'},
        <String, Object?>{'type': 'text', 'text': 'b'},
      ]);
    });

    test('中段 system 块 → role:system 消息 + mid-conversation beta', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const SystemMessage('s1'),
          const UserMessage(<UserContentPart>[TextPart('u')]),
          const SystemMessage('s2'),
        ],
        sendReasoning: false,
      );
      expect(result.system, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 's1'},
      ]);
      expect(result.messages, hasLength(2));
      expect(result.messages[0]['role'], 'user');
      expect(result.messages[1], <String, Object?>{
        'role': 'system',
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 's2'},
        ],
      });
      expect(result.betas, contains('mid-conversation-system-2026-04-07'));
    });

    test('system 消息级 cache_control 注入顶层块', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const SystemMessage(
            'x',
            providerOptions: <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'cacheControl': <String, Object?>{'type': 'ephemeral'},
              },
            },
          ),
        ],
        sendReasoning: false,
      );
      expect(result.system, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': 'x',
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        },
      ]);
    });

    test('user 与 tool 消息归同一 user 块,产出一条 user 消息', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[TextPart('q')]),
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'call-1',
              toolName: 'calc',
              output: ToolResultText('42'),
            ),
          ]),
          const UserMessage(<UserContentPart>[TextPart('q2')]),
        ],
        sendReasoning: false,
      );
      expect(result.messages, hasLength(1));
      final message = result.messages.single;
      expect(message['role'], 'user');
      final content = message['content'] as List<Object?>;
      expect(content, hasLength(3));
      expect((content[0] as Map<String, Object?>)['type'], 'text');
      expect((content[0] as Map<String, Object?>)['text'], 'q');
      expect((content[1] as Map<String, Object?>)['type'], 'tool_result');
      expect((content[2] as Map<String, Object?>)['type'], 'text');
      expect((content[2] as Map<String, Object?>)['text'], 'q2');
    });

    test('连续 assistant 消息合并为一条 assistant 消息', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[TextPart('a1')]),
          const AssistantMessage(<AssistantContentPart>[TextPart('a2')]),
        ],
        sendReasoning: false,
      );
      expect(result.messages, hasLength(1));
      final message = result.messages.single;
      expect(message['role'], 'assistant');
      final content = message['content'] as List<Object?>;
      expect(content, hasLength(2));
      expect((content[0] as Map<String, Object?>)['text'], 'a1');
      expect((content[1] as Map<String, Object?>)['text'], 'a2');
    });

    test('角色交替 user → assistant → user 产出 3 条消息且顺序保持', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[TextPart('u1')]),
          const AssistantMessage(<AssistantContentPart>[TextPart('a1')]),
          const UserMessage(<UserContentPart>[TextPart('u2')]),
        ],
        sendReasoning: false,
      );
      expect(result.messages, hasLength(3));
      expect(result.messages[0]['role'], 'user');
      expect(result.messages[1]['role'], 'assistant');
      expect(result.messages[2]['role'], 'user');
    });
  });

  group('user 内容块', () {
    test('text part → text 块;part 级 cacheControl 注入', () {
      expect(
        _userContent(const UserMessage(<UserContentPart>[TextPart('hi')])),
        <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 'hi'},
        ],
      );
      expect(
        _userContent(
          const UserMessage(<UserContentPart>[
            TextPart(
              'hi',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ),
        <Map<String, Object?>>[
          <String, Object?>{
            'type': 'text',
            'text': 'hi',
            'cache_control': <String, Object?>{'type': 'ephemeral'},
          },
        ],
      );
    });

    test('cache_control 回退:消息级只落在最后一个 part', () {
      final content = _userContent(
        const UserMessage(
          <UserContentPart>[TextPart('a'), TextPart('b')],
          providerOptions: <String, Map<String, Object?>>{
            'anthropic': <String, Object?>{
              'cacheControl': <String, Object?>{'type': 'ephemeral'},
            },
          },
        ),
      );
      expect(content[0].containsKey('cache_control'), isFalse);
      expect(
        content[1]['cache_control'],
        <String, Object?>{'type': 'ephemeral'},
      );
    });

    test('cache_control 回退:part 级与消息级同存时 part 级优先', () {
      final content = _userContent(
        const UserMessage(
          <UserContentPart>[
            TextPart('a'),
            TextPart(
              'b',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{
                    'type': 'ephemeral',
                    'ttl': '1h',
                  },
                },
              },
            ),
          ],
          providerOptions: <String, Map<String, Object?>>{
            'anthropic': <String, Object?>{
              'cacheControl': <String, Object?>{'type': 'ephemeral'},
            },
          },
        ),
      );
      expect(
        content[1]['cache_control'],
        <String, Object?>{'type': 'ephemeral', 'ttl': '1h'},
      );
    });

    test('image / bytes → base64 source', () {
      final content = _userContent(
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBytes(Uint8List.fromList(<int>[1, 2, 3])),
            mediaType: 'image/png',
          ),
        ]),
      );
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AQID',
          },
        },
      ]);
    });

    test('image / base64 → base64 source 同形', () {
      final content = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(data: FileDataBase64('AQID'), mediaType: 'image/png'),
        ]),
      );
      expect(content.single['source'], <String, Object?>{
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'AQID',
      });
    });

    test('image / url → url source', () {
      final content = _userContent(
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataUrl(Uri.parse('https://e.com/i.png')),
            mediaType: 'image/jpeg',
          ),
        ]),
      );
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'url',
            'url': 'https://e.com/i.png',
          },
        },
      ]);
    });

    test('PDF / base64 → document + title + pdfs beta', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataBase64('JVBERi0='),
              mediaType: 'application/pdf',
              filename: 'a.pdf',
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': 'JVBERi0=',
          },
          'title': 'a.pdf',
        },
      ]);
      expect(result.betas, contains('pdfs-2024-09-25'));
    });

    test('PDF / url → url source + pdfs beta', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataUrl(Uri.parse('https://e.com/d.pdf')),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['type'], 'document');
      expect(content.single['source'], <String, Object?>{
        'type': 'url',
        'url': 'https://e.com/d.pdf',
      });
      expect(result.betas, contains('pdfs-2024-09-25'));
    });

    test('document providerOptions:title 覆盖 filename + context + citations',
        () {
      final content = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBase64('JVBERi0='),
            mediaType: 'application/pdf',
            filename: 'a.pdf',
            providerOptions: <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'title': 'T',
                'context': 'C',
                'citations': <String, Object?>{'enabled': true},
              },
            },
          ),
        ]),
      );
      final block = content.single;
      expect(block['title'], 'T');
      expect(block['context'], 'C');
      expect(block['citations'], <String, Object?>{'enabled': true});
    });

    test('document providerOptions:citations enabled=false / 缺省 → 无字段', () {
      final withFalse = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBase64('JVBERi0='),
            mediaType: 'application/pdf',
            providerOptions: <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'citations': <String, Object?>{'enabled': false},
              },
            },
          ),
        ]),
      );
      expect(withFalse.single.containsKey('citations'), isFalse);
      expect(withFalse.single.containsKey('context'), isFalse);

      final withDefault = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBase64('JVBERi0='),
            mediaType: 'application/pdf',
          ),
        ]),
      );
      expect(withDefault.single.containsKey('citations'), isFalse);
      expect(withDefault.single.containsKey('context'), isFalse);
      // 无 filename 且无 title → 无 title 字段。
      expect(withDefault.single.containsKey('title'), isFalse);
    });

    test('text/plain / bytes → text source(UTF-8 解码)', () {
      final content = _userContent(
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBytes(utf8.encode('hello')),
            mediaType: 'text/plain',
          ),
        ]),
      );
      expect(content.single, <String, Object?>{
        'type': 'document',
        'source': <String, Object?>{
          'type': 'text',
          'media_type': 'text/plain',
          'data': 'hello',
        },
      });
    });

    test('text/plain / base64 → 解码回字符串', () {
      final content = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(data: FileDataBase64('aGVsbG8='), mediaType: 'text/plain'),
        ]),
      );
      expect(
        (content.single['source'] as Map<String, Object?>)['data'],
        'hello',
      );
    });

    test('text/plain / url → url source', () {
      final content = _userContent(
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataUrl(Uri.parse('https://e.com/f.txt')),
            mediaType: 'text/plain',
          ),
        ]),
      );
      expect(content.single['type'], 'document');
      expect(content.single['source'], <String, Object?>{
        'type': 'url',
        'url': 'https://e.com/f.txt',
      });
    });

    test('FileDataText → text source + filename 作 title', () {
      final content = _userContent(
        const UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataText('raw text'),
            mediaType: 'text/plain',
            filename: 'f.txt',
          ),
        ]),
      );
      expect(content.single, <String, Object?>{
        'type': 'document',
        'source': <String, Object?>{
          'type': 'text',
          'media_type': 'text/plain',
          'data': 'raw text',
        },
        'title': 'f.txt',
      });
    });

    test('顶级 mediaType image + PNG 魔数 → 探测出 image/png', () {
      final content = _userContent(
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBytes(
              Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]),
            ),
            mediaType: 'image',
          ),
        ]),
      );
      expect(content.single['type'], 'image');
      expect(
        (content.single['source'] as Map<String, Object?>)['media_type'],
        'image/png',
      );
    });

    test('顶级 mediaType application + %PDF- 魔数 → document PDF 路径', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataBytes(
                Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2d]),
              ),
              mediaType: 'application',
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['type'], 'document');
      expect(
        (content.single['source'] as Map<String, Object?>)['media_type'],
        'application/pdf',
      );
      expect(result.betas, contains('pdfs-2024-09-25'));
    });

    test('不支持的 mediaType → UnsupportedFunctionalityError', () {
      expect(
        () => _userContent(
          UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataBytes(Uint8List.fromList(<int>[1])),
              mediaType: 'audio/mp3',
            ),
          ]),
        ),
        throwsA(
          isA<UnsupportedFunctionalityError>().having(
            (e) => e.functionality,
            'functionality',
            contains('media type: audio/mp3'),
          ),
        ),
      );
    });

    test('PDF FileDataReference → document file source + metadata + beta', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataReference(<String, String>{
                'anthropic': 'file_pdf',
              }),
              mediaType: 'application/pdf',
              filename: 'fallback.pdf',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'title': 'Report',
                  'context': 'Quarterly results',
                  'citations': <String, Object?>{'enabled': true},
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'file',
            'file_id': 'file_pdf',
          },
          'title': 'Report',
          'context': 'Quarterly results',
          'citations': <String, Object?>{'enabled': true},
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        },
      ]);
      expect(result.betas, <String>{'files-api-2025-04-14'});
    });

    test('image FileDataReference → image file source + cache + beta', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataReference(<String, String>{
                'anthropic': 'file_img',
              }),
              mediaType: 'image/png',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'file',
            'file_id': 'file_img',
          },
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        },
      ]);
      expect(result.betas, <String>{'files-api-2025-04-14'});
    });

    test('containerUpload FileDataReference → bare container_upload + beta',
        () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataReference(<String, String>{
                'anthropic': 'file_csv',
              }),
              mediaType: 'text/csv',
              filename: 'data.csv',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'containerUpload': true,
                  'title': 'Data',
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        <String, Object?>{
          'type': 'container_upload',
          'file_id': 'file_csv',
        },
      ]);
      expect(result.betas, <String>{'files-api-2025-04-14'});
    });

    test('containerUpload cache option does not consume cache breakpoints', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataReference(<String, String>{
                'anthropic': 'file_csv',
              }),
              mediaType: 'text/csv',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'containerUpload': true,
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
            TextPart(
              'one',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
            TextPart(
              'two',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
            TextPart(
              'three',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
            TextPart(
              'four',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(5));
      expect(content.first, <String, Object?>{
        'type': 'container_upload',
        'file_id': 'file_csv',
      });
      for (final block in content.skip(1)) {
        expect(
          block['cache_control'],
          <String, Object?>{'type': 'ephemeral'},
        );
      }
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (warning) => warning.feature == 'cacheControl breakpoint limit',
            ),
        isEmpty,
      );
    });

    test('FileDataReference 缺 anthropic 键 → NoSuchProviderReferenceError', () {
      expect(
        () => _userContent(
          const UserMessage(<UserContentPart>[
            FilePart(
              data: FileDataReference(<String, String>{
                'openai': 'file_1',
              }),
              mediaType: 'application/pdf',
            ),
          ]),
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>().having(
            (error) => error.provider,
            'provider',
            'anthropic',
          ),
        ),
      );
    });
  });

  group('tool_result', () {
    test('外层形状:text output → content 字符串,无 is_error 字段', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'call_1',
            toolName: 't',
            output: ToolResultText('ok'),
          ),
        ]),
      );
      expect(content.single, <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': 'call_1',
        'content': 'ok',
      });
      expect(content.single.containsKey('is_error'), isFalse);
    });

    test(
        'client 工具(computer)结果 → 普通 tool_result 块(Task 15,'
        '报告 08 §5:回流无专用分支)', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'tu_1',
            toolName: 'computer',
            output: ToolResultText('screenshot taken'),
          ),
        ]),
      );
      expect(content.single, <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': 'tu_1',
        'content': 'screenshot taken',
      });
      expect(content.single.containsKey('is_error'), isFalse);
    });

    test('error-text output → content 字符串 + is_error: true', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultErrorText('bad'),
          ),
        ]),
      );
      expect(content.single['content'], 'bad');
      expect(content.single['is_error'], isTrue);
    });

    test('json output → jsonEncode 字符串,无 is_error', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultJson(<String, Object?>{'a': 1}),
          ),
        ]),
      );
      expect(content.single['content'], '{"a":1}');
      expect(content.single.containsKey('is_error'), isFalse);
    });

    test('error-json output → jsonEncode 字符串 + is_error: true', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultErrorJson(<String, Object?>{'e': 2}),
          ),
        ]),
      );
      expect(content.single['content'], '{"e":2}');
      expect(content.single['is_error'], isTrue);
    });

    test('execution-denied 带 reason → content 为 reason,无 is_error', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultExecutionDenied(reason: 'no'),
          ),
        ]),
      );
      expect(content.single['content'], 'no');
      expect(content.single.containsKey('is_error'), isFalse);
    });

    test('execution-denied 无 reason → 默认拒绝文案', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultExecutionDenied(),
          ),
        ]),
      );
      expect(content.single['content'], 'Tool call execution denied.');
    });

    test('content 型 output → text / image(base64)块数组', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultContentOutput(<ToolResultContentItem>[
              ToolResultTextItem('t'),
              ToolResultFileItem(
                data: FileDataBase64('AQID'),
                mediaType: 'image/png',
              ),
            ]),
          ),
        ]),
      );
      expect(content.single['content'], <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 't'},
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AQID',
          },
        },
      ]);
    });

    test('file item / url + image → image url source', () {
      final content = _toolContent(
        ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultContentOutput(<ToolResultContentItem>[
              ToolResultFileItem(
                data: FileDataUrl(Uri.parse('https://e.com/i.png')),
                mediaType: 'image/png',
              ),
            ]),
          ),
        ]),
      );
      expect(content.single['content'], <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'url',
            'url': 'https://e.com/i.png',
          },
        },
      ]);
    });

    test('file item / url + 非 image → document url source', () {
      final content = _toolContent(
        ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultContentOutput(<ToolResultContentItem>[
              ToolResultFileItem(
                data: FileDataUrl(Uri.parse('https://e.com/f.pdf')),
                mediaType: 'application/pdf',
              ),
            ]),
          ),
        ]),
      );
      expect(content.single['content'], <Map<String, Object?>>[
        <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'url',
            'url': 'https://e.com/f.pdf',
          },
        },
      ]);
    });

    test('file item / data + application/pdf → document base64 + pdfs beta',
        () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultFileItem(
                  data: FileDataBase64('JVBERi0='),
                  mediaType: 'application/pdf',
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['content'], <Map<String, Object?>>[
        <String, Object?>{
          'type': 'document',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': 'JVBERi0=',
          },
        },
      ]);
      expect(result.betas, contains('pdfs-2024-09-25'));
    });

    test('file item / 顶级 mediaType image + PNG 魔数 → 探测出 image/png', () {
      final content = _toolContent(
        ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultContentOutput(<ToolResultContentItem>[
              ToolResultFileItem(
                data: FileDataBytes(
                  Uint8List.fromList(
                    <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a],
                  ),
                ),
                mediaType: 'image',
              ),
            ]),
          ),
        ]),
      );
      final items = (content.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items.single['type'], 'image');
      expect(
        (items.single['source'] as Map<String, Object?>)['media_type'],
        'image/png',
      );
    });

    test('file item / 顶级 mediaType application + %PDF- 魔数 → document PDF(不误丢)',
        () {
      // 回归:顶级-only 'application' 需探测出 application/pdf,而非按裸字符串
      // == 'application/pdf' 误判丢弃(codex PR #60 复审)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultFileItem(
                  data: FileDataBytes(
                    Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2d]),
                  ),
                  mediaType: 'application',
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final items = ((result.messages.single['content'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items.single['type'], 'document');
      expect(
        (items.single['source'] as Map<String, Object?>)['media_type'],
        'application/pdf',
      );
      expect(result.betas, contains('pdfs-2024-09-25'));
    });

    test('file item / data + 非 image 非 pdf mediaType → 过滤 + warning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultTextItem('kept'),
                ToolResultFileItem(
                  data: FileDataBase64('AQID'),
                  mediaType: 'audio/mp3',
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['content'], <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'kept'},
      ]);
      expect(
        result.warnings,
        contains(
          isA<UnsupportedWarning>()
              .having(
                (w) => w.details,
                'details',
                contains('unsupported tool content part type'),
              )
              .having((w) => w.details, 'details', contains('audio/mp3')),
        ),
      );
    });

    test('file item / FileDataText → 过滤 + warning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultFileItem(
                  data: FileDataText('raw'),
                  mediaType: 'text/plain',
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['content'], isEmpty);
      expect(
        result.warnings,
        contains(
          isA<UnsupportedWarning>().having(
            (w) => w.details,
            'details',
            contains('unsupported tool content part type'),
          ),
        ),
      );
    });

    test('file item / FileDataReference → 过滤 + warning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultFileItem(
                  data: FileDataReference(<String, String>{
                    'anthropic': 'file_1',
                  }),
                  mediaType: 'application/pdf',
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['content'], isEmpty);
      expect(result.betas, isEmpty);
      expect(
        result.warnings,
        contains(
          isA<UnsupportedWarning>().having(
            (w) => w.details,
            'details',
            contains('data type: reference'),
          ),
        ),
      );
    });

    test('ToolResultCustomItem → 过滤 + warning(spec 疑点 #8)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultContentOutput(<ToolResultContentItem>[
                ToolResultCustomItem(
                  providerOptions: <String, Map<String, Object?>>{
                    'anthropic': <String, Object?>{'type': 'tool-reference'},
                  },
                ),
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['content'], isEmpty);
      expect(
        result.warnings,
        contains(
          isA<UnsupportedWarning>().having(
            (w) => w.details,
            'details',
            contains('unsupported custom tool content part'),
          ),
        ),
      );
    });

    test('tool-approval-response 跳过,不产出块也不告警', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolApprovalResponsePart(approvalId: 'a', approved: true),
            ToolResultPart(
              toolCallId: 'c',
              toolName: 't',
              output: ToolResultText('ok'),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'tool_result');
      expect(result.warnings, isEmpty);
    });

    test('cache_control part 级优先', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultText('ok'),
            providerOptions: <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'cacheControl': <String, Object?>{'type': 'ephemeral'},
              },
            },
          ),
        ]),
      );
      expect(content.single['cache_control'], <String, Object?>{
        'type': 'ephemeral',
      });
    });

    test('cache_control output 级回退(text output 的 providerOptions)', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultText(
              'ok',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ),
        ]),
      );
      expect(content.single['cache_control'], <String, Object?>{
        'type': 'ephemeral',
      });
    });

    test('cache_control output 级:content output 取第一个非 null 元素', () {
      final content = _toolContent(
        const ToolMessage(<ToolContentPart>[
          ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultContentOutput(<ToolResultContentItem>[
              ToolResultTextItem('a'),
              ToolResultTextItem(
                'b',
                providerOptions: <String, Map<String, Object?>>{
                  'anthropic': <String, Object?>{
                    'cacheControl': <String, Object?>{
                      'type': 'ephemeral',
                      'ttl': '1h',
                    },
                  },
                },
              ),
              ToolResultTextItem(
                'c',
                providerOptions: <String, Map<String, Object?>>{
                  'anthropic': <String, Object?>{
                    'cacheControl': <String, Object?>{'type': 'ephemeral'},
                  },
                },
              ),
            ]),
          ),
        ]),
      );
      expect(content.single['cache_control'], <String, Object?>{
        'type': 'ephemeral',
        'ttl': '1h',
      });
    });

    test('cache_control 消息级回退仅作用于最后一个 part', () {
      final content = _toolContent(
        const ToolMessage(
          <ToolContentPart>[
            ToolResultPart(
              toolCallId: 'c1',
              toolName: 't',
              output: ToolResultText('one'),
            ),
            ToolResultPart(
              toolCallId: 'c2',
              toolName: 't',
              output: ToolResultText('two'),
            ),
          ],
          providerOptions: <String, Map<String, Object?>>{
            'anthropic': <String, Object?>{
              'cacheControl': <String, Object?>{'type': 'ephemeral'},
            },
          },
        ),
      );
      expect(content, hasLength(2));
      expect(content[0].containsKey('cache_control'), isFalse);
      expect(content[1]['cache_control'], <String, Object?>{
        'type': 'ephemeral',
      });
    });
  });

  group('assistant 内容块', () {
    test('末位 text part 尾随空白被 trim(最后块+最后消息+最后 part)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[TextPart('q')]),
          const AssistantMessage(<AssistantContentPart>[
            TextPart('answer  '),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages[1]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'text',
        'text': 'answer',
      });
    });

    test('assistant 块后还有 user 消息时末位 text 不 trim', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('answer  '),
          ]),
          const UserMessage(<UserContentPart>[TextPart('next')]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages[0]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['text'], 'answer  ');
    });

    test('同消息内非末位 text part 不 trim,末位 part 才 trim', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('a  '),
            TextPart('b  '),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['text'], 'a  ');
      expect(content[1]['text'], 'b');
    });

    test('末位 part 被跳过时,真正落地的末位 text 仍被 trim(codex PR #60 复审)', () {
      // 回归:末位 ReasoningPart 因 sendReasoning:false 被丢弃,前面的 text 才是
      // 真正落地的末位块——按原始位置判定会漏 trim 而产生 400。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('answer  '),
            ReasoningPart('dropped'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['type'], 'text');
      expect(content.single['text'], 'answer');
    });

    test('末位为 tool_use(重排后)时前面的 text 不被过度 trim', () {
      // 重排后 tool_use 收尾,text 不是真正末位块 → 保留尾随空白(与上游位置
      // 语义一致,不过度 trim)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('answer  '),
            ToolCallPart(
              toolCallId: 'c1',
              toolName: 't',
              input: <String, Object?>{'x': 1},
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.last['type'], 'tool_use');
      final textBlock = content.firstWhere((b) => b['type'] == 'text');
      expect(textBlock['text'], 'answer  ');
    });

    test('末位 text 前导空白保留,仅去尾随(缩进 prefill 语义,codex PR #60 复审)', () {
      // API 约束仅针对 trailing whitespace(上游注释自证 :601-603);前导缩进
      // 是 prefill 语义的一部分,两端 trim 会改写用户数据。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('  indented code  '),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['text'], '  indented code');
    });

    test('全空白末位 text trim 后为空 → 丢弃该块(codex PR #60 复审)', () {
      // Anthropic 拒绝空 text 内容块;偏离点自洽收尾:trim 成空串的块直接丢弃。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('answer'),
            TextPart('   '),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['text'], 'answer');
    });

    test('assistant 消息仅含全空白 text → 整条消息被丢弃', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const UserMessage(<UserContentPart>[TextPart('q')]),
          const AssistantMessage(<AssistantContentPart>[TextPart('  ')]),
        ],
        sendReasoning: false,
      );
      // 空内容 assistant 消息不发出,仅剩 user 消息。
      expect(result.messages, hasLength(1));
      expect(result.messages.single['role'], 'user');
    });

    test('user 块内容全被跳过 → 整条消息被丢弃(与 assistant 对称)', () {
      // ToolMessage 仅含 tool-approval-response(转换器有意跳过)时,不发
      // {role:user, content:[]} 空消息(codex PR #60 复审)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const ToolMessage(<ToolContentPart>[
            ToolApprovalResponsePart(approvalId: 'a1', approved: true),
          ]),
          const AssistantMessage(<AssistantContentPart>[TextPart('done')]),
        ],
        sendReasoning: false,
      );
      expect(result.messages, hasLength(1));
      expect(result.messages.single['role'], 'assistant');
    });

    test('compaction text part → compaction 块重建(content 直入,warnings 为空)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart(
              'sum',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{'type': 'compaction'},
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'compaction',
        'content': 'sum',
      });
      expect(result.warnings, isEmpty);
    });

    test('compaction 末位不 trim(trim 只作用于 text 型末位块)+ cache_control 沿 part 处理',
        () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart(
              'summary with trailing space ',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'type': 'compaction',
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'compaction',
        'content': 'summary with trailing space ',
        'cache_control': <String, Object?>{'type': 'ephemeral'},
      });
    });

    test('sendReasoning=false 时 reasoning part 丢弃 + OtherWarning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart('think'),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'text');
      expect(
        result.warnings,
        contains(
          const OtherWarning(
            'sending reasoning content is disabled for this model',
          ),
        ),
      );
    });

    test('signature reasoning → thinking 块,无 cache_control 字段', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart(
              'think',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{'signature': 'sig_x'},
              },
            ),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'thinking',
        'thinking': 'think',
        'signature': 'sig_x',
      });
      expect(content.single.containsKey('cache_control'), isFalse);
    });

    test('thinking 块 cache_control 被拒:warning + 不占计数', () {
      final validator = CacheControlValidator();
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart(
              'think',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'signature': 'sig_x',
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
          // 后续 4 个 breakpoint:若 thinking 占了计数,第 4 个会超限。
          for (var i = 0; i < 4; i++)
            const UserMessage(<UserContentPart>[
              TextPart(
                'u',
                providerOptions: <String, Map<String, Object?>>{
                  'anthropic': <String, Object?>{
                    'cacheControl': <String, Object?>{'type': 'ephemeral'},
                  },
                },
              ),
            ]),
        ],
        sendReasoning: true,
        cacheControlValidator: validator,
      );
      final thinkingContent = (result.messages[0]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(thinkingContent.single.containsKey('cache_control'), isFalse);
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains('thinking block'),
            ),
        isNotEmpty,
      );
      // 不占计数:后面 4 个 user breakpoint 全部生效且无超限 warning。
      final userContent = (result.messages[1]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      for (final block in userContent) {
        expect(block['cache_control'], <String, Object?>{'type': 'ephemeral'});
      }
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => w.feature == 'cacheControl breakpoint limit',
            ),
        isEmpty,
      );
    });

    test('redactedData → redacted_thinking 块,不带 thinking 文本', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart(
              'ignored',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{'redactedData': 'redacted_x'},
              },
            ),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'redacted_thinking',
        'data': 'redacted_x',
      });
    });

    test('signature 与 redactedData 同存时 signature 优先', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart(
              'think',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'signature': 'sig_x',
                  'redactedData': 'redacted_x',
                },
              },
            ),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single['type'], 'thinking');
      expect(content.single['signature'], 'sig_x');
    });

    test('无 metadata 的 reasoning part 丢弃 + OtherWarning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ReasoningPart('t'),
            TextPart('x'),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'text');
      expect(
        result.warnings,
        contains(const OtherWarning('unsupported reasoning metadata')),
      );
    });

    test('客户端 tool-call → tool_use 块,可带 part 级 cache_control', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'tc1',
              toolName: 'get_weather',
              input: <String, Object?>{'city': 'SF'},
            ),
            ToolCallPart(
              toolCallId: 'tc2',
              toolName: 'get_time',
              input: <String, Object?>{},
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'cacheControl': <String, Object?>{'type': 'ephemeral'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0], <String, Object?>{
        'type': 'tool_use',
        'id': 'tc1',
        'name': 'get_weather',
        'input': <String, Object?>{'city': 'SF'},
      });
      expect(content[1]['cache_control'], <String, Object?>{
        'type': 'ephemeral',
      });
    });

    test(
        'client 工具(computer)非 providerExecuted → 普通 tool_use 块'
        '(Task 15,报告 08 §5:非 providerExecuted 走普通路径)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'tu_1',
              toolName: 'computer',
              input: <String, Object?>{'action': 'screenshot'},
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'tool_use',
        'id': 'tu_1',
        'name': 'computer',
        'input': <String, Object?>{'action': 'screenshot'},
      });
    });

    test('tool_use 非 object input 包装为 rawInvalidInput', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(toolCallId: 'a', toolName: 't', input: 'raw text'),
            ToolCallPart(
              toolCallId: 'b',
              toolName: 't',
              input: <Object?>[1, 2],
            ),
            ToolCallPart(toolCallId: 'c', toolName: 't', input: null),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['input'], <String, Object?>{
        'rawInvalidInput': 'raw text',
      });
      expect(content[1]['input'], <String, Object?>{
        'rawInvalidInput': <Object?>[1, 2],
      });
      expect(content[2]['input'], <String, Object?>{'rawInvalidInput': null});
    });

    test('caller 透传:direct / code_execution(snake_case)/ 不识别', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'a',
              toolName: 't',
              input: <String, Object?>{},
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'caller': <String, Object?>{'type': 'direct'},
                },
              },
            ),
            ToolCallPart(
              toolCallId: 'b',
              toolName: 't',
              input: <String, Object?>{},
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'caller': <String, Object?>{
                    'type': 'code_execution_20250825',
                    'toolId': 'srvtoolu_1',
                  },
                },
              },
            ),
            ToolCallPart(
              toolCallId: 'c',
              toolName: 't',
              input: <String, Object?>{},
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{
                  'caller': <String, Object?>{'type': 'mystery'},
                },
              },
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['caller'], <String, Object?>{'type': 'direct'});
      expect(content[1]['caller'], <String, Object?>{
        'type': 'code_execution_20250825',
        'tool_id': 'srvtoolu_1',
      });
      expect(content[2].containsKey('caller'), isFalse);
    });

    test('providerExecuted tool-call 丢弃 + UnsupportedWarning(未知 server 工具)',
        () {
      // web_search/web_fetch 现已进入白名单(Task 9),故本用例改用未注册的
      // server 工具名 'computer' 以保持"未知 provider 工具丢弃"语义
      // (决策摘要 assertion 8,:771-776 同构)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srv1',
              toolName: 'computer',
              input: <String, Object?>{},
              providerExecuted: true,
            ),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'text');
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool call for tool computer '
                'is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('assistant 内 ToolResultPart 丢弃 + warning(未知 server 工具)', () {
      // 同上,改用未注册的 server 工具名 'computer'。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolResultPart(
              toolCallId: 'srv1',
              toolName: 'computer',
              output: ToolResultJson(<String, Object?>{'ok': true}),
            ),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'text');
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool result for tool computer '
                'is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('assistant 消息级 cache_control 回退仅作用于最后一个 part', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(
            <AssistantContentPart>[
              TextPart('a'),
              TextPart('b'),
            ],
            providerOptions: <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'cacheControl': <String, Object?>{'type': 'ephemeral'},
              },
            },
          ),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0].containsKey('cache_control'), isFalse);
      expect(content[1]['cache_control'], <String, Object?>{
        'type': 'ephemeral',
      });
    });

    test('assistant 位置的契约独有 part 一律丢弃 + UnsupportedWarning', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            FilePart(data: FileDataBase64('aGk='), mediaType: 'image/png'),
            ReasoningFilePart(
              data: FileDataBase64('aGk='),
              mediaType: 'application/octet-stream',
            ),
            CustomPart('ns.thing'),
            ToolApprovalRequestPart(approvalId: 'ap1', toolCallId: 'tc1'),
            TextPart('t'),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(1));
      expect(content.single['type'], 'text');
      for (final typeName in <String>[
        'FilePart',
        'ReasoningFilePart',
        'CustomPart',
        'ToolApprovalRequestPart',
      ]) {
        expect(
          result.warnings.whereType<UnsupportedWarning>().where(
                (w) =>
                    (w.details ?? '').contains(typeName) &&
                    (w.details ?? '').contains(
                      'in assistant message is not supported by '
                      'anthropic messages',
                    ),
              ),
          isNotEmpty,
          reason: 'missing warning for $typeName',
        );
      }
    });

    test('moveToolUseBlocksToEnd:tool_use 移到末尾', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'A',
              toolName: 't',
              input: <String, Object?>{},
            ),
            TextPart('B'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'B');
      expect(content[1]['type'], 'tool_use');
      expect(content[1]['id'], 'A');
    });

    test('moveToolUseBlocksToEnd:thinking 作段界,tool_use 各自移段尾', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            TextPart('A'),
            ToolCallPart(
              toolCallId: 'B',
              toolName: 't',
              input: <String, Object?>{},
            ),
            ReasoningPart(
              'C',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{'signature': 'sig_c'},
              },
            ),
            ToolCallPart(
              toolCallId: 'D',
              toolName: 't',
              input: <String, Object?>{},
            ),
            TextPart('E'),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        content
            .map(
              (block) => block['type'] == 'tool_use'
                  ? block['id']
                  : (block['text'] ?? block['thinking']),
            )
            .toList(),
        <Object?>['A', 'B', 'C', 'E', 'D'],
      );
      expect(content[1]['type'], 'tool_use');
      expect(content[2]['type'], 'thinking');
      expect(content[4]['type'], 'tool_use');
    });

    test('redacted_thinking 同样作段界', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'A',
              toolName: 't',
              input: <String, Object?>{},
            ),
            ReasoningPart(
              'ignored',
              providerOptions: <String, Map<String, Object?>>{
                'anthropic': <String, Object?>{'redactedData': 'r1'},
              },
            ),
            TextPart('B'),
          ]),
        ],
        sendReasoning: true,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['type'], 'tool_use');
      expect(content[1]['type'], 'redacted_thinking');
      expect(content[2]['type'], 'text');
    });

    test('多条 assistant 消息合并后统一重排', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'tc1',
              toolName: 't',
              input: <String, Object?>{},
            ),
          ]),
          const AssistantMessage(<AssistantContentPart>[TextPart('after')]),
        ],
        sendReasoning: false,
      );
      expect(result.messages, hasLength(1));
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'after');
      expect(content[1]['type'], 'tool_use');
    });
  });

  group('server 工具历史回传', () {
    test('server_tool_use 回传:input 原样不包装,不被重排', () {
      // 报告 07 §6.1 :739-750:input 原样透传,不经 _toAnthropicToolInput
      // 包装;moveToolUseBlocksToEnd 只挪 'tool_use',server_tool_use 保持原位
      // (决策摘要,:343)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        {
          'type': 'server_tool_use',
          'id': 'srvtoolu_1',
          'name': 'web_search',
          'input': <String, Object?>{'query': 'dart'},
        },
        {'type': 'text', 'text': 't'},
      ]);
    });

    test('web_search 结果回传(json):camel→snake 还原', () {
      // 报告 07 §6.2 :1097-1108。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              output: ToolResultJson(<Object?>[
                <String, Object?>{
                  'type': 'web_search_result',
                  'url': 'https://r.com',
                  'title': 'R',
                  'pageAge': null,
                  'encryptedContent': 'enc1',
                },
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          content.singleWhere((b) => b['type'] == 'web_search_tool_result');
      expect(resultBlock, <String, Object?>{
        'type': 'web_search_tool_result',
        'tool_use_id': 'srvtoolu_1',
        'content': <Object?>[
          <String, Object?>{
            'url': 'https://r.com',
            'title': 'R',
            'page_age': null,
            'encrypted_content': 'enc1',
            'type': 'web_search_result',
          },
        ],
      });
    });

    test('web_fetch 结果回传(json):retrieved_at/media_type 还原', () {
      // 报告 07 §6.2 :1034-1056。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              input: <String, Object?>{'url': 'https://d.com/a.txt'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              output: ToolResultJson(<String, Object?>{
                'type': 'web_fetch_result',
                'url': 'https://d.com/a.txt',
                'retrievedAt': '2026-07-07T00:00:00Z',
                'content': <String, Object?>{
                  'type': 'document',
                  'title': 'Doc A',
                  'source': <String, Object?>{
                    'type': 'text',
                    'mediaType': 'text/plain',
                    'data': 'hello',
                  },
                },
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          content.singleWhere((b) => b['type'] == 'web_fetch_tool_result');
      expect(resultBlock, <String, Object?>{
        'type': 'web_fetch_tool_result',
        'tool_use_id': 'srvtoolu_2',
        'content': <String, Object?>{
          'type': 'web_fetch_result',
          'url': 'https://d.com/a.txt',
          'retrieved_at': '2026-07-07T00:00:00Z',
          'content': <String, Object?>{
            'type': 'document',
            'title': 'Doc A',
            'source': <String, Object?>{
              'type': 'text',
              'media_type': 'text/plain',
              'data': 'hello',
            },
          },
        },
      });
    });

    test('web_search 结果回传(json):title 为 null 时按 nullable 放行', () {
      // 报告 07 §1.2 OutputSchema :62,title 为 string|null 且必填。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              output: ToolResultJson(<Object?>[
                <String, Object?>{
                  'type': 'web_search_result',
                  'url': 'https://r.com',
                  'title': null,
                  'pageAge': 'recent',
                  'encryptedContent': 'enc1',
                },
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          content.singleWhere((b) => b['type'] == 'web_search_tool_result');
      final items = (resultBlock['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items.single['title'], isNull);
    });

    test('web_search 结果回传(json):缺失 pageAge 抛出 TypeValidationError', () {
      // 报告 07 §1.2 OutputSchema :63,pageAge 必填(可空但不可缺失)。
      expect(
        () => convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            const AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'srvtoolu_1',
                toolName: 'web_search',
                input: <String, Object?>{'query': 'dart'},
                providerExecuted: true,
              ),
              ToolResultPart(
                toolCallId: 'srvtoolu_1',
                toolName: 'web_search',
                output: ToolResultJson(<Object?>[
                  <String, Object?>{
                    'type': 'web_search_result',
                    'url': 'https://r.com',
                    'title': 'R',
                    'encryptedContent': 'enc1',
                  },
                ]),
              ),
            ]),
          ],
          sendReasoning: false,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('web_fetch 结果回传(json):retrievedAt/content.title 为 null 时放行', () {
      // 报告 07 §1.4 OutputSchema :99/:102,均为 string|null 且必填。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              input: <String, Object?>{'url': 'https://d.com/a.txt'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              output: ToolResultJson(<String, Object?>{
                'type': 'web_fetch_result',
                'url': 'https://d.com/a.txt',
                'retrievedAt': null,
                'content': <String, Object?>{
                  'type': 'document',
                  'title': null,
                  'source': <String, Object?>{
                    'type': 'text',
                    'mediaType': 'text/plain',
                    'data': 'hello',
                  },
                },
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          content.singleWhere((b) => b['type'] == 'web_fetch_tool_result');
      final resultContent = resultBlock['content']! as Map<String, Object?>;
      expect(resultContent['retrieved_at'], isNull);
      final documentContent = resultContent['content']! as Map<String, Object?>;
      expect(documentContent['title'], isNull);
    });

    test('往返自洽:citations 缺席的解析产物可直接回放不抛(codex PR #61)', () {
      // 解析侧对 wire 无 citations 的成功结果不写 citations 键(缺席语义);
      // 该产物作为 ToolResultJson 原样回放必须通过 validator——防"成功
      // fetch 后续轮本地 TypeValidationError"回归。
      final parsedShapedResult = <String, Object?>{
        'type': 'web_fetch_result',
        'url': 'https://d.com/p.txt',
        'retrievedAt': '2026-07-07T00:00:00Z',
        'content': <String, Object?>{
          'type': 'document',
          'title': 'P',
          // 无 citations 键(解析侧缺席产物形状)。
          'source': <String, Object?>{
            'type': 'text',
            'mediaType': 'text/plain',
            'data': 'hello',
          },
        },
      };
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          AssistantMessage(<AssistantContentPart>[
            const ToolCallPart(
              toolCallId: 'srvtoolu_9',
              toolName: 'web_fetch',
              input: <String, Object?>{'url': 'https://d.com/p.txt'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_9',
              toolName: 'web_fetch',
              output: ToolResultJson(parsedShapedResult),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          content.singleWhere((b) => b['type'] == 'web_fetch_tool_result');
      final documentContent = ((resultBlock['content']!
          as Map<String, Object?>)['content']!) as Map<String, Object?>;
      expect(documentContent.containsKey('citations'), isFalse);
    });

    test('web_fetch 结果回传(json):缺失 retrievedAt 抛出 TypeValidationError', () {
      // 报告 07 §1.4 OutputSchema :102,retrievedAt 必填(可空但不可缺失)。
      expect(
        () => convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            const AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'srvtoolu_2',
                toolName: 'web_fetch',
                input: <String, Object?>{'url': 'https://d.com/a.txt'},
                providerExecuted: true,
              ),
              ToolResultPart(
                toolCallId: 'srvtoolu_2',
                toolName: 'web_fetch',
                output: ToolResultJson(<String, Object?>{
                  'type': 'web_fetch_result',
                  'url': 'https://d.com/a.txt',
                  'content': <String, Object?>{
                    'type': 'document',
                    'title': 'Doc A',
                    'source': <String, Object?>{
                      'type': 'text',
                      'mediaType': 'text/plain',
                      'data': 'hello',
                    },
                  },
                }),
              ),
            ]),
          ],
          sendReasoning: false,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('错误回传:errorCode 原样;缺失时兜底 unavailable', () {
      // 报告 07 §6.2 :1001-1015/:1064-1078,extractErrorValue ?? 'unavailable'。
      final withCode = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              output: ToolResultErrorJson(<String, Object?>{
                'errorCode': 'unavailable',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final withCodeContent =
          (withCode.messages.single['content'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        withCodeContent.singleWhere(
          (b) => b['type'] == 'web_search_tool_result',
        )['content'],
        <String, Object?>{
          'type': 'web_search_tool_result_error',
          'error_code': 'unavailable',
        },
      );

      // value 无 errorCode 字段 → 兜底 'unavailable';value 为字符串化 JSON
      // 也能提取(extractErrorValue 兼容字符串化 JSON 与对象)。
      final fallback = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              input: <String, Object?>{'url': 'https://d.com'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_2',
              toolName: 'web_fetch',
              output: ToolResultErrorJson('{"reason":"boom"}'),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final fallbackContent =
          (fallback.messages.single['content'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        fallbackContent.singleWhere(
          (b) => b['type'] == 'web_fetch_tool_result',
        )['content'],
        <String, Object?>{
          'type': 'web_fetch_tool_result_error',
          'error_code': 'unavailable',
        },
      );
    });

    test('偏离上游:未命中 server 侧调用的同名 function 结果不回放', () {
      // 决策摘要偏离项:toolCallId 集合匹配,而非上游的 toProviderToolName
      // 判定——用户同名 function tool 的结果维持既有 warning + 丢弃。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'fn1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
            ),
            ToolResultPart(
              toolCallId: 'fn1',
              toolName: 'web_search',
              output: ToolResultJson(<String, Object?>{'ok': true}),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        content.where((b) => b['type'] == 'web_search_tool_result'),
        isEmpty,
      );
      expect(content.singleWhere((b) => b['type'] == 'tool_use')['id'], 'fn1');
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool result for tool web_search '
                'is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('非 json/error-json 变体命中集合时 warning + 丢弃', () {
      // 报告 07 §6.2 :1017-1024 同构。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              output: ToolResultText('x'),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        content.where((b) => b['type'] == 'web_search_tool_result'),
        isEmpty,
      );
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool result for tool web_search '
                'is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('校验失败抛出(缺必填字段)', () {
      // 报告 07 §6.2 :1029-1032,validateTypes 抛。
      expect(
        () => convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            const AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'srvtoolu_1',
                toolName: 'web_search',
                input: <String, Object?>{'query': 'dart'},
                providerExecuted: true,
              ),
              ToolResultPart(
                toolCallId: 'srvtoolu_1',
                toolName: 'web_search',
                output: ToolResultJson(<Object?>[
                  <String, Object?>{'bogus': 1},
                ]),
              ),
            ]),
          ],
          sendReasoning: false,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('未知 server 工具维持既有 warning + 丢弃', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srv1',
              toolName: 'computer',
              input: <String, Object?>{},
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      // 唯一 part 被丢弃 → assistant content 全空 → 整条消息不发出
      // (与既有"空内容不发空消息"语义一致)。
      expect(result.messages, isEmpty);
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool call for tool computer '
                'is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('跨块回放:result 在下一个 assistant 块仍正确回放(codex PR #61 P1)', () {
      // deferred server-tool 续轮场景:call 在上一个 assistant 块,中间隔
      // user 消息,result 单独出现在下一个 assistant 块——prompt 级预扫描
      // 必须仍能配对,否则 fetched/search 历史在续轮被丢弃。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_x',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
          ]),
          const UserMessage(<UserContentPart>[TextPart('continue')]),
          const AssistantMessage(<AssistantContentPart>[
            ToolResultPart(
              toolCallId: 'srvtoolu_x',
              toolName: 'web_search',
              output: ToolResultJson(<Object?>[
                <String, Object?>{
                  'type': 'web_search_result',
                  'url': 'https://r.com',
                  'title': 'R',
                  'pageAge': null,
                  'encryptedContent': 'enc1',
                },
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      // 最后一条消息(第二个 assistant 块)应含回放的 web_search_tool_result。
      final lastContent = (result.messages.last['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final resultBlock =
          lastContent.singleWhere((b) => b['type'] == 'web_search_tool_result');
      expect(resultBlock['tool_use_id'], 'srvtoolu_x');
      // 无"provider executed tool result ... not supported"告警。
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains('provider executed tool'),
            ),
        isEmpty,
      );
    });

    test('乱序不敏感:ToolResultPart 排在配对 ToolCallPart 之前仍正确回放', () {
      // codex 计划复审补(预扫描语义):两遍扫描消除顺序敏感;块输出顺序照
      // part 原序,result 块在前、server_tool_use 块在后。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolResultPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              output: ToolResultJson(<Object?>[
                <String, Object?>{
                  'type': 'web_search_result',
                  'url': 'https://r.com',
                  'title': 'R',
                  'pageAge': null,
                  'encryptedContent': 'enc1',
                },
              ]),
            ),
            ToolCallPart(
              toolCallId: 'srvtoolu_1',
              toolName: 'web_search',
              input: <String, Object?>{'query': 'dart'},
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(2));
      expect(content[0]['type'], 'web_search_tool_result');
      expect(content[1]['type'], 'server_tool_use');
    });
  });

  group('code_execution / advisor 调用回放(报告 09 §5.1)', () {
    test('子工具形态 bash_code_execution:name=子工具名,input 原样含 type 键', () {
      // 报告 09 §5.1a(:701-717):子工具解码侧已归一为 'code_execution',
      // 回放靠 input.type 还原子工具 wire 名;type 键不剥离。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce1',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'bash_code_execution',
                'command': 'ls -la',
              },
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_ce1',
        'name': 'bash_code_execution',
        'input': <String, Object?>{
          'type': 'bash_code_execution',
          'command': 'ls -la',
        },
      });
    });

    test('text_editor_code_execution 形态:name=子工具名,input 原样含 type 键', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce2',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'text_editor_code_execution',
                'command': 'view',
                'path': '/a.py',
              },
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_ce2',
        'name': 'text_editor_code_execution',
        'input': <String, Object?>{
          'type': 'text_editor_code_execution',
          'command': 'view',
          'path': '/a.py',
        },
      });
    });

    test('programmatic-tool-call 形态:name=code_execution,type 键剥离', () {
      // 报告 09 §5.1b(:718-737):SDK 内部虚构 type,wire 上不存在,回放前
      // 剥离。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce3',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'programmatic-tool-call',
                'code': 'print(1)',
              },
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_ce3',
        'name': 'code_execution',
        'input': <String, Object?>{'code': 'print(1)'},
      });
    });

    test('20250522 无 type 形态:name=code_execution,input 原样', () {
      // 报告 09 §5.1c(:738-750):既非子工具名也非 programmatic 虚构 type,
      // input 原样直传。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce4',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'print(1)'},
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_ce4',
        'name': 'code_execution',
        'input': <String, Object?>{'code': 'print(1)'},
      });
    });

    test('advisor:input 恒强制为空 map,忽略 part.input', () {
      // 报告 09 §5.1e(:762-770):"The advisor server_tool_use.input is
      // always {}." 上游不读 part.input,pigcode 同样硬编码 {}。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_adv1',
              toolName: 'advisor',
              input: <String, Object?>{'model': 'should-be-ignored'},
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_adv1',
        'name': 'advisor',
        'input': <String, Object?>{},
      });
    });

    test('tool_search_tool_regex 回放不受集合扩容影响:input 原样(回归)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ts1',
              toolName: 'tool_search_tool_regex',
              input: <String, Object?>{'pattern': 'weather', 'limit': 10},
              providerExecuted: true,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.single, <String, Object?>{
        'type': 'server_tool_use',
        'id': 'srvtoolu_ts1',
        'name': 'tool_search_tool_regex',
        'input': <String, Object?>{'pattern': 'weather', 'limit': 10},
      });
    });
  });

  group('code_execution / tool_search / advisor 结果回放(报告 09 §5.2)', () {
    test('code_execution_result 成功:字段重建,return_code 保持 snake', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce1',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'print(1)'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce1',
              toolName: 'code_execution',
              output: ToolResultJson(<String, Object?>{
                'type': 'code_execution_result',
                'stdout': 'hi\n',
                'stderr': '',
                'return_code': 0,
                'content': <Object?>[],
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(block, <String, Object?>{
        'type': 'code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce1',
        'content': <String, Object?>{
          'type': 'code_execution_result',
          'stdout': 'hi\n',
          'stderr': '',
          'return_code': 0,
          'content': <Object?>[],
        },
      });
    });

    test('encrypted_code_execution_result 成功:content 省略时缺席键默认 []', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce2',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'print(1)'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce2',
              toolName: 'code_execution',
              output: ToolResultJson(<String, Object?>{
                'type': 'encrypted_code_execution_result',
                'encrypted_stdout': 'enc-blob',
                'stderr': '',
                'return_code': 0,
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(block, <String, Object?>{
        'type': 'code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce2',
        'content': <String, Object?>{
          'type': 'encrypted_code_execution_result',
          'encrypted_stdout': 'enc-blob',
          'stderr': '',
          'return_code': 0,
          'content': <Object?>[],
        },
      });
    });

    test('bash_code_execution_result 成功:content 原样透传', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce3',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'bash_code_execution',
                'command': 'ls',
              },
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce3',
              toolName: 'code_execution',
              output: ToolResultJson(<String, Object?>{
                'type': 'bash_code_execution_result',
                'content': <Object?>[
                  <String, Object?>{
                    'type': 'bash_code_execution_output',
                    'file_id': 'f1',
                  },
                ],
                'stdout': 'a.txt\n',
                'stderr': '',
                'return_code': 0,
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block = content
          .singleWhere((b) => b['type'] == 'bash_code_execution_tool_result');
      expect(block, <String, Object?>{
        'type': 'bash_code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce3',
        'content': <String, Object?>{
          'type': 'bash_code_execution_result',
          'content': <Object?>[
            <String, Object?>{
              'type': 'bash_code_execution_output',
              'file_id': 'f1',
            },
          ],
          'stdout': 'a.txt\n',
          'stderr': '',
          'return_code': 0,
        },
      });
    });

    test('未知具体 type:20250825 union 校验失败 → 抛错(不 warning 丢弃)', () {
      expect(
        () => convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            const AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'srvtoolu_ce9',
                toolName: 'code_execution',
                input: <String, Object?>{'code': 'x'},
                providerExecuted: true,
              ),
              ToolResultPart(
                toolCallId: 'srvtoolu_ce9',
                toolName: 'code_execution',
                output: ToolResultJson(<String, Object?>{
                  'type': 'bogus_execution_result',
                  'stdout': 'x',
                }),
              ),
            ]),
          ],
          sendReasoning: false,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test(
        'text_editor_code_execution_view_result 成功:content 原样透传含 '
        'null 字段', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce4',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'text_editor_code_execution',
                'command': 'view',
                'path': '/a.py',
              },
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce4',
              toolName: 'code_execution',
              output: ToolResultJson(<String, Object?>{
                'type': 'text_editor_code_execution_view_result',
                'content': 'print(1)\n',
                'file_type': 'text',
                'num_lines': null,
                'start_line': null,
                'total_lines': null,
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block = content.singleWhere(
          (b) => b['type'] == 'text_editor_code_execution_tool_result');
      expect(block, <String, Object?>{
        'type': 'text_editor_code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce4',
        'content': <String, Object?>{
          'type': 'text_editor_code_execution_view_result',
          'content': 'print(1)\n',
          'file_type': 'text',
          'num_lines': null,
          'start_line': null,
          'total_lines': null,
        },
      });
    });

    test(
        'code_execution_tool_result_error 错误:精确匹配落 '
        'code_execution_tool_result 块', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce5',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'x'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce5',
              toolName: 'code_execution',
              output: ToolResultErrorJson(<String, Object?>{
                'type': 'code_execution_tool_result_error',
                'errorCode': 'invalid_tool_input',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(block['content'], <String, Object?>{
        'type': 'code_execution_tool_result_error',
        'error_code': 'invalid_tool_input',
      });
    });

    test(
        '错误兜底变形(报告 09 §9.8):text_editor 错误的 error-json 形态回放'
        '变形为 bash_code_execution_tool_result 块', () {
      // errorInfo.type 非 'code_execution_tool_result_error' 时恒落 bash
      // 块——即使原始错误其实来自 text_editor 侧(上游 :870-879 现状,照抄)。
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce6',
              toolName: 'code_execution',
              input: <String, Object?>{
                'type': 'text_editor_code_execution',
                'command': 'view',
                'path': '/missing.py',
              },
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce6',
              toolName: 'code_execution',
              output: ToolResultErrorJson(<String, Object?>{
                'type': 'text_editor_code_execution_tool_result_error',
                'errorCode': 'file_not_found',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      // 关键断言:块类型是 bash_code_execution_tool_result,**不是**
      // text_editor_code_execution_tool_result。
      expect(
        content
            .any((b) => b['type'] == 'text_editor_code_execution_tool_result'),
        isFalse,
      );
      final block = content
          .singleWhere((b) => b['type'] == 'bash_code_execution_tool_result');
      expect(block, <String, Object?>{
        'type': 'bash_code_execution_tool_result',
        'tool_use_id': 'srvtoolu_ce6',
        'content': <String, Object?>{
          'type': 'bash_code_execution_tool_result_error',
          'error_code': 'file_not_found',
        },
      });
    });

    test("错误 errorCode 缺失兜底 'unknown'(区别于 web 工具的 'unavailable')", () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce7',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'x'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce7',
              toolName: 'code_execution',
              output: ToolResultErrorJson(
                <String, Object?>{'type': 'code_execution_tool_result_error'},
              ),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(
        (block['content']! as Map<String, Object?>)['error_code'],
        'unknown',
      );
    });

    test('错误载体为字符串化 JSON(ToolResultErrorText)时同样能解析', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ce8',
              toolName: 'code_execution',
              input: <String, Object?>{'code': 'x'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ce8',
              toolName: 'code_execution',
              output: ToolResultErrorText(
                '{"type":"code_execution_tool_result_error",'
                '"errorCode":"unavailable"}',
              ),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'code_execution_tool_result');
      expect(block['content'], <String, Object?>{
        'type': 'code_execution_tool_result_error',
        'error_code': 'unavailable',
      });
    });

    test(
        'tool_search 成功回放:tool_name 还原,wrapper type 不因 regex/bm25 '
        '而变', () {
      for (final searchName in [
        'tool_search_tool_regex',
        'tool_search_tool_bm25',
      ]) {
        final result = convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'srvtoolu_ts1',
                toolName: searchName,
                input: const <String, Object?>{'pattern': 'weather'},
                providerExecuted: true,
              ),
              const ToolResultPart(
                toolCallId: 'srvtoolu_ts1',
                toolName: 'tool_search_tool_regex',
                output: ToolResultJson(<Object?>[
                  <String, Object?>{
                    'type': 'tool_reference',
                    'toolName': 'get_temp_data',
                  },
                ]),
              ),
            ]),
          ],
          sendReasoning: false,
        );
        final content = (result.messages.single['content'] as List<Object?>)
            .cast<Map<String, Object?>>();
        final block =
            content.singleWhere((b) => b['type'] == 'tool_search_tool_result');
        expect(block, <String, Object?>{
          'type': 'tool_search_tool_result',
          'tool_use_id': 'srvtoolu_ts1',
          'content': <String, Object?>{
            'type': 'tool_search_tool_search_result',
            'tool_references': <Object?>[
              <String, Object?>{
                'type': 'tool_reference',
                'tool_name': 'get_temp_data',
              },
            ],
          },
        });
      }
    });

    test(
        'tool_search 错误结果(error-json)丢弃 + warning(报告 09 §9.7,往返'
        '不闭环)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_ts2',
              toolName: 'tool_search_tool_regex',
              input: <String, Object?>{'pattern': 'x'},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_ts2',
              toolName: 'tool_search_tool_regex',
              output: ToolResultErrorJson(<String, Object?>{
                'errorCode': 'invalid_tool_input',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        content.any((b) => b['type'] == 'tool_search_tool_result'),
        isFalse,
      );
      expect(
        result.warnings.whereType<UnsupportedWarning>().where(
              (w) => (w.details ?? '').contains(
                'provider executed tool result for tool '
                'tool_search_tool_regex is not supported',
              ),
            ),
        isNotEmpty,
      );
    });

    test('advisor_result 成功回放', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_adv1',
              toolName: 'advisor',
              input: <String, Object?>{},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_adv1',
              toolName: 'advisor',
              output: ToolResultJson(<String, Object?>{
                'type': 'advisor_result',
                'text': 'analysis text',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'advisor_tool_result');
      expect(block, <String, Object?>{
        'type': 'advisor_tool_result',
        'tool_use_id': 'srvtoolu_adv1',
        'content': <String, Object?>{
          'type': 'advisor_result',
          'text': 'analysis text',
        },
      });
    });

    test(
        'advisor_redacted_result verbatim 往返:encryptedContent→'
        'encrypted_content 原样回传(报告 09 §7.4 :2610-2658)', () {
      const blob = 'opaque-encrypted-blob-xyz';
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_adv2',
              toolName: 'advisor',
              input: <String, Object?>{},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_adv2',
              toolName: 'advisor',
              output: ToolResultJson(<String, Object?>{
                'type': 'advisor_redacted_result',
                'encryptedContent': blob,
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'advisor_tool_result');
      expect(block['content'], <String, Object?>{
        'type': 'advisor_redacted_result',
        'encrypted_content': blob,
      });
    });

    test('advisor 错误回放:errorCode→error_code', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'srvtoolu_adv3',
              toolName: 'advisor',
              input: <String, Object?>{},
              providerExecuted: true,
            ),
            ToolResultPart(
              toolCallId: 'srvtoolu_adv3',
              toolName: 'advisor',
              output: ToolResultErrorJson(<String, Object?>{
                'type': 'advisor_tool_result_error',
                'errorCode': 'max_uses_exceeded',
              }),
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final block =
          content.singleWhere((b) => b['type'] == 'advisor_tool_result');
      expect(block['content'], <String, Object?>{
        'type': 'advisor_tool_result_error',
        'error_code': 'max_uses_exceeded',
      });
    });
  });

  group('mcp 两块回放与块级作用域', () {
    // 解析侧(doGenerate/doStream)写入的 metadata 同形(T12 契约形态),
    // 直接作 ToolCallPart.providerOptions 输入即构成"解析 → 回放"往返。
    const mcpOptions = <String, Map<String, Object?>>{
      'anthropic': <String, Object?>{
        'type': 'mcp-tool-use',
        'serverName': 'echo-server',
      },
    };

    test('同块配对:mcp 两块重建;成功回放 warnings 为空(走向 B 锁修复)', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              input: <String, Object?>{'message': 'hello world'},
              providerExecuted: true,
              providerOptions: mcpOptions,
            ),
            ToolResultPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              output: ToolResultJson(<Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'Tool echo: hello world',
                },
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, <Map<String, Object?>>[
        {
          'type': 'mcp_tool_use',
          'id': 'mcptoolu_1',
          'name': 'echo',
          'input': <String, Object?>{'message': 'hello world'},
          'server_name': 'echo-server',
        },
        {
          'type': 'mcp_tool_result',
          'tool_use_id': 'mcptoolu_1',
          'is_error': false,
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': 'Tool echo: hello world',
            },
          ],
        },
      ]);
      // 走向 B(已拍板,报告 10 §4.4):成功回放不发上游 missing-break
      // 落穿产生的兜底 warning——warnings 必须为空,锁修复防回归。
      expect(result.warnings, isEmpty);
    });

    test('error-json 结果 → is_error: true', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              input: <String, Object?>{},
              providerExecuted: true,
              providerOptions: mcpOptions,
            ),
            ToolResultPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              output: ToolResultErrorJson(<Object?>[
                <String, Object?>{'type': 'text', 'text': 'echo failed'},
              ]),
            ),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content[1]['type'], 'mcp_tool_result');
      expect(content[1]['is_error'], isTrue);
      expect(result.warnings, isEmpty);
    });

    test('非 JSON output → output-type warning + 跳过不回放', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              input: <String, Object?>{},
              providerExecuted: true,
              providerOptions: mcpOptions,
            ),
            ToolResultPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              output: ToolResultText('plain text result'),
            ),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );

      final content = (result.messages.single['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content.where((b) => b['type'] == 'mcp_tool_result'), isEmpty);
      expect(
        result.warnings,
        contains(const OtherWarning(
          'provider executed tool result output type text for tool echo '
          'is not supported',
        )),
      );
    });

    test('serverName 缺失 → ArgumentError(server_name 必填)', () {
      expect(
        () => convertToAnthropicMessages(
          prompt: <LanguageModelMessage>[
            const AssistantMessage(<AssistantContentPart>[
              ToolCallPart(
                toolCallId: 'mcptoolu_1',
                toolName: 'echo',
                input: <String, Object?>{},
                providerExecuted: true,
                providerOptions: <String, Map<String, Object?>>{
                  'anthropic': <String, Object?>{'type': 'mcp-tool-use'},
                },
              ),
            ]),
          ],
          sendReasoning: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('块级作用域:跨 assistant 块同 id 结果不误判为 mcp_tool_result', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              input: <String, Object?>{},
              providerExecuted: true,
              providerOptions: mcpOptions,
            ),
          ]),
          const UserMessage(<UserContentPart>[TextPart('next')]),
          const AssistantMessage(<AssistantContentPart>[
            ToolResultPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              output: ToolResultJson(<Object?>['late']),
            ),
            TextPart('t'),
          ]),
        ],
        sendReasoning: false,
      );

      // 集合随块重建:第二个 assistant 块的同 id 结果不命中 → 落到既有
      // "未命中 server 侧调用集合" warning + 丢弃路径。
      final secondAssistant = (result.messages[2]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        secondAssistant.where((b) => b['type'] == 'mcp_tool_result'),
        isEmpty,
      );
      expect(secondAssistant.map((b) => b['type']).toList(), ['text']);
      expect(
        result.warnings,
        contains(const UnsupportedWarning(
          'provider executed tool result',
          details: 'provider executed tool result for tool echo '
              'is not supported. It will be ignored.',
        )),
      );
    });

    test('块级作用域:tool role 中同 id 结果仍序列化为普通 tool_result', () {
      final result = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          const AssistantMessage(<AssistantContentPart>[
            ToolCallPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              input: <String, Object?>{},
              providerExecuted: true,
              providerOptions: mcpOptions,
            ),
          ]),
          const ToolMessage(<ToolContentPart>[
            ToolResultPart(
              toolCallId: 'mcptoolu_1',
              toolName: 'echo',
              output: ToolResultText('echoed'),
            ),
          ]),
        ],
        sendReasoning: false,
      );

      // tool role 路径(_convertUserBlockContent)无 MCP 判定,不受影响。
      final toolContent = (result.messages[1]['content'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(toolContent.single, <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': 'mcptoolu_1',
        'content': 'echoed',
      });
    });
  });
}
