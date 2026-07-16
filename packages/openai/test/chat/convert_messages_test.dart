import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('convertToOpenAiChatMessages — system', () {
    test('systemMessageMode=system 产出 role:system', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [SystemMessage('be nice')],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages, [
        {'role': 'system', 'content': 'be nice'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('systemMessageMode=developer 产出 role:developer', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [SystemMessage('be nice')],
        systemMessageMode: SystemMessageMode.developer,
      );

      expect(result.messages, [
        {'role': 'developer', 'content': 'be nice'},
      ]);
    });

    test('systemMessageMode=remove 丢弃消息并产出 warning', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [SystemMessage('be nice')],
        systemMessageMode: SystemMessageMode.remove,
      );

      expect(result.messages, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<OtherWarning>());
    });
  });

  group('convertToOpenAiChatMessages — user', () {
    test('单 text part 走字符串快路径', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          UserMessage([TextPart('hello')]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages, [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test('多 part 走数组形态,含 text + image(bytes 编码为 data URI)', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            const TextPart('describe this'),
            FilePart(data: FileDataBytes(bytes), mediaType: 'image/png'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final message = result.messages.single;
      expect(message['role'], 'user');
      final content = message['content']! as List<Object?>;
      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': 'describe this'});
      final imagePart = content[1]! as Map<String, Object?>;
      expect(imagePart['type'], 'image_url');
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/png;base64,AQID');
    });

    test('image base64 来源同样补全 data URI 前缀', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: const FileDataBase64('AQID'),
              mediaType: 'image/jpeg',
            ),
            const TextPart('x'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/jpeg;base64,AQID');
    });

    test('image url 来源直接透传远程 URL(不下载不编码)', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.png')),
              mediaType: 'image/png',
            ),
            const TextPart('x'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'https://example.com/a.png');
    });

    test(
        "providerOptions.openai.imageDetail='high' 时 image_url 携带 "
        'detail 字段(对照 raw convert-to-openai-chat-messages.ts ~104 行)', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.png')),
              mediaType: 'image/png',
              providerOptions: const {
                'openai': {'imageDetail': 'high'},
              },
            ),
            const TextPart('x'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['detail'], 'high');
    });

    test('未设置 imageDetail 时 image_url 不含 detail 字段', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.png')),
              mediaType: 'image/png',
            ),
            const TextPart('x'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl.containsKey('detail'), isFalse);
    });

    test(
        "providerOptionsName 为 azure 时 imageDetail 按 'azure' 键读取"
        '(与 call 级 options/文件引用派生 key 取齐)', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataUrl(Uri.parse('https://example.com/a.png')),
              mediaType: 'image/png',
              providerOptions: const {
                'azure': {'imageDetail': 'low'},
              },
            ),
            const TextPart('x'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        providerOptionsName: 'azure',
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final imagePart = content[0]! as Map<String, Object?>;
      final imageUrl = imagePart['image_url']! as Map<String, Object?>;
      expect(imageUrl['detail'], 'low');
    });

    test('PDF file part 编码为 data URI,filename 缺失时用 part-<index>.pdf 兜底', () {
      final bytes = Uint8List.fromList([9, 9]);
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataBytes(bytes),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final filePart = content[0]! as Map<String, Object?>;
      expect(filePart['type'], 'file');
      final file = filePart['file']! as Map<String, Object?>;
      expect(file['filename'], 'part-0.pdf');
      expect(file['file_data'], 'data:application/pdf;base64,CQk=');
    });

    test('不支持的文件媒体类型(既非 image/audio/pdf)抛出', () {
      expect(
        () => convertToOpenAiChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataBytes(Uint8List.fromList([1])),
                mediaType: 'application/zip',
              ),
              const TextPart('x'),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('文本文件 part 不受支持,抛出', () {
      expect(
        () => convertToOpenAiChatMessages(
          prompt: [
            UserMessage([
              const FilePart(
                data: FileDataText('plain text'),
                mediaType: 'text/plain',
              ),
              const TextPart('x'),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
        ),
        throwsA(isA<UnsupportedFunctionalityError>()),
      );
    });

    test('provider reference 含 openai 键时正常解析为 file_id', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataReference({'openai': 'file-abc123'}),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final filePart = content[0]! as Map<String, Object?>;
      expect(filePart['type'], 'file');
      final file = filePart['file']! as Map<String, Object?>;
      expect(file['file_id'], 'file-abc123');
    });

    test('provider reference 缺少 openai 键时本地失败,不构造请求', () {
      expect(
        () => convertToOpenAiChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataReference({'anthropic': 'file-xyz'}),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>()
              .having((error) => error.provider, 'provider', 'openai')
              .having(
            (error) => error.reference,
            'reference',
            {'anthropic': 'file-xyz'},
          ),
        ),
      );
    });

    test('providerOptionsName 为 azure 时 provider reference 按 azure 键解析', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          UserMessage([
            FilePart(
              data: FileDataReference({'azure': 'file-az-1'}),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
        providerOptionsName: 'azure',
      );

      final content = (result.messages.single['content']! as List<Object?>);
      final filePart = content[0]! as Map<String, Object?>;
      final file = filePart['file']! as Map<String, Object?>;
      expect(file['file_id'], 'file-az-1');
    });

    test(
        'providerOptionsName 为 azure 时仅含 openai 键的 reference 本地失败'
        '(派生 key 无 openai 兜底,与 responses 侧取齐)', () {
      expect(
        () => convertToOpenAiChatMessages(
          prompt: [
            UserMessage([
              FilePart(
                data: FileDataReference({'openai': 'file-abc123'}),
                mediaType: 'application/pdf',
              ),
            ]),
          ],
          systemMessageMode: SystemMessageMode.system,
          providerOptionsName: 'azure',
        ),
        throwsA(
          isA<NoSuchProviderReferenceError>()
              .having((error) => error.provider, 'provider', 'azure')
              .having(
            (error) => error.reference,
            'reference',
            {'openai': 'file-abc123'},
          ),
        ),
      );
    });
  });

  group('convertToOpenAiChatMessages — assistant', () {
    test('多段 text 拼接,无 tool_calls 时空串保留', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          AssistantMessage([TextPart('foo'), TextPart('bar')]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages, [
        {'role': 'assistant', 'content': 'foobar'},
      ]);
    });

    test('有 tool_calls 且文本为空时 content 转 null', () {
      final result = convertToOpenAiChatMessages(
        prompt: [
          AssistantMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'sf'},
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
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

    test('reasoning part 静默丢弃(不 throw、不 warning)', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          AssistantMessage([
            ReasoningPart('internal thought'),
            TextPart('final answer'),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages, [
        {'role': 'assistant', 'content': 'final answer'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('tool-call input 为 null 时序列化为空对象', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          AssistantMessage([
            ToolCallPart(toolCallId: 'call_2', toolName: 'noop', input: null),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final toolCalls =
          (result.messages.single['tool_calls']! as List<Object?>);
      final call = toolCalls.single! as Map<String, Object?>;
      final function = call['function']! as Map<String, Object?>;
      expect(function['arguments'], '{}');
    });
  });

  group('convertToOpenAiChatMessages — tool', () {
    test('逐 part 展开为多条 role:tool 消息,text/json/error-* 序列化规则', () {
      final result = convertToOpenAiChatMessages(
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
              output: ToolResultJson({'ok': true}),
            ),
            ToolResultPart(
              toolCallId: 'call_3',
              toolName: 'lookup',
              output: ToolResultExecutionDenied(),
            ),
            ToolApprovalResponsePart(approvalId: 'appr_1', approved: true),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages, [
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'plain result',
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_2',
          'content': '{"ok":true}',
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_3',
          'content': 'Tool call execution denied.',
        },
      ]);
    });

    test('execution-denied 带 reason 时使用 reason 文案', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultExecutionDenied(reason: 'user rejected'),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      expect(result.messages.single['content'], 'user rejected');
    });

    test('content 类型工具结果的 items 显式序列化为 JSON 字符串,不抛异常', () {
      final result = convertToOpenAiChatMessages(
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
        systemMessageMode: SystemMessageMode.system,
      );

      final message = result.messages.single;
      expect(message['role'], 'tool');
      expect(message['tool_call_id'], 'call_1');
      final content = jsonDecode(message['content']! as String);
      expect(content, [
        {'type': 'text', 'text': 'x'},
        {'type': 'file', 'data': 'AAA=', 'mediaType': 'image/png'},
      ]);
    });

    test('custom 内容项的 providerOptions 整 map 入 JSON(唯一载荷不丢弃)', () {
      final result = convertToOpenAiChatMessages(
        prompt: const [
          ToolMessage([
            ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              output: ToolResultContentOutput([
                ToolResultCustomItem(
                  providerOptions: {
                    'openai': {'payload': 'opaque-blob'},
                  },
                ),
                ToolResultCustomItem(),
              ]),
            ),
          ]),
        ],
        systemMessageMode: SystemMessageMode.system,
      );

      final content = jsonDecode(result.messages.single['content']! as String);
      expect(content, [
        {
          'type': 'custom',
          'providerOptions': {
            'openai': {'payload': 'opaque-blob'},
          },
        },
        {'type': 'custom'},
      ]);
    });
  });
}
