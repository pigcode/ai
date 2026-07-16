import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 把三引号字符串字面量里每一行的前导空白去掉,使跟随 Dart 源码缩进
/// 书写的 SSE fixture 文本在解析时等价于零缩进版本(照
/// `packages/openai/test/chat/chat_language_model_stream_test.dart` 式样)。
String _flushLeft(String text) =>
    text.split('\n').map((line) => line.trimLeft()).join('\n');

/// 文本流基线 fixture(报告 04 §2 的 8 事件中覆盖 7 种;`event:` 字段行
/// 仅为 SSE 形式,判别只看 data JSON 的 `type`)。
final _streamText = _flushLeft('''
event: message_start
data: {"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"stop_reason":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":5}}}

event: ping
data: {"type":"ping"}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}

event: message_stop
data: {"type":"message_stop"}

''');

/// 由 data JSON 行构造 SSE 文本(判别只看 data JSON 的 `type`,`event:`
/// 行可省略)。
String _sseFrom(List<String> dataJsonLines) =>
    dataJsonLines.map((data) => 'data: $data\n\n').join();

/// Task 23 共用的 message_start data(usage:10/3/5,stop_reason null)。
const _messageStartData =
    '{"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"stop_reason":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":5}}}';

const _messageStopData = '{"type":"message_stop"}';

http.StreamedResponse _sseResponse(String sseText) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(sseText)),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// 记录最近一次请求体与请求对象的测试客户端(照 openai 包模式;流测试
/// 文件内自带,不共享 support 文件)。
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

AnthropicConfig _config(http.Client client) {
  return AnthropicConfig(
    providerName: 'anthropic.messages',
    baseUrl: 'https://api.anthropic.com/v1',
    headers: () => {'x-api-key': 'test-key'},
    client: client,
  );
}

const _prompt = <LanguageModelMessage>[
  UserMessage(<UserContentPart>[TextPart('hello')]),
];

/// 跑一段 SSE 流并返回全部 stream part(Task 24+ 断言入口)。
Future<List<LanguageModelStreamPart>> _partsOf(
  String sseText, {
  String modelId = 'claude-sonnet-4-5',
  String providerName = 'anthropic.messages',
  ProviderOptions? providerOptions,
  List<LanguageModelMessage> prompt = _prompt,
  ResponseFormat? responseFormat,
  bool? includeRawChunks,
  List<LanguageModelTool>? tools,
}) async {
  final client = _RecordingClient((request) async => _sseResponse(sseText));
  final model = AnthropicMessagesLanguageModel(
    modelId,
    config: AnthropicConfig(
      providerName: providerName,
      baseUrl: 'https://api.anthropic.com/v1',
      headers: () => {'x-api-key': 'test-key'},
      client: client,
    ),
  );
  final result = await model.doStream(LanguageModelCallOptions(
    prompt: prompt,
    providerOptions: providerOptions,
    responseFormat: responseFormat,
    includeRawChunks: includeRawChunks,
    tools: tools,
  ));
  return result.stream.toList();
}

/// 跑一段 SSE 流并取出唯一的 [FinishPart](Task 23 断言入口)。
Future<FinishPart> _finishOf(
  String sseText, {
  String providerName = 'anthropic.messages',
  ProviderOptions? providerOptions,
}) async {
  final parts = await _partsOf(
    sseText,
    providerName: providerName,
    providerOptions: providerOptions,
  );
  return parts.whereType<FinishPart>().single;
}

void main() {
  group('AnthropicMessagesLanguageModel.doStream 文本流基线', () {
    test('请求体带 stream:true,URL 以 /messages 结尾', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(prompt: _prompt),
      );
      await result.stream.drain<void>();

      expect(client.lastBody!['stream'], true);
      expect(client.lastRequest!.url.path, endsWith('/messages'));
    });

    test('8 事件判别:StreamStart 首发 + 文本流 + FinishPart 收尾,ping 无产出', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(prompt: _prompt),
      );
      final parts = await result.stream.toList();

      // StreamStart 首发(warnings 首发,:1547-1549)。
      expect(parts.first, isA<StreamStart>());

      // ResponseMetadata 恰 1 个(:2341-2345)。
      final metadata = parts.whereType<ResponseMetadata>().toList();
      expect(metadata, hasLength(1));
      expect(metadata.single.id, 'msg_01');
      expect(metadata.single.modelId, 'claude-sonnet-4-5');

      // text 块 id = String(块索引)(报告 04 §3 :133)。
      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, '0');

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas, hasLength(2));
      expect(textDeltas.map((delta) => delta.id), everyElement('0'));
      expect(textDeltas.map((delta) => delta.delta).join(), 'Hello world');

      final textEnds = parts.whereType<TextEnd>().toList();
      expect(textEnds, hasLength(1));
      expect(textEnds.single.id, '0');

      // FinishPart 恰 1 个且是最后一个(报告 04 §9)。
      final finishes = parts.whereType<FinishPart>().toList();
      expect(finishes, hasLength(1));
      expect(parts.last, isA<FinishPart>());
      expect(
        finishes.single.finishReason.unified,
        FinishReasonType.stop,
      );
      expect(finishes.single.finishReason.raw, 'end_turn');

      // ping 不产出任何 part(:1564-1566):StreamStart + ResponseMetadata
      // + TextStart + 2×TextDelta + TextEnd + FinishPart = 7。
      expect(parts, hasLength(7));
    });

    test('toolStreaming 流式默认:tools[0].eager_input_streaming == true', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
          ],
        ),
      );
      await result.stream.drain<void>();

      final tools = client.lastBody!['tools']! as List<Object?>;
      final wireTool = tools.first! as Map<String, Object?>;
      expect(wireTool['eager_input_streaming'], true);
    });

    test('toolStreaming: false → tools[0] 无 eager_input_streaming 键', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: _prompt,
          tools: [
            FunctionTool(
              name: 'get_weather',
              inputSchema: JsonSchema({'type': 'object'}),
            ),
          ],
          providerOptions: {
            'anthropic': {'toolStreaming': false},
          },
        ),
      );
      await result.stream.drain<void>();

      final tools = client.lastBody!['tools']! as List<Object?>;
      final wireTool = tools.first! as Map<String, Object?>;
      expect(wireTool.containsKey('eager_input_streaming'), isFalse);
    });
  });

  group('message_delta 状态更新与流式 usage 口径(Task 23)', () {
    test('usage 口径:input 侧取 message_start,output 无条件取 message_delta(报告 04 §7)',
        () async {
      final finish = await _finishOf(_sseFrom([
        _messageStartData,
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // inputTokens.total = input + cacheWrite + cacheRead = 10+3+5。
      expect(finish.usage.inputTokens.total, 18);
      expect(finish.usage.inputTokens.noCache, 10);
      expect(finish.usage.inputTokens.cacheRead, 5);
      expect(finish.usage.inputTokens.cacheWrite, 3);
      // output 无条件取 message_delta 值(:2411)。
      expect(finish.usage.outputTokens.total, 25);
    });

    test('input 修正 + cache 覆盖:message_delta 非 null 字段才覆盖(:2405-2420)',
        () async {
      final finish = await _finishOf(_sseFrom([
        _messageStartData,
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":12,"cache_read_input_tokens":7,"output_tokens":25}}',
        _messageStopData,
      ]));

      // input_tokens 12 ≠ 10 → 修正;cache_read 非 null → 覆盖为 7;
      // cache_creation 缺失(null)→ 保持 message_start 的 3 不回退。
      expect(finish.usage.inputTokens.noCache, 12);
      expect(finish.usage.inputTokens.cacheRead, 7);
      expect(finish.usage.inputTokens.cacheWrite, 3);
      expect(finish.usage.inputTokens.total, 22);
    });

    test(
        'spec 裁决 #3(偏离):message_delta stop_reason 为 null 不覆盖 message_start 已设值',
        () async {
      final startWithStop = _messageStartData.replaceFirst(
        '"stop_reason":null',
        '"stop_reason":"end_turn"',
      );
      final finish = await _finishOf(_sseFrom([
        startWithStop,
        '{"type":"message_delta","delta":{"stop_reason":null,"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // 上游会被 null 覆盖回 other/undefined(:2425-2431);spec #3 偏离:
      // 仅非 null 才重建。
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.finishReason.raw, 'end_turn');
    });

    test('对照:message_delta stop_reason 非 null 时正常覆盖', () async {
      final startWithStop = _messageStartData.replaceFirst(
        '"stop_reason":null',
        '"stop_reason":"end_turn"',
      );
      final finish = await _finishOf(_sseFrom([
        startWithStop,
        '{"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(finish.finishReason.unified, FinishReasonType.length);
      expect(finish.finishReason.raw, 'max_tokens');
    });

    test(
        'spec 裁决 #4(偏离)+ metadata 组装:message_delta 无 container 不清空 message_start 的值',
        () async {
      const startWithContainer =
          '{"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"stop_reason":null,"container":{"id":"cont_1","expires_at":"2026-01-01T00:00:00Z"},"usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"server_tool_use":{"web_search_requests":0}}}}';
      final finish = await _finishOf(_sseFrom([
        startWithContainer,
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":"END"},"usage":{"output_tokens":25},"context_management":{"applied_edits":[{"type":"clear_tool_uses_20250919","cleared_tool_uses":2,"cleared_input_tokens":100}]}}',
        _messageStopData,
      ]));

      final metadata = finish.providerMetadata!['anthropic']!;

      // 上游 delta.container 为 null 时会置回 null(:2435-2447);spec #4
      // 偏离:非 null 才覆盖,message_start 的值保留(skills 恒 null,
      // :2323-2329)。
      expect(metadata['container'], {
        'expiresAt': '2026-01-01T00:00:00Z',
        'id': 'cont_1',
        'skills': null,
      });

      // usage == rawUsage:message_start 全量(loose 保留未知字段)+
      // message_delta usage 浅合并(:2319-2321,2455-2458)。
      expect(metadata['usage'], {
        'input_tokens': 10,
        'cache_creation_input_tokens': 3,
        'cache_read_input_tokens': 5,
        'server_tool_use': {'web_search_requests': 0},
        'output_tokens': 25,
      });

      expect(metadata['stopSequence'], 'END');
      // stop_details 为 null → 不落键(:2434)。
      expect(metadata.containsKey('stopDetails'), isFalse);
      // iterations 无 → 显式 null。
      expect(metadata.containsKey('iterations'), isTrue);
      expect(metadata['iterations'], isNull);
      expect(metadata['contextManagement'], {
        'appliedEdits': [
          {
            'type': 'clear_tool_uses_20250919',
            'clearedToolUses': 2,
            'clearedInputTokens': 100,
          },
        ],
      });
    });

    test('message_delta 带非 null container/stop_details 时覆盖并做 camelCase 映射',
        () async {
      const startWithContainer =
          '{"type":"message_start","message":{"id":"msg_01","model":"claude-sonnet-4-5","role":"assistant","content":[],"stop_reason":null,"container":{"id":"cont_1","expires_at":"2026-01-01T00:00:00Z"},"usage":{"input_tokens":10,"cache_creation_input_tokens":3,"cache_read_input_tokens":5}}}';
      final finish = await _finishOf(_sseFrom([
        startWithContainer,
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null,"stop_details":{"type":"refusal","category":"policy"},"container":{"id":"cont_2","expires_at":"2026-02-01T00:00:00Z","skills":[{"type":"anthropic","skill_id":"sk_1","version":"1"}]}},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final metadata = finish.providerMetadata!['anthropic']!;

      // 非 null container 正常覆盖;skills 映射 skill_id → skillId。
      expect(metadata['container'], {
        'expiresAt': '2026-02-01T00:00:00Z',
        'id': 'cont_2',
        'skills': [
          {'type': 'anthropic', 'skillId': 'sk_1', 'version': '1'},
        ],
      });

      // stop_details 非 null → 落键;空字段(explanation/recommended_model)
      // 不落键(:2781-2797)。
      expect(metadata['stopDetails'], {
        'type': 'refusal',
        'category': 'policy',
      });
    });

    test('iterations 映射:camelCase + cache 键 truthy 判断 0 不落键(:2476-2487)',
        () async {
      final finish = await _finishOf(_sseFrom([
        _messageStartData,
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25,"iterations":[{"type":"message","model":"claude-sonnet-4-5","input_tokens":10,"output_tokens":25,"cache_creation_input_tokens":0}]}}',
        _messageStopData,
      ]));

      final metadata = finish.providerMetadata!['anthropic']!;
      expect(metadata['iterations'], [
        {
          'type': 'message',
          'model': 'claude-sonnet-4-5',
          'inputTokens': 10,
          'outputTokens': 25,
        },
      ]);
    });

    test(
        '双 key 同挂:providerOptions 走自定义 key 时 FinishPart.providerMetadata 同挂两键(:2495-2504)',
        () async {
      final finish = await _finishOf(
        _sseFrom([
          _messageStartData,
          '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        providerName: 'my-anthropic',
        providerOptions: {
          'my-anthropic': {'sendReasoning': true},
        },
      );

      final metadata = finish.providerMetadata!;
      expect(metadata.keys, containsAll(['anthropic', 'my-anthropic']));
      expect(metadata['my-anthropic'], metadata['anthropic']);
    });
  });

  group('reasoning 块(Task 24)', () {
    test(
        'thinking 流:ReasoningStart/Delta/End,signature 只进 metadata(:1597-1603,2201-2227)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think"}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_abc"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Answer"}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // reasoning 块 id = String(块索引)(:1597-1603)。
      final reasoningStarts = parts.whereType<ReasoningStart>().toList();
      expect(reasoningStarts, hasLength(1));
      expect(reasoningStarts.single.id, '0');

      // thinking_delta → 文本增量;signature_delta → delta 为空串、签名
      // 只进 metadata(:2201-2209,2211-2227)。
      final reasoningDeltas = parts.whereType<ReasoningDelta>().toList();
      expect(reasoningDeltas, hasLength(2));
      expect(reasoningDeltas[0].id, '0');
      expect(reasoningDeltas[0].delta, 'Let me think');
      expect(reasoningDeltas[1].id, '0');
      expect(reasoningDeltas[1].delta, '');
      expect(
        reasoningDeltas[1].providerMetadata!['anthropic']!['signature'],
        'sig_abc',
      );

      final reasoningEnds = parts.whereType<ReasoningEnd>().toList();
      expect(reasoningEnds, hasLength(1));
      expect(reasoningEnds.single.id, '0');

      // 后接的 text 块 id = '1'。
      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, '1');
    });

    test('signature_delta 仅 thinking 块生效:text 块内出现则丢弃(:1522-1538,2213)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_abc"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // blockType 标量守卫:当前块非 thinking → 丢弃,不产出任何
      // ReasoningDelta,也不走 ErrorPart 路径,流正常收尾。
      expect(parts.whereType<ReasoningDelta>(), isEmpty);
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), hasLength(1));
    });

    test('redacted_thinking:ReasoningStart 带 redactedData metadata(:1606-1617)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"redacted_thinking","data":"EmwKAhgB..."}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final reasoningStarts = parts.whereType<ReasoningStart>().toList();
      expect(reasoningStarts, hasLength(1));
      expect(reasoningStarts.single.id, '0');
      expect(
        reasoningStarts.single.providerMetadata!['anthropic']!['redactedData'],
        'EmwKAhgB...',
      );

      final reasoningEnds = parts.whereType<ReasoningEnd>().toList();
      expect(reasoningEnds, hasLength(1));
      expect(reasoningEnds.single.id, '0');
    });
  });

  group('工具调用拼装(Task 25)', () {
    test(
        'delta 累积流:ToolInputStart/Delta/End + ToolCall,空串 delta 跳过(:2245-2282)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}}',
        r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"city\""}}',
        r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":":\"sf\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // tool 块 part id 用工具 id 而非块索引(报告 04 §3 :133、
      // :1676-1680)。
      final toolStarts = parts.whereType<ToolInputStart>().toList();
      expect(toolStarts, hasLength(1));
      expect(toolStarts.single.id, 'toolu_01');
      expect(toolStarts.single.toolName, 'get_weather');

      // 空串 delta 跳过(:2245-2249),join 为完整 JSON。
      final toolDeltas = parts.whereType<ToolInputDelta>().toList();
      expect(toolDeltas, hasLength(2));
      expect(toolDeltas.map((delta) => delta.id), everyElement('toolu_01'));
      expect(toolDeltas.map((delta) => delta.delta).join(), '{"city":"sf"}');

      // ToolInputEnd 后紧跟 ToolCall(:2275-2282、:2147-2168)。
      final toolEnds = parts.whereType<ToolInputEnd>().toList();
      expect(toolEnds, hasLength(1));
      expect(toolEnds.single.id, 'toolu_01');
      final endIndex = parts.indexOf(toolEnds.single);
      expect(parts[endIndex + 1], isA<ToolCall>());

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolCallId, 'toolu_01');
      expect(toolCalls.single.toolName, 'get_weather');
      expect(toolCalls.single.input, '{"city":"sf"}');

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('零 delta 空输入:start 后直接 stop → ToolCall.input == "{}"(:2126-2127)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01","name":"get_weather","input":{}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.input, '{}');
    });

    test('start 即带非空 input 且无 delta → initialInput 为 JSON 序列化(:1661-1665)',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_02","name":"search","input":{"q":"dart"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolCallId, 'toolu_02');
      expect(toolCalls.single.toolName, 'search');
      expect(toolCalls.single.input, '{"q":"dart"}');
    });

    test(
        'client 工具(name=computer)走同一普通 tool_use 拼装,'
        'ToolCall.providerExecuted 为 null(Task 15,报告 08 §4/§5)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_03","name":"computer","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"screenshot\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolCallId, 'toolu_03');
      expect(toolCalls.single.toolName, 'computer');
      expect(toolCalls.single.input, '{"action":"screenshot"}');
      expect(toolCalls.single.providerExecuted, isNull);
    });
  });

  group('server_tool_use 块拼装(Task 7)', () {
    test(
        'delta 模式(web_search):ToolInputStart(providerExecuted:true) → '
        '两个 ToolInputDelta → ToolInputEnd → ToolCall(providerExecuted:true)'
        '(报告 07 §5.1-5.3)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search",'
            '"input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":"{\"que"}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":"ry\":\"dart\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolStarts = parts.whereType<ToolInputStart>().toList();
      expect(toolStarts, hasLength(1));
      expect(toolStarts.single.id, 'srvtoolu_1');
      expect(toolStarts.single.toolName, 'web_search');
      expect(toolStarts.single.providerExecuted, true);

      final toolDeltas = parts.whereType<ToolInputDelta>().toList();
      expect(toolDeltas, hasLength(2));
      expect(
        toolDeltas.map((delta) => delta.delta).join(),
        '{"query":"dart"}',
      );

      final toolEnds = parts.whereType<ToolInputEnd>().toList();
      expect(toolEnds, hasLength(1));
      expect(toolEnds.single.id, 'srvtoolu_1');

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolCallId, 'srvtoolu_1');
      expect(toolCalls.single.toolName, 'web_search');
      expect(toolCalls.single.input, '{"query":"dart"}');
      expect(toolCalls.single.providerExecuted, true);
    });

    test(
        'input 齐备模式(web_fetch):start 块 input 非空 → 无 delta,'
        'ToolCall.input 为 finalInput 直接 stringify(:1719-1727)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_2","name":"web_fetch",'
            '"input":{"url":"https://e.com"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputDelta>(), isEmpty);

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolCallId, 'srvtoolu_2');
      expect(toolCalls.single.toolName, 'web_fetch');
      expect(toolCalls.single.input, '{"url":"https://e.com"}');
      expect(toolCalls.single.providerExecuted, true);
    });

    test(
        '未知 name(future_server_tool)不注册不 yield,流不报错(白名单外,'
        ':1807-1809 + :2266-2268)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_3",'
            '"name":"future_server_tool","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":"{}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);
      expect(parts.whereType<ToolCall>(), isEmpty);
      expect(parts.whereType<ErrorPart>(), isEmpty);
    });

    test(
        'bash_code_execution 子工具:首个空 delta 跳过 + 首个非空 delta 注入 '
        'type(冒号后一个空格,与 doGenerate 侧无空格是两种字节形态,报告 '
        '09 §9.3),流式最终 input 保留该空格(§7.3 snap 形态)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_40",'
            '"name":"bash_code_execution","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":""}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta",'
            r'"partial_json":"{\"command\":\"ls\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolStarts = parts.whereType<ToolInputStart>().toList();
      expect(toolStarts, hasLength(1));
      expect(toolStarts.single.toolName, 'code_execution');
      expect(toolStarts.single.providerExecuted, true);

      // 空串 delta 被跳过,不产出 ToolInputDelta;唯一的非空 delta 是首
      // delta,已被注入 type(冒号后一个空格)。
      final toolDeltas = parts.whereType<ToolInputDelta>().toList();
      expect(toolDeltas, hasLength(1));
      expect(
        toolDeltas.single.delta,
        '{"type": "bash_code_execution","command":"ls"}',
      );

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolName, 'code_execution');
      // 流式最终 input 是逐 delta 拼接结果(非重新 jsonEncode),保留注入处
      // 的空格——与 doGenerate 侧 jsonEncode 无空格是两种字节形态(报告 09
      // §7.3/§9.3)。
      expect(
        toolCalls.single.input,
        '{"type": "bash_code_execution","command":"ls"}',
      );
      expect(toolCalls.single.providerExecuted, true);
    });

    test(
        'code_execution 直接调用(programmatic):首个非空 delta 注入 '
        'programmatic-tool-call(冒号后空格)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_41",'
            '"name":"code_execution","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":""}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta",'
            r'"partial_json":"{\"code\":\"print(1)\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolName, 'code_execution');
      expect(
        toolCalls.single.input,
        '{"type": "programmatic-tool-call","code":"print(1)"}',
      );
    });

    test(
        'code_execution 直接调用、input 经 start 帧整体到达(无 delta)→ '
        'stop 时兜底注入 programmatic-tool-call(无空格,jsonEncode 重编码,'
        '报告 09 §4.3 :2132-2149,覆盖 firstDelta 语义上不成立的场景)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_42",'
            '"name":"code_execution","input":{"code":"print(2)"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(
        toolCalls.single.input,
        '{"type":"programmatic-tool-call","code":"print(2)"}',
      );
    });

    test(
        'code_execution 直接调用、input 已含 type(20260120 continuation)→ '
        'stop 时不重复注入', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_43",'
            '"name":"code_execution",'
            '"input":{"type":"programmatic-tool-call","code":"print(3)"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(
        toolCalls.single.input,
        '{"type":"programmatic-tool-call","code":"print(3)"}',
      );
    });

    test(
        'tool_search_tool_regex:input 全靠 delta 累积,不注入 type('
        'providerToolInputType 恒 null,与 code_execution 族形成对照)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_44",'
            '"name":"tool_search_tool_regex","input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":""}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta",'
            r'"partial_json":"{\"pattern\":\"weather\"}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolName, 'tool_search_tool_regex');
      expect(toolCalls.single.input, '{"pattern":"weather"}');
    });

    test(
        'advisor:预置 input "{}",无 delta,stop 直接产出 ToolCall(input:'
        '"{}")(报告 09 §4.1c :1787-1807)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_45","name":"advisor",'
            '"input":{}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.toolName, 'advisor');
      expect(toolCalls.single.input, '{}');
      expect(toolCalls.single.providerExecuted, true);
    });

    test('caller 忽略:start 带 caller → 无 providerMetadata(§5.1 :270)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_4","name":"web_search",'
            '"input":{"query":"x"},"caller":{"type":"direct"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolStarts = parts.whereType<ToolInputStart>().toList();
      expect(toolStarts, hasLength(1));
      expect(toolStarts.single.providerMetadata, isNull);

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.single.providerMetadata, isNull);
    });

    test('parts 总数断言(防多发):delta 模式共 7 个 part', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_5","name":"web_search",'
            '"input":{}}}',
        r'{"type":"content_block_delta","index":0,"delta":'
            r'{"type":"input_json_delta","partial_json":"{}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      // StreamStart + ResponseMetadata + ToolInputStart + ToolInputDelta +
      // ToolInputEnd + ToolCall + FinishPart
      expect(parts, hasLength(7));
    });
  });

  group('*_tool_result 块回流 + 流式 citations(Task 8)', () {
    test(
        'web_search 成功:ToolResult(snake→camel) + 每条结果一个 SourceContent,'
        'content_block_stop 不再产出任何 part(:311)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search",'
            '"input":{"query":"dart"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1",'
            '"content":[{"type":"web_search_result","url":"https://r.com",'
            '"title":"R","encrypted_content":"enc1","page_age":"1d"}]}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'web_search',
          result: [
            {
              'type': 'web_search_result',
              'url': 'https://r.com',
              'title': 'R',
              'pageAge': '1d',
              'encryptedContent': 'enc1',
            },
          ],
        ),
      );
      expect(toolResults.single.isError, isNull);

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.url);
      expect(source.url, 'https://r.com');
      expect(source.title, 'R');
      expect(source.providerMetadata, {
        'anthropic': {'pageAge': '1d'},
      });
    });

    test('web_search 错误 → isError ToolResult', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search",'
            '"input":{"query":"dart"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1",'
            '"content":{"type":"web_search_tool_result_error",'
            '"error_code":"max_uses_exceeded"}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'web_search',
          result: {
            'type': 'web_search_tool_result_error',
            'errorCode': 'max_uses_exceeded',
          },
          isError: true,
        ),
      );
      expect(parts.whereType<SourceContent>(), isEmpty);
    });

    test(
        'web_fetch 成功 → ToolResult + 随后 text 块 citations_delta 解析出 '
        'SourceContent.document(title: Doc A)(流式 push,§5.4/§5.5)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_2","name":"web_fetch",'
            '"input":{"url":"https://d.com/a.pdf"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"web_fetch_tool_result","tool_use_id":"srvtoolu_2",'
            '"content":{"type":"web_fetch_result","url":"https://d.com/a.pdf",'
            '"retrieved_at":"2026-07-07T00:00:00Z","content":{"type":"document",'
            '"title":"Doc A","citations":{"enabled":true},"source":'
            '{"type":"base64","media_type":"application/pdf",'
            '"data":"JVBERi0="}}}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"content_block_start","index":2,"content_block":'
            '{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":2,"delta":'
            '{"type":"citations_delta","citation":{"type":"char_location",'
            '"cited_text":"quote","document_index":0,"document_title":null,'
            '"start_char_index":1,"end_char_index":2}}}',
        '{"type":"content_block_stop","index":2}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'web_fetch',
          result: {
            'type': 'web_fetch_result',
            'url': 'https://d.com/a.pdf',
            'retrievedAt': '2026-07-07T00:00:00Z',
            'content': {
              'type': 'document',
              'title': 'Doc A',
              'citations': {'enabled': true},
              'source': {
                'type': 'base64',
                'mediaType': 'application/pdf',
                'data': 'JVBERi0=',
              },
            },
          },
        ),
      );
      expect(toolResults.single.isError, isNull);

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.document);
      expect(source.title, 'Doc A');
      expect(source.mediaType, 'application/pdf');
    });

    test('web_fetch 错误 → isError ToolResult、无 citation 文档', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_2","name":"web_fetch",'
            '"input":{"url":"https://d.com/a.pdf"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"web_fetch_tool_result","tool_use_id":"srvtoolu_2",'
            '"content":{"type":"web_fetch_tool_result_error",'
            '"error_code":"url_not_accessible"}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"content_block_start","index":2,"content_block":'
            '{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":2,"delta":'
            '{"type":"citations_delta","citation":{"type":"char_location",'
            '"cited_text":"quote","document_index":0,"document_title":null,'
            '"start_char_index":1,"end_char_index":2}}}',
        '{"type":"content_block_stop","index":2}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'web_fetch',
          result: {
            'type': 'web_fetch_tool_result_error',
            'errorCode': 'url_not_accessible',
          },
          isError: true,
        ),
      );
      // document_index 0 无匹配文档(未追加 citationDocuments)→ 丢弃,无
      // document source。
      expect(parts.whereType<SourceContent>(), isEmpty);
    });
  });

  group('*_tool_result 块回流(第三批,原子到达)', () {
    test(
        'code_execution_tool_result 成功 → ToolResult(return_code 保留 '
        'snake_case)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"code_execution_tool_result",'
            '"tool_use_id":"srvtoolu_1","content":'
            '{"type":"code_execution_result","stdout":"hi\\n","stderr":"",'
            '"return_code":0,"content":[]}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_1',
          toolName: 'code_execution',
          result: {
            'type': 'code_execution_result',
            'stdout': 'hi\n',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        ),
      );
    });

    test('code_execution_tool_result_error → isError:true', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"code_execution_tool_result",'
            '"tool_use_id":"srvtoolu_2","content":'
            '{"type":"code_execution_tool_result_error",'
            '"error_code":"unavailable"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(
        parts.whereType<ToolResult>().single,
        const ToolResult(
          toolCallId: 'srvtoolu_2',
          toolName: 'code_execution',
          result: {
            'type': 'code_execution_tool_result_error',
            'errorCode': 'unavailable',
          },
          isError: true,
        ),
      );
    });

    test(
        'bash_code_execution_tool_result 错误变体 → 原样透传、不标 '
        'isError', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"bash_code_execution_tool_result",'
            '"tool_use_id":"srvtoolu_3","content":'
            '{"type":"bash_code_execution_tool_result_error",'
            '"error_code":"unavailable"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_3',
          toolName: 'code_execution',
          result: {
            'type': 'bash_code_execution_tool_result_error',
            'error_code': 'unavailable',
          },
        ),
      );
      expect(toolResults.single.isError, isNull);
    });

    test(
        'tool_search_tool_result 成功(有配对 server_tool_use)→ '
        'ToolResult', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_4",'
            // start input 恒空对象(真实流量形态;tool_search 分支空串
            // 起步 :1775,本用例只断结果块配对、不涉 input)。
            '"name":"tool_search_tool_bm25","input":{}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"tool_search_tool_result",'
            '"tool_use_id":"srvtoolu_4","content":'
            '{"type":"tool_search_tool_search_result","tool_references":'
            '[{"type":"tool_reference","tool_name":"get_weather"}]}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final toolResults = parts.whereType<ToolResult>().toList();
      expect(toolResults, hasLength(1));
      expect(
        toolResults.single,
        const ToolResult(
          toolCallId: 'srvtoolu_4',
          toolName: 'tool_search_tool_bm25',
          result: [
            {'type': 'tool_reference', 'toolName': 'get_weather'},
          ],
        ),
      );
    });

    test(
        'tool_search_tool_result deferred:本响应无配对 server_tool_use → '
        '恒落 tool_search_tool_regex(报告 09 §9.9)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"tool_search_tool_result",'
            '"tool_use_id":"srvtoolu_deferred","content":'
            '{"type":"tool_search_tool_search_result","tool_references":'
            '[{"type":"tool_reference","tool_name":"get_weather"}]}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(
        parts.whereType<ToolResult>().single.toolName,
        'tool_search_tool_regex',
      );
    });

    test(
        'advisor_tool_result:原子到达(无 delta),结果 part 出现在后续 '
        'text-start 之前(报告 09 §7.3 时序断言)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_5","name":"advisor",'
            '"input":{}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"advisor_tool_result","tool_use_id":"srvtoolu_5",'
            '"content":{"type":"advisor_result","text":"answer"}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"content_block_start","index":2,"content_block":'
            '{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":2,"delta":'
            '{"type":"text_delta","text":"done"}}',
        '{"type":"content_block_stop","index":2}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final resultIndex = parts.indexWhere((p) => p is ToolResult);
      final textStartIndex = parts.indexWhere((p) => p is TextStart);
      expect(resultIndex, greaterThanOrEqualTo(0));
      expect(textStartIndex, greaterThan(resultIndex));

      expect(
        parts.whereType<ToolResult>().single,
        const ToolResult(
          toolCallId: 'srvtoolu_5',
          toolName: 'advisor',
          result: {'type': 'advisor_result', 'text': 'answer'},
        ),
      );
    });

    test('advisor_redacted_result → encryptedContent(camel)原样回传', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"advisor_tool_result","tool_use_id":"srvtoolu_6",'
            '"content":{"type":"advisor_redacted_result",'
            '"encrypted_content":"opaque-blob"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(
        parts.whereType<ToolResult>().single,
        const ToolResult(
          toolCallId: 'srvtoolu_6',
          toolName: 'advisor',
          result: {
            'type': 'advisor_redacted_result',
            'encryptedContent': 'opaque-blob',
          },
        ),
      );
    });
  });

  group('dynamic 标记(doStream,三态,超上游覆盖,报告 09 §9.12)', () {
    test(
        '在场:web_search_20260209 + 无同名 code_execution 工具 → '
        'ToolInputStart/ToolCall 均 isDynamic:true', () async {
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":'
              '{"type":"server_tool_use","id":"srvtoolu_20",'
              '"name":"code_execution","input":{"code":"print(1)"}}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
              '"stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        tools: const [
          ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
        ],
      );

      expect(parts.whereType<ToolInputStart>().single.isDynamic, true);
      expect(parts.whereType<ToolCall>().single.isDynamic, true);
    });

    test('缺席:请求无 web 20260209 工具 → isDynamic:null', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_21",'
            '"name":"code_execution","input":{"code":"print(1)"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputStart>().single.isDynamic, isNull);
      expect(parts.whereType<ToolCall>().single.isDynamic, isNull);
    });

    test(
        '抑制:同名 code_execution function tool 在场 → isDynamic:null'
        '(报告 09 §3.1 :2694)', () async {
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":'
              '{"type":"server_tool_use","id":"srvtoolu_22",'
              '"name":"code_execution","input":{"code":"print(1)"}}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
              '"stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        tools: [
          const ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
          FunctionTool(
            name: 'code_execution',
            inputSchema: const JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(parts.whereType<ToolInputStart>().single.isDynamic, isNull);
      expect(parts.whereType<ToolCall>().single.isDynamic, isNull);
    });

    test(
        '子工具同样吃 dynamic 标记(defensive 恒真,报告 09 §9.5/spec 疑点 '
        '11)', () async {
      // fixture 形态说明:input 直接放 content_block_start 是「非空 start
      // input → 立即 jsonEncode」的合法分支(报告 09 §4.1),此处只为隔离
      // 断言 dynamic 标记;真实子工具流量是空 start + input_json_delta
      // (首 delta 注入 type),该形态已由 Task 9 注入用例覆盖。本形态无
      // delta,type 注入不发生(上游同理),与本断言无关。
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":'
              '{"type":"server_tool_use","id":"srvtoolu_23",'
              '"name":"bash_code_execution","input":{"command":"ls"}}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use",'
              '"stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        tools: const [
          ProviderTool(
            id: 'anthropic.web_search_20260209',
            name: 'web_search',
            args: {},
          ),
        ],
      );

      expect(parts.whereType<ToolCall>().single.isDynamic, true);
    });
  });

  group('citations_delta → SourceContent(Task 26)', () {
    // citations.enabled 的 text/plain 文档 prompt(报告 04 §6 :831-872 的
    // citationDocuments 初始来源)。
    final notesPrompt = <LanguageModelMessage>[
      UserMessage(<UserContentPart>[
        const FilePart(
          data: FileDataText('Dart is fun to learn'),
          mediaType: 'text/plain',
          filename: 'notes.txt',
          providerOptions: {
            'anthropic': {
              'citations': {'enabled': true},
            },
          },
        ),
        const TextPart('cite this'),
      ]),
    ];

    test('char_location → document source(报告 04 §6 :105-126)', () async {
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Dar"}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"char_location","cited_text":"Dart is fun","document_index":0,"document_title":"My Notes","start_char_index":3,"end_char_index":14}}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"t is fun"}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        prompt: notesPrompt,
      );

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.document);
      // document_title 优先于文档条目 title。
      expect(source.title, 'My Notes');
      expect(source.mediaType, 'text/plain');
      expect(source.filename, 'notes.txt');
      expect(source.id, isNotEmpty);
      expect(source.providerMetadata, {
        'anthropic': {
          'citedText': 'Dart is fun',
          'startCharIndex': 3,
          'endCharIndex': 14,
        },
      });
      // citation 不影响文本流本身。
      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((delta) => delta.delta).join(), 'Dart is fun');
    });

    test('web_search_result_location → url source(报告 04 §6 :79-93)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","cited_text":"cited","url":"https://example.com/a","title":"Example A","encrypted_index":"abc123"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.url);
      expect(source.url, 'https://example.com/a');
      expect(source.title, 'Example A');
      expect(source.id, isNotEmpty);
      expect(source.providerMetadata, {
        'anthropic': {
          'citedText': 'cited',
          'encryptedIndex': 'abc123',
        },
      });
    });

    test('document_index 查不到 → 丢弃,流不报错(:99-103)', () async {
      // 默认 _prompt 无可引用文档,page_location 查不到 document_index。
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"page_location","cited_text":"lost","document_index":0,"document_title":"X","start_page_number":1,"end_page_number":2}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      expect(parts.whereType<SourceContent>(), isEmpty);
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), hasLength(1));
    });

    test('探测型 media 对齐:顶级-only mediaType + PDF 魔数(偏离裁决,见 Task 19)', () async {
      final pdfBytes = Uint8List.fromList('%PDF-1.4'.codeUnits);
      final prompt = <LanguageModelMessage>[
        UserMessage(<UserContentPart>[
          FilePart(
            data: FileDataBytes(pdfBytes),
            mediaType: 'application',
            providerOptions: const {
              'anthropic': {
                'citations': {'enabled': true},
              },
            },
          ),
          const TextPart('cite this'),
        ]),
      ];
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"page_location","cited_text":"quote","document_index":0,"document_title":"T","start_page_number":2,"end_page_number":3}}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        prompt: prompt,
      );

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(1));
      final source = sources.single;
      expect(source.sourceType, SourceType.document);
      // 发送侧与收集侧同一套 resolved 判定 → 'application/pdf'。
      expect(source.mediaType, 'application/pdf');
    });
  });

  group('json 响应工具模式的流式路径(Task 27)', () {
    // 能力表不支持原生 json output 的模型 + json schema responseFormat
    // → 请求侧走 json tool 回退(Task 18),流侧走本组断言。
    const modelId = 'claude-3-haiku-20240307';
    const schema = JsonSchema({
      'type': 'object',
      'properties': {
        'answer': {'type': 'number'},
      },
      'required': ['answer'],
    });

    test(
        "json tool_use → 文本流:TextStart/Delta/End,id 用 String(index),tool_use→stop(:1635-1646,2251-2260,:353)",
        () async {
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_j","name":"json","input":{}}}',
          r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"answer\":"}}',
          r'{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"42}"}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        modelId: modelId,
        responseFormat: const ResponseFormatJson(schema: schema),
      );

      // json tool_use 不算真实工具调用:无任何 tool part。
      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);
      expect(parts.whereType<ToolCall>(), isEmpty);

      // json tool_use 块注册为 text 块,id 用 String(index)(:1635-1646)。
      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, '0');

      // input_json_delta 走 text-delta 且不累积 input(:2251-2260)。
      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((delta) => delta.id), everyElement('0'));
      expect(textDeltas.map((delta) => delta.delta).join(), '{"answer":42}');

      final textEnds = parts.whereType<TextEnd>().toList();
      expect(textEnds, hasLength(1));
      expect(textEnds.single.id, '0');

      // isJsonResponseFromTool → tool_use 映射 stop(:353)。
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.finishReason.raw, 'tool_use');
    });

    test('json 模式下普通 text 块整块忽略:无以 text 块索引为 id 的 part(:1585-1587,2188-2190)',
        () async {
      final parts = await _partsOf(
        _sseFrom([
          _messageStartData,
          '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I will return JSON"}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_j","name":"json","input":{}}}',
          r'{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"answer\":42}"}}',
          '{"type":"content_block_stop","index":1}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":25}}',
          _messageStopData,
        ]),
        modelId: modelId,
        responseFormat: const ResponseFormatJson(schema: schema),
      );

      // text 块(index 0)start/delta 整块忽略(:1585-1587,2188-2190);
      // 只有 json tool_use 块(index 1)以 text 形式输出。
      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, '1');

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((delta) => delta.id), everyElement('1'));
      expect(textDeltas.map((delta) => delta.delta).join(), '{"answer":42}');

      final textEnds = parts.whereType<TextEnd>().toList();
      expect(textEnds, hasLength(1));
      expect(textEnds.single.id, '1');

      expect(parts.whereType<ErrorPart>(), isEmpty);
    });
  });

  group('流式错误语义(Task 28)', () {
    // wire error 帧(报告 04 §8.1:Anthropic 在 overloaded 时也会返回
    // 200 + error 事件)。
    const overloadedErrorData =
        '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}';
    const apiErrorData =
        '{"type":"error","error":{"type":"api_error","message":"Internal server error"}}';

    /// 直接构造 model + client,断言 doStream 的 Future 抛错(预读路径)。
    Future<LanguageModelStreamResult> streamOf(String sseText) {
      final client = _RecordingClient((request) async => _sseResponse(sseText));
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );
      return model.doStream(const LanguageModelCallOptions(prompt: _prompt));
    }

    test('首 error 事件 overloaded → Future 抛 ApiCallError 529 可重试(:2543-2557)',
        () async {
      await expectLater(
        streamOf(_sseFrom([overloadedErrorData])),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.message, 'message', 'Overloaded')
              .having((error) => error.statusCode, 'statusCode', 529)
              .having((error) => error.isRetryable, 'isRetryable', isTrue)
              .having(
                (error) => error.responseBody,
                'responseBody',
                jsonEncode({
                  'type': 'overloaded_error',
                  'message': 'Overloaded',
                }),
              )
              .having((error) => error.data, 'data', {
            'type': 'overloaded_error',
            'message': 'Overloaded',
          }),
        ),
      );
    });

    test('首 error 事件非 overloaded → 500 且显式不可重试(:2554)', () async {
      await expectLater(
        streamOf(_sseFrom([apiErrorData])),
        throwsA(
          isA<ApiCallError>()
              .having(
                (error) => error.message,
                'message',
                'Internal server error',
              )
              .having((error) => error.statusCode, 'statusCode', 500)
              // 显式 false,不依赖 5xx 默认推断(上游
              // `isRetryable: error.type === 'overloaded_error'`)。
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('ping 后 error 仍算首个实义事件 → 照抛(:2534-2541)', () async {
      await expectLater(
        streamOf(_sseFrom(['{"type":"ping"}', overloadedErrorData])),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 529),
        ),
      );
    });

    test('message_start 之后的 error → 流内 ErrorPart 终态(:2515-2518)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}',
        overloadedErrorData,
      ]));

      // error-as-terminal:ErrorPart 恰 1 个且是最后一个,其后无
      // TextEnd/FinishPart(偏离上游"不 close")。
      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);

      // ErrorPart.error 为 error 事件的 `{type, message}` 对象。
      expect(errorParts.single.error, {
        'type': 'overloaded_error',
        'message': 'Overloaded',
      });

      // error 之前的文本流照常产出。
      expect(parts.whereType<TextStart>(), hasLength(1));
      expect(parts.whereType<TextDelta>(), hasLength(1));
    });

    test('chunk 解析失败(非法 JSON)→ ErrorPart 终态(:1556-1559)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{not-json}',
      ]));

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('范围外块类型(future_block)→ ErrorPart 终态(报告 04 §8.3 同构)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"future_block"}}',
        '{"type":"content_block_stop","index":0}',
      ]));

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      // ErrorPart 后无任何 part(content_block_stop 不再被消费)。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('连接级传输错误 → Future 正常完成,流内 ErrorPart 收尾(round-6 先例)', () async {
      // 先发正常帧再让字节流本身 addError(照 openai
      // `chat_language_model_stream_test.dart` 式样),模拟 SSE 中途断连。
      http.StreamedResponse transportErrorResponse() {
        late StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onListen: () async {
            controller.add(utf8.encode('data: $_messageStartData\n\n'));
            await Future<void>.delayed(Duration.zero);
            controller.add(utf8.encode(
              'data: {"type":"content_block_start","index":0,'
              '"content_block":{"type":"text","text":""}}\n\n',
            ));
            await Future<void>.delayed(Duration.zero);
            controller.addError(StateError('connection reset'));
            await controller.close();
          },
        );
        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }

      final client =
          _RecordingClient((request) async => transportErrorResponse());
      final model = AnthropicMessagesLanguageModel(
        'claude-sonnet-4-5',
        config: _config(client),
      );

      // doStream 本身不 throw(错误在 message_start 之后,不在预读窗口);
      // 连接级失败走流内 ErrorPart 终态。
      final result = await model.doStream(
        const LanguageModelCallOptions(prompt: _prompt),
      );
      final parts = await result.stream.toList();

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect(errorParts.single.error, isA<StateError>());
      expect(parts.whereType<FinishPart>(), isEmpty);
      // 断连前的正常帧照常产出。
      expect(parts.whereType<TextStart>(), hasLength(1));
    });
  });

  group('includeRawChunks 透传(Task 29)', () {
    test('开启时逐帧前置 RawPart:8 帧恰 8 个,含 ping/message_delta 等无实义帧', () async {
      final parts = await _partsOf(_streamText, includeRawChunks: true);

      // 8 帧 → RawPart 恰 8 个(:1552-1554),含 ping 与 message_delta
      // 这类不产出实义 part 的帧。
      final rawParts = parts.whereType<RawPart>().toList();
      expect(rawParts, hasLength(8));

      // rawValue 为该帧 data JSON 对象,按帧序对应 8 种事件类型。
      expect(
        rawParts
            .map((raw) => (raw.rawValue! as Map<String, Object?>)['type'])
            .toList(),
        [
          'message_start',
          'ping',
          'content_block_start',
          'content_block_delta',
          'content_block_delta',
          'content_block_stop',
          'message_delta',
          'message_stop',
        ],
      );

      // 首个 RawPart 位于 StreamStart 之后、ResponseMetadata 之前;每个
      // RawPart 先于同帧派生的其它 part(:1552-1554)——整序断言。
      expect(parts.map((part) => part.runtimeType).toList(), [
        StreamStart, // warnings 首发
        RawPart, // message_start
        ResponseMetadata,
        RawPart, // ping(无实义 part)
        RawPart, // content_block_start
        TextStart,
        RawPart, // content_block_delta
        TextDelta,
        RawPart, // content_block_delta
        TextDelta,
        RawPart, // content_block_stop
        TextEnd,
        RawPart, // message_delta(无实义 part)
        RawPart, // message_stop
        FinishPart,
      ]);
      expect(
        (rawParts.first.rawValue! as Map<String, Object?>)['type'],
        'message_start',
      );
    });

    test('解析失败帧也发 RawPart,位于 ErrorPart 之前', () async {
      final parts = await _partsOf(
        _sseFrom([_messageStartData, '{not-json}']),
        includeRawChunks: true,
      );

      // 两帧各一个 RawPart;非法 JSON 帧的 RawPart 紧邻 ErrorPart 之前。
      final rawParts = parts.whereType<RawPart>().toList();
      expect(rawParts, hasLength(2));
      expect(parts.last, isA<ErrorPart>());
      expect(parts[parts.length - 2], isA<RawPart>());
      // rawValue 透传 ParseFailure.rawValue(照 openai 先例;JSON 语法
      // 失败时 safeParseJson 无可回填原始值,为 null,原文在
      // JsonParseError.text 上)。
      expect(rawParts.last.rawValue, isNull);
      expect(
        (rawParts.first.rawValue! as Map<String, Object?>)['type'],
        'message_start',
      );
    });

    test('默认关闭:不传 includeRawChunks → 无任何 RawPart', () async {
      final parts = await _partsOf(_streamText);
      expect(parts.whereType<RawPart>(), isEmpty);
    });
  });

  group('批次三工具全链路 — doStream(报告 09 §7.1)', () {
    test(
        'code_execution(programmatic)全链:content_block_start 完整 input '
        '+ stop 时注入 type', () async {
      // 用"input 在 content_block_start 齐备到达"路径(报告 09 §4.1a
      // finalInput 非空分支),规避首 delta 字节替换 hack(T7-T10 自身测试
      // 已覆盖该 hack,§7 spec 明确列出)。stop 时的 programmatic 注入
      // (:2128-2149)与 doGenerate 的 JSON.stringify 同为无空格形态,断言
      // 因此可对齐。
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_ce2","name":'
            '"code_execution","input":{"code":"print(1)"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"code_execution_tool_result","tool_use_id":'
            '"srvtoolu_ce2","content":{"type":"encrypted_code_execution_result",'
            '"encrypted_stdout":"enc-blob","stderr":"","return_code":0,'
            '"content":[]}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_ce2');
      expect(call.toolName, 'code_execution');
      expect(call.providerExecuted, isTrue);
      expect(
        jsonDecode(call.input),
        {'type': 'programmatic-tool-call', 'code': 'print(1)'},
      );

      final toolResult = parts.whereType<ToolResult>().single;
      expect(
        toolResult,
        const ToolResult(
          toolCallId: 'srvtoolu_ce2',
          toolName: 'code_execution',
          result: {
            'type': 'encrypted_code_execution_result',
            'encrypted_stdout': 'enc-blob',
            'stderr': '',
            'return_code': 0,
            'content': <Object?>[],
          },
        ),
      );
    });

    test('tool_search(bm25)全链:完整事件序', () async {
      // fixture 形态(计划复审修订):照真实流量(报告 09 §7.1 bm25 样本)
      // ——start input 为空对象、input 全靠 input_json_delta 累积。上游
      // tool_search 分支硬编码空串起步(:1775,独立于 web/code_execution
      // 族的非空 start input 规则 :1722-1727),start 携带的非空 input 会被
      // 忽略,勿用那种形态造 fixture。
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_ts2","name":'
            '"tool_search_tool_bm25","input":{}}}',
        '{"type":"content_block_delta","index":0,"delta":'
            '{"type":"input_json_delta","partial_json":'
            '"{\\"query\\": \\"weather"}}',
        '{"type":"content_block_delta","index":0,"delta":'
            '{"type":"input_json_delta","partial_json":'
            '" forecast\\", \\"limit\\": 5}"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"tool_search_tool_result","tool_use_id":"srvtoolu_ts2",'
            '"content":{"type":"tool_search_tool_search_result",'
            '"tool_references":[{"type":"tool_reference","tool_name":'
            '"get_weather"}]}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_ts2');
      expect(call.toolName, 'tool_search_tool_bm25');
      expect(call.providerExecuted, isTrue);
      // input 断言(计划复审补):delta 累积产物,防"空串起步吞 input"类
      // 回归被 whereType 断言漏过。
      expect(
        jsonDecode(call.input),
        {'query': 'weather forecast', 'limit': 5},
      );

      final toolResult = parts.whereType<ToolResult>().single;
      expect(toolResult.toolCallId, 'srvtoolu_ts2');
      expect(toolResult.toolName, 'tool_search_tool_bm25');
      expect(
        toolResult.result,
        [
          {'type': 'tool_reference', 'toolName': 'get_weather'},
        ],
      );
    });

    test('advisor 全链:结果原子到达(无 delta)', () async {
      // 报告 09 §4.4 :2012-2013:"arrives fully formed in a single
      // content_block_start (no deltas)."
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"server_tool_use","id":"srvtoolu_adv2","name":"advisor",'
            '"input":{}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":'
            '{"type":"advisor_tool_result","tool_use_id":"srvtoolu_adv2",'
            '"content":{"type":"advisor_result","text":"Use a HashMap."}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'srvtoolu_adv2');
      expect(call.toolName, 'advisor');
      expect(jsonDecode(call.input), <String, Object?>{});

      final toolResult = parts.whereType<ToolResult>().single;
      expect(
        toolResult,
        const ToolResult(
          toolCallId: 'srvtoolu_adv2',
          toolName: 'advisor',
          result: {'type': 'advisor_result', 'text': 'Use a HashMap.'},
        ),
      );
    });

    test('memory 全链:普通 tool_use 流式解析,无 providerExecuted', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":'
            '{"type":"tool_use","id":"tu_mem2","name":"memory","input":'
            '{"command":"view","path":"/memories"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"tool_calls",'
            '"stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'tu_mem2');
      expect(call.toolName, 'memory');
      expect(call.providerExecuted, isNull);
      expect(
        jsonDecode(call.input),
        {'command': 'view', 'path': '/memories'},
      );
    });
  });

  group('doStream 三族新块(mcp/compaction/fallback)', () {
    test('compaction 全生命周期:metadata 只在 TextStart,delta 累积,stop 产 TextEnd',
        () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"compaction","content":null}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta","content":"summary of"}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta","content":" earlier turns"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}',
        _messageStopData,
      ]));

      final start = parts.whereType<TextStart>().single;
      expect(start.id, '0');
      expect(start.providerMetadata, {
        'anthropic': {'type': 'compaction'},
      });

      // delta 以普通 TextDelta 输出,无 metadata(:2233-2243)。
      final deltas = parts.whereType<TextDelta>().toList();
      expect(deltas.map((d) => d.id), everyElement('0'));
      expect(deltas.map((d) => d.delta).join(), 'summary of earlier turns');
      expect(deltas.map((d) => d.providerMetadata), everyElement(isNull));

      // stop 走既有 text 块状态机产普通 TextEnd,无 metadata。
      final end = parts.whereType<TextEnd>().single;
      expect(end.id, '0');
      expect(end.providerMetadata, isNull);

      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test('compaction_delta content null/缺席两态:静默无事件(报告 10 §9.5g)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"compaction"}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta","content":null}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta"}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta","content":"x"}}',
        '{"type":"content_block_stop","index":0}',
        _messageStopData,
      ]));

      // 显式 null 与缺席均静默无事件;仅非 null delta 产出。
      expect(parts.whereType<TextDelta>().map((d) => d.delta).toList(), ['x']);
      expect(parts.whereType<ErrorPart>(), isEmpty);
    });

    test('mcp_tool_use 一发完整 ToolCall:不注册块状态、无 ToolInput* 三段式', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"mcp_tool_use","id":"mcptoolu_1","name":"echo","server_name":"echo-server","input":{"message":"hello world"}}}',
        '{"type":"content_block_stop","index":0}',
        _messageStopData,
      ]));

      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputDelta>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);
      expect(
        parts.whereType<ToolCall>().single,
        const ToolCall(
          toolCallId: 'mcptoolu_1',
          toolName: 'echo',
          input: '{"message":"hello world"}',
          providerExecuted: true,
          isDynamic: true,
          providerMetadata: {
            'anthropic': {
              'type': 'mcp-tool-use',
              'serverName': 'echo-server',
            },
          },
        ),
      );
      // stop 对未注册块无事件:StreamStart + ResponseMetadata + ToolCall +
      // FinishPart = 4。
      expect(parts, hasLength(4));
    });

    test('mcp 两块配对:结果取配对调用的 toolName/providerMetadata', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"mcp_tool_use","id":"mcptoolu_1","name":"echo","server_name":"echo-server","input":{"message":"hi"}}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":{"type":"mcp_tool_result","tool_use_id":"mcptoolu_1","is_error":false,"content":[{"type":"text","text":"Tool echo: hi"}]}}',
        '{"type":"content_block_stop","index":1}',
        _messageStopData,
      ]));

      expect(
        parts.whereType<ToolResult>().single,
        const ToolResult(
          toolCallId: 'mcptoolu_1',
          toolName: 'echo',
          result: [
            {'type': 'text', 'text': 'Tool echo: hi'},
          ],
          isError: false,
          isDynamic: true,
          providerMetadata: {
            'anthropic': {
              'type': 'mcp-tool-use',
              'serverName': 'echo-server',
            },
          },
        ),
      );
      expect(parts.whereType<ErrorPart>(), isEmpty);
    });

    test('mcp_tool_result 无配对 → ErrorPart 终态(受控错误文案锁定)', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"mcp_tool_result","tool_use_id":"mcptoolu_9","is_error":false,"content":[]}}',
        '{"type":"content_block_stop","index":0}',
        _messageStopData,
      ]));

      final error = parts.whereType<ErrorPart>().single;
      expect(parts.last, isA<ErrorPart>());
      expect(
        (error.error! as FormatException).message,
        'mcp_tool_result block without matching mcp_tool_use: mcptoolu_9',
      );
      expect(parts.whereType<ToolResult>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('fallback 前置拦截:不产事件不报错,后续块照常', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"fallback"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"hi"}}',
        '{"type":"content_block_stop","index":1}',
        _messageStopData,
      ]));

      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<TextStart>().single.id, '1');
      expect(parts.whereType<TextDelta>().single.delta, 'hi');
      expect(parts.whereType<TextEnd>().single.id, '1');
      expect(parts.last, isA<FinishPart>());
    });

    test('与既有块并存:compaction + mcp 两块 + 普通 text 交错', () async {
      final parts = await _partsOf(_sseFrom([
        _messageStartData,
        '{"type":"content_block_start","index":0,"content_block":{"type":"compaction","content":null}}',
        '{"type":"content_block_delta","index":0,"delta":{"type":"compaction_delta","content":"sum"}}',
        '{"type":"content_block_stop","index":0}',
        '{"type":"content_block_start","index":1,"content_block":{"type":"mcp_tool_use","id":"mcptoolu_1","name":"echo","server_name":"s","input":{}}}',
        '{"type":"content_block_stop","index":1}',
        '{"type":"content_block_start","index":2,"content_block":{"type":"mcp_tool_result","tool_use_id":"mcptoolu_1","is_error":false,"content":["ok"]}}',
        '{"type":"content_block_stop","index":2}',
        '{"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}',
        '{"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"done"}}',
        '{"type":"content_block_stop","index":3}',
        _messageStopData,
      ]));

      // 两个文本块各自独立生命周期:compaction 块 id '0' 带 metadata,
      // 普通 text 块 id '3' 无 metadata。
      final starts = parts.whereType<TextStart>().toList();
      expect(starts, hasLength(2));
      expect(starts[0].id, '0');
      expect(starts[0].providerMetadata, {
        'anthropic': {'type': 'compaction'},
      });
      expect(starts[1].id, '3');
      expect(starts[1].providerMetadata, isNull);
      expect(parts.whereType<TextEnd>().map((e) => e.id).toList(), ['0', '3']);
      expect(parts.whereType<ToolCall>(), hasLength(1));
      expect(parts.whereType<ToolResult>(), hasLength(1));
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });
  });
}
