import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('convertToOpenAiCompatibleChatMessages — system', () {
    test('恒产出 role:system(无 systemMessageMode 概念)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [SystemMessage('be nice')],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {'role': 'system', 'content': 'be nice'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('消息级 providerOptions 按 providerOptionsName 键透传进请求体', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          const SystemMessage(
            'be nice',
            providerOptions: {
              'mycustom': {'cache_control': 'ephemeral'},
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages.single, {
        'role': 'system',
        'content': 'be nice',
        'cache_control': 'ephemeral',
      });
    });
  });

  group('convertToOpenAiCompatibleChatMessages — user', () {
    test('单 text part 走字符串快路径', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          UserMessage([TextPart('hello')]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test(
        '单 text 快路径同样展开消息级 providerOptions'
        '(codex PR#5 round-6:raw 快路径唯独丢消息级,主动补齐),'
        'part 级同键覆盖消息级', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          UserMessage(
            [
              TextPart(
                'hello',
                providerOptions: {
                  'mycustom': {'tier': 'part'},
                },
              ),
            ],
            providerOptions: {
              'mycustom': {'tier': 'message', 'cache_control': 'ephemeral'},
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {
          'role': 'user',
          'content': 'hello',
          'tier': 'part',
          'cache_control': 'ephemeral',
        },
      ]);
    });

    test('多 part 走数组形态,image 走 image_url(不含 openai 专属 detail 字段)', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage([
            const TextPart('describe this'),
            FilePart(data: FileDataBytes(bytes), mediaType: 'image/png'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = result.messages.single['content']! as List<Object?>;
      expect(content[0], {'type': 'text', 'text': 'describe this'});
      final imagePart = content[1]! as Map<String, Object?>;
      expect(imagePart['type'], 'image_url');
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/png;base64,AQID');
      expect(imageUrl.containsKey('detail'), isFalse);
    });

    test('image url 来源直接透传远程 URL', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.png')),
              mediaType: 'image/png',
            ),
            const TextPart('x'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = result.messages.single['content']! as List<Object?>;
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'https://example.com/a.png');
    });

    test('通用文本媒体类型(topLevel=text)转为 {type:text}(本包独有分支)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: const FileDataBase64('aGVsbG8='), // "hello"
              mediaType: 'text/csv',
            ),
            const TextPart('x'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = result.messages.single['content']! as List<Object?>;
      final textFilePart = content[0]! as Map<String, Object?>;
      expect(textFilePart, {'type': 'text', 'text': 'hello'});
    });

    test('文本媒体的 url 来源直接使用 URL 字符串作为 text', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.csv')),
              mediaType: 'text/csv',
            ),
            const TextPart('x'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = result.messages.single['content']! as List<Object?>;
      final textFilePart = content[0]! as Map<String, Object?>;
      expect(textFilePart['text'], 'https://example.com/a.csv');
    });

    test('audio wav/mp3/mpeg 均映射为 input_audio,mp3 与 mpeg 归一化为 mp3', () {
      for (final entry in {
        'audio/wav': 'wav',
        'audio/mp3': 'mp3',
        'audio/mpeg': 'mp3',
      }.entries) {
        final result = convertToOpenAiCompatibleChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: const FileDataBase64('AAAA'),
                mediaType: entry.key,
              ),
            ]),
          ],
          providerOptionsName: 'mycustom',
        );

        final content = result.messages.single['content']! as List<Object?>;
        final audioPart = content[0]! as Map<String, Object?>;
        expect(audioPart['type'], 'input_audio');
        final inputAudio = audioPart['input_audio']! as Map<String, Object?>;
        expect(inputAudio['format'], entry.value);
      }
    });

    test('audio url 来源不受支持,抛出', () {
      expect(
        () => convertToOpenAiCompatibleChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataUrl(Uri.parse('https://example.com/a.wav')),
                mediaType: 'audio/wav',
              ),
            ]),
          ],
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test(
        'PDF file part 编码为 data URI,filename 缺失时用 document.pdf 兜底'
        '(与 openai 包 part-<index>.pdf 不同)', () {
      final bytes = Uint8List.fromList([9, 9]);
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage([
            FilePart(data: FileDataBytes(bytes), mediaType: 'application/pdf'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = result.messages.single['content']! as List<Object?>;
      final filePart = content[0]! as Map<String, Object?>;
      final file = filePart['file']! as Map<String, Object?>;
      expect(file['filename'], 'document.pdf');
      expect(file['file_data'], 'data:application/pdf;base64,CQk=');
    });

    test('file reference part 一律不受支持,直接 throw(不尝试匹配 provider key)', () {
      expect(
        () => convertToOpenAiCompatibleChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataReference({'mycustom': 'file-abc123'}),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('文本文件(FileDataText)part 不受支持,抛出', () {
      expect(
        () => convertToOpenAiCompatibleChatMessages(
          prompt: [
            UserMessage([
              const FilePart(
                data: FileDataText('plain'),
                mediaType: 'text/plain',
              ),
            ]),
          ],
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('不支持的文件媒体类型(既非 image/audio/application/text)抛出', () {
      expect(
        () => convertToOpenAiCompatibleChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataBytes(Uint8List.fromList([1])),
                mediaType: 'font/woff2',
              ),
            ]),
          ],
          providerOptionsName: 'mycustom',
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('part 级与消息级 providerOptions 按 providerOptionsName 键分别展开', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          UserMessage(
            const [
              TextPart(
                'x',
                providerOptions: {
                  'mycustom': {'weight': 1},
                },
              ),
              TextPart('y'),
            ],
            providerOptions: const {
              'mycustom': {'topField': true},
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      final message = result.messages.single;
      expect(message['topField'], true);
      final content = message['content']! as List<Object?>;
      expect(content[0], {'type': 'text', 'text': 'x', 'weight': 1});
      expect(content[1], {'type': 'text', 'text': 'y'});
    });
  });

  group('convertToOpenAiCompatibleChatMessages — assistant', () {
    test('reasoning part 累积回传进 reasoning_content(与 openai 包静默丢弃相反)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          AssistantMessage([
            ReasoningPart('internal thought'),
            TextPart('final answer'),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {
          'role': 'assistant',
          'content': 'final answer',
          'reasoning_content': 'internal thought',
        },
      ]);
    });

    test('无 reasoning part 时不携带 reasoning_content 键', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          AssistantMessage([TextPart('foo')]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages.single.containsKey('reasoning_content'), isFalse);
    });

    test('有 tool_calls 且文本为空时 content 转 null', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'sf'},
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final message = result.messages.single;
      expect(message['content'], isNull);
      expect(message['tool_calls'], [
        {
          'id': 'call_1',
          'type': 'function',
          'function': {'name': 'get_weather', 'arguments': '{"city":"sf"}'},
        },
      ]);
    });

    test(
        'tool-call 的 thoughtSignature 挂在 google 键(手工挂载兜底)时写入 '
        'extra_content', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'noop',
              input: {},
              providerOptions: {
                'google': {'thoughtSignature': 'sig-abc'},
              },
            ),
          ]),
        ],
        providerOptionsName: 'mycustom', // 与 google 键无关,验证不受此参数影响
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      expect(call['extra_content'], {
        'google': {'thought_signature': 'sig-abc'},
      });
    });

    test(
        'tool-call 的 thoughtSignature 挂在 providerOptionsName 键(工具循环回放'
        '场景,Fix 1)时同样写入 extra_content', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'noop',
              input: {},
              providerOptions: {
                'mycustom': {'thoughtSignature': 'sig-replayed'},
              },
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      expect(call['extra_content'], {
        'google': {'thought_signature': 'sig-replayed'},
      });
    });

    test(
        'thoughtSignature 同时挂在 providerOptionsName 键与 google 键时,'
        'providerOptionsName 键优先(Fix 1)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'noop',
              input: {},
              providerOptions: {
                'mycustom': {'thoughtSignature': 'sig-priority'},
                'google': {'thoughtSignature': 'sig-stale'},
              },
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      expect(call['extra_content'], {
        'google': {'thought_signature': 'sig-priority'},
      });
    });

    test('无 thoughtSignature 时 tool_calls 条目不含 extra_content 键', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          AssistantMessage([
            ToolCallPart(toolCallId: 'call_1', toolName: 'noop', input: {}),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      expect(call.containsKey('extra_content'), isFalse);
    });

    test('thoughtSignature 为空串时视同未提供,不含 extra_content 键(Fix 4)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'noop',
              input: {},
              providerOptions: {
                'google': {'thoughtSignature': ''},
              },
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      expect(call.containsKey('extra_content'), isFalse);
    });

    test('tool-call input 为 null 时序列化为空对象', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          AssistantMessage([
            ToolCallPart(toolCallId: 'call_2', toolName: 'noop', input: null),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final toolCalls = result.messages.single['tool_calls']! as List<Object?>;
      final call = toolCalls.single! as Map<String, Object?>;
      final function = call['function']! as Map<String, Object?>;
      expect(function['arguments'], '{}');
    });
  });

  group('convertToOpenAiCompatibleChatMessages — tool', () {
    test('text/error-text 直用,execution-denied 无 reason 时兜底文案', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultText('plain result'),
            ),
            ToolResultPart(
              toolCallId: 'call_2',
              toolName: 'lookup',
              output: ToolResultErrorText('boom'),
            ),
            ToolResultPart(
              toolCallId: 'call_3',
              toolName: 'lookup',
              output: ToolResultExecutionDenied(),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'plain result'},
        {'role': 'tool', 'tool_call_id': 'call_2', 'content': 'boom'},
        {
          'role': 'tool',
          'tool_call_id': 'call_3',
          'content': 'Tool call execution denied.',
        },
      ]);
    });

    test('execution-denied 带 reason 时使用 reason 文案', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultExecutionDenied(reason: 'user rejected'),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages.single['content'], 'user rejected');
    });

    test('json/error-json 序列化为 JSON 字符串', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultJson({'ok': true}),
            ),
            ToolResultPart(
              toolCallId: 'call_2',
              toolName: 'lookup',
              output: ToolResultErrorJson({'code': 'E1'}),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages[0]['content'], '{"ok":true}');
      expect(result.messages[1]['content'], '{"code":"E1"}');
    });

    test('content 类型工具结果的 items 序列化为 JSON 字符串', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultContentOutput([
                const ToolResultTextItem('x'),
                ToolResultFileItem(
                  data: const FileDataBase64('AAA='),
                  mediaType: 'image/png',
                ),
              ]),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = jsonDecode(result.messages.single['content']! as String);
      expect(content, [
        {'type': 'text', 'text': 'x'},
        {'type': 'file', 'data': 'AAA=', 'mediaType': 'image/png'},
      ]);
    });

    test(
        'custom 内容项的 providerOptions 整 map 入 JSON'
        '(codex PR#5 round-7:providerOptions 是 custom item 的唯一载荷)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultContentOutput([
                ToolResultCustomItem(
                  providerOptions: {
                    'mycustom': {'payload': 'opaque-blob'},
                  },
                ),
                ToolResultCustomItem(),
              ]),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      final content = jsonDecode(result.messages.single['content']! as String);
      expect(content, [
        {
          'type': 'custom',
          'providerOptions': {
            'mycustom': {'payload': 'opaque-blob'},
          },
        },
        {'type': 'custom'},
      ]);
    });

    test('tool-approval-response part 被跳过,不产出消息', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolApprovalResponsePart(approvalId: 'appr_1', approved: true),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, isEmpty);
    });

    test(
        '消息级 providerOptions 展开进每条 role:tool wire 消息(Fix 2),'
        '与 system/user/assistant 三分支一致', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage(
            [
              ToolResultPart(
                toolCallId: 'call_1',
                toolName: 'lookup',
                output: ToolResultText('first'),
              ),
              ToolResultPart(
                toolCallId: 'call_2',
                toolName: 'lookup',
                output: ToolResultText('second'),
              ),
            ],
            providerOptions: {
              'mycustom': {'cache_control': 'ephemeral'},
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'first',
          'cache_control': 'ephemeral',
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_2',
          'content': 'second',
          'cache_control': 'ephemeral',
        },
      ]);
    });

    test(
        '输出级 providerOptions(ToolResultOutput 变体自身)展开进 wire 消息'
        '(codex PR#5 round-5:契约声明字段不静默丢弃)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultText(
                'ok',
                providerOptions: {
                  'mycustom': {'signature': 'sig-out'},
                },
              ),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'ok',
          'signature': 'sig-out',
        },
      ]);
    });

    test('三层 metadata 优先级:输出级 > part 级 > 消息级(同键由内层胜出)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage(
            [
              ToolResultPart(
                toolCallId: 'call_1',
                toolName: 'lookup',
                output: ToolResultText(
                  'ok',
                  providerOptions: {
                    'mycustom': {'tier': 'output'},
                  },
                ),
                providerOptions: {
                  'mycustom': {'tier': 'part', 'from_part': true},
                },
              ),
            ],
            providerOptions: {
              'mycustom': {'tier': 'message', 'from_message': true},
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'ok',
          'tier': 'output',
          'from_message': true,
          'from_part': true,
        },
      ]);
    });

    test(
        'part 级 providerOptions 透传不回归(消息级 + part 级同时展开,'
        'part 级同名键覆盖消息级)', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage(
            [
              ToolResultPart(
                toolCallId: 'call_1',
                toolName: 'lookup',
                output: ToolResultText('first'),
                providerOptions: {
                  'mycustom': {'cache_control': 'no-cache'},
                },
              ),
            ],
            providerOptions: {
              'mycustom': {
                'cache_control': 'ephemeral',
                'extra_flag': true,
              },
            },
          ),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages.single, {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'content': 'first',
        'cache_control': 'no-cache',
        'extra_flag': true,
      });
    });

    test('无 providerOptions 时行为不变', () {
      final result = convertToOpenAiCompatibleChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultText('plain result'),
            ),
          ]),
        ],
        providerOptionsName: 'mycustom',
      );

      expect(result.messages, [
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'plain result'},
      ]);
    });
  });
}
