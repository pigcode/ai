import 'dart:convert';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 构造一个 JSON 响应(200)。
http.StreamedResponse _jsonResponse(String body) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );

http.StreamedResponse _sseResponse(String sseText) => http.StreamedResponse(
      Stream.value(utf8.encode(sseText)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

/// 由 data JSON 行构造 SSE 文本(判别只看 data JSON 的 `type`)。
String _sseFrom(List<String> dataJsonLines) =>
    dataJsonLines.map((data) => 'data: $data\n\n').join();

/// 记录最近一次请求体与请求头的测试客户端(照既有 messages 测试模式)。
final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;
  http.BaseRequest? lastRequest;
  Map<String, Object?>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastBody = jsonDecode(request.body) as Map<String, Object?>;
    }
    return handler(request);
  }
}

AnthropicConfig _config(http.Client client) => AnthropicConfig(
      providerName: 'anthropic.messages',
      baseUrl: 'https://api.anthropic.com/v1',
      headers: () => {'x-api-key': 'test-key'},
      client: client,
    );

const _prompt = <LanguageModelMessage>[
  UserMessage(<UserContentPart>[TextPart('hello')]),
];

/// 请求侧 mcpServers providerOptions(camelCase schema 形态)。
const _mcpProviderOptions = <String, Map<String, Object?>>{
  'anthropic': <String, Object?>{
    'mcpServers': <Object?>[
      <String, Object?>{
        'type': 'url',
        'name': 'echo-server',
        'url': 'https://mcp.example.com/sse',
      },
    ],
  },
};

/// 解析产物 → 次轮 assistant 消息。照核心 `_toAssistantMessage` 的映射同构
/// 手工装配(ToolCall.providerMetadata → ToolCallPart.providerOptions,
/// ToolResult 按 isError 分流 json/error-json)——anthropic 包测试不得依赖
/// pigcode_ai(包依赖方向,spec §8),故在此镜像该两行映射。
AssistantMessage _assistantFrom(ToolCall call, ToolResult result) =>
    AssistantMessage(<AssistantContentPart>[
      ToolCallPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        input: jsonDecode(call.input),
        providerExecuted: true,
        providerOptions: call.providerMetadata,
      ),
      ToolResultPart(
        toolCallId: result.toolCallId,
        toolName: result.toolName,
        output: result.isError == true
            ? ToolResultErrorJson(result.result)
            : ToolResultJson(result.result),
      ),
    ]);

void main() {
  group('MCP 全链路:请求编码 → 响应解析 → convert 回放次轮请求', () {
    // 次轮请求 assistant content 的期望回放块(两路共用)。
    const expectedReplayBlocks = <Map<String, Object?>>[
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
          <String, Object?>{'type': 'text', 'text': 'Tool echo: hello world'},
        ],
      },
    ];

    void expectMcpRequestSide(_RecordingClient client) {
      // 请求侧:mcp_servers 编码(可选键缺席不写,§9.5b)+ beta。
      expect(client.lastBody!['mcp_servers'], [
        {
          'type': 'url',
          'name': 'echo-server',
          'url': 'https://mcp.example.com/sse',
        },
      ]);
      expect(
        anthropicBetasFromHeaderValue(
          client.lastRequest!.headers['anthropic-beta'],
        ),
        contains('mcp-client-2025-04-04'),
      );
    }

    void expectMcpReplay(ToolCall call, ToolResult result) {
      final replay = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          ..._prompt,
          _assistantFrom(call, result),
        ],
        sendReasoning: false,
      );
      final assistantContent =
          (replay.messages.last['content'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(assistantContent, expectedReplayBlocks);
      // 走向 B(T14):成功回放无兜底 warning。
      expect(replay.warnings, isEmpty);
    }

    test('doGenerate 路', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': [
            {
              'type': 'mcp_tool_use',
              'id': 'mcptoolu_1',
              'name': 'echo',
              'server_name': 'echo-server',
              'input': {'message': 'hello world'},
            },
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'mcptoolu_1',
              'is_error': false,
              'content': [
                {'type': 'text', 'text': 'Tool echo: hello world'},
              ],
            },
          ],
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        })),
      );
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(
        prompt: _prompt,
        providerOptions: _mcpProviderOptions,
      ));

      expectMcpRequestSide(client);

      // 响应侧:mcp 两块解析(T12 契约形态)。
      final call = result.content.whereType<ToolCall>().single;
      final toolResult = result.content.whereType<ToolResult>().single;
      expect(call.providerExecuted, isTrue);
      expect(call.isDynamic, isTrue);
      expect(call.providerMetadata, {
        'anthropic': {'type': 'mcp-tool-use', 'serverName': 'echo-server'},
      });
      expect(toolResult.toolName, 'echo');
      expect(toolResult.isDynamic, isTrue);

      // convert 回放次轮请求(T14)。
      expectMcpReplay(call, toolResult);
    });

    test('doStream 路', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_sseFrom([
          '{"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"stop_reason":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":5}}}',
          '{"type":"content_block_start","index":0,"content_block":{"type":"mcp_tool_use","id":"mcptoolu_1","name":"echo","server_name":"echo-server","input":{"message":"hello world"}}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"content_block_start","index":1,"content_block":{"type":"mcp_tool_result","tool_use_id":"mcptoolu_1","is_error":false,"content":[{"type":"text","text":"Tool echo: hello world"}]}}',
          '{"type":"content_block_stop","index":1}',
          '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
          '{"type":"message_stop"}',
        ])),
      );
      final streamResult = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doStream(const LanguageModelCallOptions(
        prompt: _prompt,
        providerOptions: _mcpProviderOptions,
      ));
      final parts = await streamResult.stream.toList();

      expectMcpRequestSide(client);

      expect(parts.whereType<ErrorPart>(), isEmpty);
      final call = parts.whereType<ToolCall>().single;
      final toolResult = parts.whereType<ToolResult>().single;

      expectMcpReplay(call, toolResult);
    });
  });

  group('pause_turn server tool pending-only 续接协议边界', () {
    const modelId = 'claude-opus-4-8';
    const toolCallId = 'srvtoolu_pause_1';
    const wireInput = <String, Object?>{'code': 'print(1)'};

    AssistantMessage pendingAssistantFrom(ToolCall call) =>
        AssistantMessage(<AssistantContentPart>[
          ToolCallPart(
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            input: jsonDecode(call.input),
            providerExecuted: call.providerExecuted,
            providerOptions: call.providerMetadata,
          ),
        ]);

    void expectPendingCall(ToolCall call) {
      expect(call.toolCallId, toolCallId);
      expect(call.toolName, 'code_execution');
      expect(call.providerExecuted, isTrue);
      expect(jsonDecode(call.input), {
        'type': 'programmatic-tool-call',
        ...wireInput,
      });
    }

    void expectPauseTurn(LanguageModelFinishReason finishReason) {
      expect(finishReason.unified, FinishReasonType.stop);
      expect(finishReason.raw, 'pause_turn');
    }

    void expectContinuationRequest(_RecordingClient client) {
      // 完整 messages 等值同时锁定顺序，且证明没有凭空插入 user 或
      // code_execution_tool_result 消息/块。
      expect(client.lastBody!['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'server_tool_use',
              'id': toolCallId,
              'name': 'code_execution',
              'input': wireInput,
            },
          ],
        },
      ]);
      expect(client.lastBody!['tools'], [
        {'type': 'code_execution_20260120', 'name': 'code_execution'},
      ]);
    }

    test('doGenerate:pause_turn 原样回放 pending server_tool_use', () async {
      final pauseTurnResponse = jsonEncode({
        'type': 'message',
        'id': 'msg_pause_1',
        'model': modelId,
        'role': 'assistant',
        'content': [
          {
            'type': 'server_tool_use',
            'id': toolCallId,
            'name': 'code_execution',
            'input': wireInput,
          },
        ],
        'stop_reason': 'pause_turn',
        'stop_sequence': null,
        'usage': {'input_tokens': 5, 'output_tokens': 2},
      });
      final completedResponse = jsonEncode({
        'type': 'message',
        'id': 'msg_done_1',
        'model': modelId,
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'done'},
        ],
        'stop_reason': 'end_turn',
        'stop_sequence': null,
        'usage': {'input_tokens': 7, 'output_tokens': 1},
      });
      var requestCount = 0;
      final client = _RecordingClient(
        (request) async => switch (++requestCount) {
          1 => _jsonResponse(pauseTurnResponse),
          2 => _jsonResponse(completedResponse),
          _ => throw StateError('unexpected request $requestCount'),
        },
      );
      final model = AnthropicMessagesLanguageModel(
        modelId,
        config: _config(client),
      );
      final tool = codeExecution_20260120();

      final first = await model.doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        tools: [tool],
      ));

      expectPauseTurn(first.finishReason);
      final call = first.content.whereType<ToolCall>().single;
      expectPendingCall(call);
      expect(first.content.whereType<ToolResult>(), isEmpty);

      await model.doGenerate(LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          ..._prompt,
          pendingAssistantFrom(call),
        ],
        tools: [tool],
      ));

      expect(requestCount, 2);
      expectContinuationRequest(client);
    });

    test('doStream:pause_turn 原样回放 pending server_tool_use', () async {
      final pauseTurnResponse = _sseFrom([
        jsonEncode({
          'type': 'message_start',
          'message': {
            'id': 'msg_pause_1',
            'model': modelId,
            'role': 'assistant',
            'content': <Object?>[],
            'stop_reason': null,
            'usage': {'input_tokens': 5},
          },
        }),
        jsonEncode({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'server_tool_use',
            'id': toolCallId,
            'name': 'code_execution',
            'input': <String, Object?>{},
          },
        }),
        jsonEncode({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(wireInput),
          },
        }),
        jsonEncode({'type': 'content_block_stop', 'index': 0}),
        jsonEncode({
          'type': 'message_delta',
          'delta': {'stop_reason': 'pause_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 2},
        }),
        jsonEncode({'type': 'message_stop'}),
      ]);
      final completedResponse = _sseFrom([
        jsonEncode({
          'type': 'message_start',
          'message': {
            'id': 'msg_done_1',
            'model': modelId,
            'role': 'assistant',
            'content': <Object?>[],
            'stop_reason': null,
            'usage': {'input_tokens': 7},
          },
        }),
        jsonEncode({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        }),
        jsonEncode({'type': 'message_stop'}),
      ]);
      var requestCount = 0;
      final client = _RecordingClient(
        (request) async => switch (++requestCount) {
          1 => _sseResponse(pauseTurnResponse),
          2 => _sseResponse(completedResponse),
          _ => throw StateError('unexpected request $requestCount'),
        },
      );
      final model = AnthropicMessagesLanguageModel(
        modelId,
        config: _config(client),
      );
      final tool = codeExecution_20260120();

      final first = await model.doStream(LanguageModelCallOptions(
        prompt: _prompt,
        tools: [tool],
      ));
      final firstParts = await first.stream.toList();

      expect(firstParts.whereType<ErrorPart>(), isEmpty);
      final finish = firstParts.whereType<FinishPart>().single;
      expectPauseTurn(finish.finishReason);
      final call = firstParts.whereType<ToolCall>().single;
      expectPendingCall(call);
      expect(firstParts.whereType<ToolResult>(), isEmpty);

      final second = await model.doStream(LanguageModelCallOptions(
        prompt: <LanguageModelMessage>[
          ..._prompt,
          pendingAssistantFrom(call),
        ],
        tools: [tool],
      ));
      final secondParts = await second.stream.toList();

      expect(requestCount, 2);
      expectContinuationRequest(client);
      expect(secondParts.whereType<ErrorPart>(), isEmpty);
      final secondFinish = secondParts.whereType<FinishPart>().single;
      expect(secondFinish.finishReason.unified, FinishReasonType.stop);
      expect(secondFinish.finishReason.raw, 'end_turn');
    });
  });

  group('compaction 全链路:contextManagement 编码 → 解析 → 回放', () {
    test(
        'compact edit 双 beta;compaction 块 → TextContent+metadata → compaction 块',
        () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': [
            {'type': 'compaction', 'content': 'summary of earlier turns'},
            {'type': 'text', 'text': 'continuing'},
          ],
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        })),
      );
      final result = await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(const LanguageModelCallOptions(
        prompt: _prompt,
        providerOptions: <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'contextManagement': <String, Object?>{
              'edits': <Object?>[
                <String, Object?>{'type': 'compact_20260112'},
              ],
            },
          },
        },
      ));

      // 编码侧(T10):context_management + compact 双 beta(:688-694)。
      expect(client.lastBody!['context_management'], {
        'edits': [
          {'type': 'compact_20260112'},
        ],
      });
      expect(
        anthropicBetasFromHeaderValue(
          client.lastRequest!.headers['anthropic-beta'],
        ),
        containsAll(['context-management-2025-06-27', 'compact-2026-01-12']),
      );

      // 解析侧(T12):compaction → TextContent + metadata。
      final compacted = result.content.first as TextContent;
      expect(compacted.text, 'summary of earlier turns');
      expect(compacted.providerMetadata, {
        'anthropic': {'type': 'compaction'},
      });

      // 回放侧(T14):metadata 判定命中 → compaction 块(content 直入)。
      final replay = convertToAnthropicMessages(
        prompt: <LanguageModelMessage>[
          ..._prompt,
          AssistantMessage(<AssistantContentPart>[
            TextPart(
              compacted.text,
              providerOptions: compacted.providerMetadata,
            ),
          ]),
        ],
        sendReasoning: false,
      );
      final assistantContent =
          (replay.messages.last['content'] as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(assistantContent.single, {
        'type': 'compaction',
        'content': 'summary of earlier turns',
      });
      expect(replay.warnings, isEmpty);
    });
  });

  group('container 请求侧 × forward helper 语义衔接', () {
    test('倒序命中最近非空 id;返回值可直接作 providerOptions 进编码(纯 id → 字符串形态)', () async {
      // 手搓契约 metadata 列表(不依赖 pigcode_ai):null 项、旧 id、最新
      // id、末步无 container(穿透)。
      final po = forwardAnthropicContainerIdFromLastStep(<ProviderMetadata?>[
        null,
        {
          'anthropic': {
            'container': {'id': 'cont_old', 'expiresAt': 'x'},
          },
        },
        {
          'anthropic': {
            'container': {'id': 'cont_new'},
          },
        },
        {
          'anthropic': {'container': null},
        },
      ]);
      expect(po, {
        'anthropic': {
          'container': {'id': 'cont_new'},
        },
      });

      final client = _RecordingClient(
        (request) async => _jsonResponse(jsonEncode({
          'type': 'message',
          'id': 'msg_1',
          'model': 'claude-sonnet-4-5',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
          'stop_reason': 'end_turn',
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        })),
      );
      await AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      ).doGenerate(LanguageModelCallOptions(
        prompt: _prompt,
        providerOptions: po,
      ));

      // 纯 id(skills 空/缺席)→ wire 字符串形态(T10);container 不触发
      // 任何 beta,且无其他 beta 来源 → 不发 anthropic-beta 头。
      expect(client.lastBody!['container'], 'cont_new');
      expect(
        client.lastRequest!.headers.containsKey('anthropic-beta'),
        isFalse,
      );
    });
  });
}
