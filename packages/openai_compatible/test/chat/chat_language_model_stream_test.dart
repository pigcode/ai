import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 把三引号字符串字面量里每一行的前导空白去掉,使跟随 Dart 源码缩进
/// 书写的 SSE fixture 文本在解析时等价于零缩进版本(复制自
/// `packages/openai/test/chat/chat_language_model_stream_test.dart` 的
/// 同名辅助函数模式)。
String _flushLeft(String text) =>
    text.split('\n').map((line) => line.trimLeft()).join('\n');

http.StreamedResponse _sseResponse(String sseText) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(sseText)),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// 构造一个先正常发出一帧文本 delta、随后字节流本身 `addError`(而非发出
/// 错误帧内容)的 [http.StreamedResponse],模拟连接级传输失败(如 SSE
/// 中途断连)——区别于"服务端下发 `{"error":{...}}` 内容帧"的场景。
http.StreamedResponse _sseResponseWithTransportError() {
  late StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () async {
      controller.add(utf8.encode(_flushLeft('''
      data: {"id":"chatcmpl-6","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":"one"}}]}

      ''')));
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

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;
  Map<String, Object?>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastBody = jsonDecode(request.body) as Map<String, Object?>;
    }
    return handler(request);
  }
}

OpenAiCompatibleChatConfig _config(
  http.Client client, {
  bool includeUsage = false,
  MetadataExtractor? metadataExtractor,
  JsonObject Function(JsonObject args)? transformRequestBody,
  LanguageModelUsage Function(JsonObject usage)? convertUsage,
}) {
  return OpenAiCompatibleChatConfig(
    providerName: 'mycustom',
    url: (path) => Uri.parse('https://api.mycustom.dev/v1$path'),
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
    includeUsage: includeUsage,
    metadataExtractor: metadataExtractor,
    transformRequestBody: transformRequestBody,
    convertUsage: convertUsage,
  );
}

const _prompt = LanguageModelCallOptions(
  prompt: [
    UserMessage([TextPart('hi')]),
  ],
);

final _streamText = _flushLeft('''
data: {"id":"chatcmpl-1","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"content":" world"}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"my-model","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}

data: [DONE]

''');

/// `delta.reasoning_content` 形态的推理流(后接文本 delta)。
final _streamReasoningContent = _flushLeft('''
data: {"id":"chatcmpl-2","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"thinking"}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"reasoning_content":" hard"}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"content":"answer"}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');

/// `delta.reasoning` 形态的推理流(gpt-oss 方言,后接文本 delta)。
final _streamReasoningDialect = _flushLeft('''
data: {"id":"chatcmpl-3","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","reasoning":"thinking"}}]}

data: {"id":"chatcmpl-3","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"reasoning":" hard"}}]}

data: {"id":"chatcmpl-3","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"content":"answer"}}]}

data: {"id":"chatcmpl-3","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');

/// 缺 name 首块缓冲——单调用:首帧只有 id,第二帧只有 arguments 增量,
/// 第三帧才带 name + 收尾 arguments。
final _streamToolCallLateName = _flushLeft('''
data: {"id":"chatcmpl-4","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":""}}]}}]}

data: {"id":"chatcmpl-4","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"city\\":\\"s"}}]}}]}

data: {"id":"chatcmpl-4","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"f\\"}"}}]}}]}

data: {"id":"chatcmpl-4","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 缺 name 首块缓冲——乱序多调用交错:index 0/1 的首帧交替到达(均无
/// name),之后各自的补 name 帧也交替到达。
final _streamToolCallInterleaved = _flushLeft('''
data: {"id":"chatcmpl-5","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"arguments":"{\\"a\\""}}]}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","function":{"arguments":"{\\"b\\""}}]}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"tool_a","arguments":":1}"}}]}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"name":"tool_b","arguments":":2}"}}]}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// `index` 缺失但首帧就带全 id + name + 完整 arguments:跳过缓冲直达
/// tracker,正常产出 ToolCall。
final _streamToolCallNoIndex = _flushLeft('''
data: {"id":"chatcmpl-7","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-7","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// `index` 缺失且始终无 name(google 式极端场景):无缓冲保护,tracker
/// 立即报缺 name。
final _streamToolCallNoIndexNoName = _flushLeft('''
data: {"id":"chatcmpl-8","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"id":"call_1","function":{"arguments":"{}"}}]}}]}

data: [DONE]

''');

/// 有 index 但全程无 name:主循环内一直缓冲,flush 阶段强制转发触发
/// tracker 报缺 name。
final _streamToolCallNeverNamed = _flushLeft('''
data: {"id":"chatcmpl-9","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":"{}"}}]}}]}

data: [DONE]

''');

/// 带 name 但 arguments 恒为空(无参工具):tracker 的"可解析即定稿"
/// 探测永不触发,依赖流收尾的 finishAll 补发 ToolInputEnd + ToolCall。
final _streamToolCallEmptyArguments = _flushLeft('''
data: {"id":"chatcmpl-10","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"name":"refresh","arguments":""}}]}}]}

data: {"id":"chatcmpl-10","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 首帧带 name 不带 id(有 index,走缓冲路径):id 应由 [generateId] 合成
/// 兜底,不抛 InvalidResponseDataError(Fix 1)。
final _streamToolCallMissingId = _flushLeft('''
data: {"id":"chatcmpl-19","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-19","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// `index` 缺失且首帧即带 name 但不带 id(走直通分支):id 同样应合成兜底。
final _streamToolCallNoIndexMissingId = _flushLeft('''
data: {"id":"chatcmpl-20","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-20","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// `index` 缺失、首帧即带全 name+arguments 但不带 id,同时带
/// `extra_content.google.thought_signature`(走直通分支,Fix 2 回归用例):
/// 合成 id 必须与捕获 thought signature 用的 id 一致,否则签名会因「捕获用
/// 原始 null id」而丢失。
final _streamToolCallNoIndexMissingIdThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-22","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"},"extra_content":{"google":{"thought_signature":"sig-direct-no-id"}}}]}}]}

data: {"id":"chatcmpl-22","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 缺 id 且带 thought_signature(走缓冲路径,首帧无 id/name):验证合成 id
/// 兜底后 metadata 仍正常回读。
final _streamToolCallMissingIdThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-21","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"arguments":""},"extra_content":{"google":{"thought_signature":"sig-no-id"}}}]}}]}

data: {"id":"chatcmpl-21","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-21","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 正常路径(非缺 name 缓冲):首帧即带 id + name + 部分 arguments,后续两帧
/// 只携带同一 `index` 的 arguments 增量——覆盖 `forwardedIndices.contains
/// (index)` 继续分支(即 tracker `_continueCall` 路径),与「缺 name 缓冲」
/// 场景形成正向对照。
final _streamToolCallNormalContinuation = _flushLeft('''
data: {"id":"chatcmpl-16","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\":"}}]}}]}

data: {"id":"chatcmpl-16","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"s"}}]}}]}

data: {"id":"chatcmpl-16","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"f\\"}"}}]}}]}

data: {"id":"chatcmpl-16","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 首帧带 index + id + name(跳过缓冲直达 tracker,已转发),续片同一
/// `index` 但缺 `id`、带 `extra_content.google.thought_signature`(Fix 1
/// 回归场景)——续片必须按转发时敲定的原始 id(`call_1`)归桶签名,不能
/// 合成新 id,否则 [ToolCall](以原始 id 发出)查不到签名。
final _streamToolCallContinuationMissingIdThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-25","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\":"}}]}}]}

data: {"id":"chatcmpl-25","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"sf\\"}"},"extra_content":{"google":{"thought_signature":"sig-continuation"}}}]}}]}

data: {"id":"chatcmpl-25","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 缓冲路径转发后续片带签名(Fix 1 回归场景的缓冲变体):首帧缺 name 走
/// 缓冲,第二帧带 name 触发一次性转发(登记 `forwardedToolCallIds`),
/// 第三帧是已转发 index 的续片,缺 id 但带 thought_signature——必须归桶到
/// 转发时敲定的原始 id。
final _streamToolCallBufferedThenContinuationThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-26","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":""}}]}}]}

data: {"id":"chatcmpl-26","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":"}}]}}]}

data: {"id":"chatcmpl-26","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"sf\\"}"},"extra_content":{"google":{"thought_signature":"sig-buffered-continuation"}}}]}}]}

data: {"id":"chatcmpl-26","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 先正常输出一帧文本,随后服务端下发错误信封帧。
final _streamErrorFrameAfterOutput = _flushLeft('''
data: {"id":"chatcmpl-11","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":"partial"}}]}

data: {"error":{"message":"stream interrupted","type":"server_error","code":null}}

''');

/// refusal delta 流(超上游 refusal 支持,移植自 `pigcode_ai_openai` chat 同名
/// fixture):两帧 `delta.refusal` 增量,无 `delta.content`。
final _streamRefusal = _flushLeft('''
data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","refusal":"I cannot"}}]}

data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"refusal":" help with that."}}]}

data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');

/// refusal 帧后紧跟服务端错误信封帧:验证 refusal 输出仍走单一流内
/// error-as-terminal-event 路径,不受本包无 pre-output probe 的既定差异
/// 影响(本包 doStream 无 probe,故该场景无需 `_isChatOutputChunk` 式
/// 判定即可自然自洽——与 `pigcode_ai_openai` chat 的对应回归用例意图一致,
/// 但触发机制不同)。
final _streamRefusalThenError = _flushLeft('''
data: {"id":"chatcmpl-24","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","refusal":"I cannot"}}]}

data: {"error":{"message":"server exploded","type":"server_error"}}

data: [DONE]

''');

/// 首帧 `delta.role` 为空字符串(部分 provider 方言)。
final _streamEmptyRole = _flushLeft('''
data: {"id":"chatcmpl-12","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"","content":"hi"}}]}

data: {"id":"chatcmpl-12","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');

/// 首帧不带 id/model/created 的最小 chunk(响应元数据全空)。
final _streamNoMetadata = _flushLeft('''
data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');

/// 工具调用首帧即带全 id + name + `extra_content.google.thought_signature`
/// (跳过缓冲直达 tracker 的路径)。
final _streamToolCallThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-13","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"},"extra_content":{"google":{"thought_signature":"sig-xyz"}}}]}}]}

data: {"id":"chatcmpl-13","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 工具调用首帧带全 id + name + 空串 `extra_content.google.thought_signature`
/// (跳过缓冲直达 tracker 的路径)——验证空串按 JS truthiness 视同未提供。
final _streamToolCallEmptyThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-13b","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"id":"call_1","function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"},"extra_content":{"google":{"thought_signature":""}}}]}}]}

data: {"id":"chatcmpl-13b","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 缺 name 首块缓冲场景下,`extra_content` 出现在首帧(尚无 name),补 name
/// 的第二帧不再带 `extra_content`——验证「首次捕获后不被后续分片覆盖」的
/// 合并策略,以及缓冲路径下的 thought signature 仍能正确回读。
final _streamToolCallLateNameThoughtSignature = _flushLeft('''
data: {"id":"chatcmpl-14","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":""},"extra_content":{"google":{"thought_signature":"sig-buffered"}}}]}}]}

data: {"id":"chatcmpl-14","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-14","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');

/// 收尾 usage 帧带 `completion_tokens_details.accepted/rejected_prediction_
/// tokens`。
final _streamUsagePredictionTokens = _flushLeft('''
data: {"id":"chatcmpl-15","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

data: {"id":"chatcmpl-15","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-15","created":1700000000,"model":"my-model","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"completion_tokens_details":{"accepted_prediction_tokens":3,"rejected_prediction_tokens":1}}}

data: [DONE]

''');

/// 一帧正常文本 delta 后紧跟一帧语法非法的 JSON(SSE 帧级解析失败)。
final _streamMalformedJsonFrame = _flushLeft('''
data: {"id":"chatcmpl-17","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":"partial"}}]}

data: {this is not valid json}

''');

/// 错误信封帧先于任何输出到达(首帧即错误,无任何文本/推理/工具调用先行)。
final _streamErrorFrameBeforeAnyOutput = _flushLeft('''
data: {"error":{"message":"immediate failure","type":"server_error","code":null}}

''');

void main() {
  group('OpenAiCompatibleChatLanguageModel.doStream', () {
    test('文本流:惰性 txt-0 start/delta/end,FinishPart 收尾且为最后分块', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(parts.first, isA<StreamStart>());

      final metadata = parts.whereType<ResponseMetadata>().single;
      expect(metadata.id, 'chatcmpl-1');
      expect(metadata.modelId, 'my-model');

      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, 'txt-0');

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.delta).join(), 'Hello world');
      for (final delta in textDeltas) {
        expect(delta.id, 'txt-0');
      }

      expect(parts.whereType<TextEnd>().single.id, 'txt-0');

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.finishReason.raw, 'stop');
      expect(finish.usage.inputTokens.total, 10);
      expect(finish.usage.outputTokens.total, 2);
      expect(finish.providerMetadata, {'mycustom': const <String, Object?>{}});
      expect(parts.last, isA<FinishPart>());

      // TextEnd 出现在 TextStart 之后、FinishPart 之前的正确顺序。
      expect(
        parts.indexWhere((p) => p is TextEnd),
        greaterThan(parts.indexWhere((p) => p is TextStart)),
      );
    });

    test(
        'refusal delta 流:两帧 refusal 合并为 TextDelta ×2 + TextEnd 带 '
        'refusal 标记(超上游支持,移植自 pigcode_ai_openai chat)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamRefusal),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas, hasLength(2));
      expect(textDeltas.map((d) => d.delta).join(), 'I cannot help with that.');

      final textEnd = parts.whereType<TextEnd>().single;
      expect(textEnd.providerMetadata?['mycustom']?['refusal'], isTrue);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        'refusal 帧后跟错误帧:refusal 输出保留,ErrorPart 走流内终态路径'
        '(不回归本包无 pre-output probe 的既定差异)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamRefusalThenError),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(
        parts.whereType<TextDelta>().map((d) => d.delta).join(),
        'I cannot',
      );
      final errorPart = parts.whereType<ErrorPart>().single;
      expect(errorPart.error, 'server exploded');
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('普通文本流不带 refusal 标记(不回归):TextEnd.providerMetadata 为 null', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final textEnd = parts.whereType<TextEnd>().single;
      expect(textEnd.providerMetadata, isNull);
    });

    test('首个 chunk 无 id/model/created 也无条件产出一次 ResponseMetadata', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamNoMetadata),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final metadata = parts.whereType<ResponseMetadata>().single;
      expect(metadata.id, isNull);
      expect(metadata.modelId, isNull);
      expect(metadata.timestamp, isNull);
    });

    for (final (fieldName, sse) in [
      ('reasoning_content', _streamReasoningContent),
      ('reasoning', _streamReasoningDialect),
    ]) {
      test(
          '推理流($fieldName 形态):reasoning-0 三连,ReasoningEnd 在 '
          'TextStart 之前', () async {
        final client = _RecordingClient(
          (request) async => _sseResponse(sse),
        );
        final model = OpenAiCompatibleChatLanguageModel(
          'my-model',
          config: _config(client),
        );

        final result = await model.doStream(_prompt);
        final parts = await result.stream.toList();

        expect(parts.whereType<ReasoningStart>().single.id, 'reasoning-0');
        final reasoningDeltas = parts.whereType<ReasoningDelta>().toList();
        expect(reasoningDeltas.map((d) => d.delta).join(), 'thinking hard');
        expect(parts.whereType<ReasoningEnd>().single.id, 'reasoning-0');

        expect(
          parts.whereType<TextDelta>().map((d) => d.delta).join(),
          'answer',
        );

        // 推理块必须在文本块开始前关闭。
        expect(
          parts.indexWhere((p) => p is ReasoningEnd),
          lessThan(parts.indexWhere((p) => p is TextStart)),
        );
        expect(parts.last, isA<FinishPart>());
      });
    }

    test('缺 name 首块缓冲(单调用):id 与累积 arguments 一次性转发', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallLateName),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');

      expect(parts.whereType<ErrorPart>(), isEmpty);
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
      expect(parts.last, isA<FinishPart>());
    });

    test('缺 name 首块缓冲(乱序多调用交错):index 0/1 各自正确 flush,不串号', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallInterleaved),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCalls = parts.whereType<ToolCall>().toList();
      expect(toolCalls, hasLength(2));

      final callA =
          toolCalls.singleWhere((call) => call.toolCallId == 'call_a');
      expect(callA.toolName, 'tool_a');
      expect(callA.input, '{"a":1}');

      final callB =
          toolCalls.singleWhere((call) => call.toolCallId == 'call_b');
      expect(callB.toolName, 'tool_b');
      expect(callB.input, '{"b":2}');

      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test('index 缺失且首帧带全 name:跳过缓冲直达 tracker,正常产出 ToolCall', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNoIndex),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        'index 缺失且始终无 name:tracker 缺 name 异常经主循环 catch 转 '
        'ErrorPart 终态', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNoIndexNoName),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final errorPart = parts.whereType<ErrorPart>().single;
      expect(errorPart.error, isA<InvalidResponseDataError>());
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test(
        'flush 时仍 pending(有 index 无 name):tracker 异常以 Stream.error '
        '传播', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNeverNamed),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      await expectLater(
        result.stream.toList(),
        throwsA(isA<InvalidResponseDataError>()),
      );
    });

    test('带 name 但 arguments 恒为空:流收尾 finishAll 补发 ToolCall', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallEmptyArguments),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'refresh');
      expect(toolCall.input, '');
      expect(parts.whereType<ToolInputEnd>(), hasLength(1));
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test('首帧带 name 不带 id(缓冲路径):id 合成兜底,流不终止(Fix 1)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallMissingId),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test('index 缺失且首帧带 name 不带 id(直通路径):id 合成兜底,流不终止(Fix 1)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNoIndexMissingId),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test('缺 id 且带 thought_signature:合成 id 兜底后 metadata 仍正常回读(Fix 1)', () async {
      final client = _RecordingClient(
        (request) async =>
            _sseResponse(_streamToolCallMissingIdThoughtSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-no-id'},
      );
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        'index 缺失(直通分支)+ 缺 id + 带 thought_signature:合成 id 先定稿再'
        '两用,捕获与转发用同一个 id,签名不丢(Fix 2)', () async {
      final client = _RecordingClient(
        (request) async =>
            _sseResponse(_streamToolCallNoIndexMissingIdThoughtSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-direct-no-id'},
      );
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        '正常路径(首帧带 name):后续同 index 的 arguments 增量走 '
        'forwardedIndices 继续分支,ToolInputStart/Delta 序列与最终拼接均正确', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNormalContinuation),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolInputStart = parts.whereType<ToolInputStart>().single;
      expect(toolInputStart.id, 'call_1');
      expect(toolInputStart.toolName, 'get_weather');

      final toolInputDeltas = parts.whereType<ToolInputDelta>().toList();
      expect(toolInputDeltas, isNotEmpty);
      for (final delta in toolInputDeltas) {
        expect(delta.id, 'call_1');
      }
      expect(
        toolInputDeltas.map((d) => d.delta).join(),
        '{"city":"sf"}',
      );

      // ToolInputStart 必须先于所有 ToolInputDelta。
      expect(
        parts.indexWhere((p) => p is ToolInputStart),
        lessThan(parts.indexWhere((p) => p is ToolInputDelta)),
      );

      expect(parts.whereType<ToolInputEnd>(), hasLength(1));
      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');

      expect(parts.whereType<ErrorPart>(), isEmpty);
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        '直通路径续片(index 已转发)缺 id 但带 thought_signature:按转发时'
        '敲定的原始 id 归桶,ToolCall(原始 id)携带该签名(Fix 1)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(
          _streamToolCallContinuationMissingIdThoughtSignature,
        ),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-continuation'},
      );
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        '缓冲路径转发后的续片缺 id 但带 thought_signature:同样按转发 id '
        '归桶,不丢签名(Fix 1)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(
          _streamToolCallBufferedThenContinuationThoughtSignature,
        ),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-buffered-continuation'},
      );
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        '工具调用带 extra_content.google.thought_signature 时回读进 '
        'ToolCall.providerMetadata', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallThoughtSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-xyz'},
      );
    });

    test(
        '缺 name 首块缓冲场景下 thought_signature 出现在首帧(补 name 帧不再带):'
        '仍正确回读且不被后续分片覆盖', () async {
      final client = _RecordingClient(
        (request) async =>
            _sseResponse(_streamToolCallLateNameThoughtSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-buffered'},
      );
    });

    test('无 extra_content 时 ToolCall.providerMetadata 为 null(不回归既有行为)',
        () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallNoIndex),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.providerMetadata, isNull);
    });

    test('thought_signature 为空串时视同未提供,ToolCall.providerMetadata 为 null(Fix 4)',
        () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamToolCallEmptyThoughtSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.providerMetadata, isNull);
    });

    test(
        '缓冲路径的空串 thought_signature 同样视同未提供'
        '(codex PR#5 round-3:此前缓冲写入只查 null,空串会占位并进 metadata)', () async {
      // 首帧走缓冲(index 无 name)且带空串签名,次帧带 name 转发。
      final bufferedEmptySignature = _flushLeft('''
data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":""},"extra_content":{"google":{"thought_signature":""}}}]}}]}

data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-23","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');
      final client = _RecordingClient(
        (request) async => _sseResponse(bufferedEmptySignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.providerMetadata, isNull);
    });

    test('缓冲期间空串签名不占位,后续帧的非空签名仍被采用', () async {
      // 首帧空串签名(不占位),次帧非空签名 + name。
      final emptyThenRealSignature = _flushLeft('''
data: {"id":"chatcmpl-24","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"arguments":""},"extra_content":{"google":{"thought_signature":""}}}]}}]}

data: {"id":"chatcmpl-24","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\\"city\\":\\"sf\\"}"},"extra_content":{"google":{"thought_signature":"sig-late"}}}]}}]}

data: {"id":"chatcmpl-24","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');
      final client = _RecordingClient(
        (request) async => _sseResponse(emptyThenRealSignature),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final toolCall = parts.whereType<ToolCall>().single;
      expect(
        toolCall.providerMetadata?['mycustom'],
        {'thoughtSignature': 'sig-late'},
      );
    });

    test('错误信封帧:该帧前输出保留,ErrorPart 为最后分块,无 TextEnd/FinishPart', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamErrorFrameAfterOutput),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(
        parts.whereType<TextDelta>().map((d) => d.delta).join(),
        'partial',
      );
      final errorPart = parts.whereType<ErrorPart>().single;
      expect(errorPart.error, 'stream interrupted');
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('SSE 帧级解析失败:一帧正常后接一帧非法 JSON,ErrorPart 终态无 FinishPart', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamMalformedJsonFrame),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(
        parts.whereType<TextDelta>().map((d) => d.delta).join(),
        'partial',
      );
      final errorPart = parts.whereType<ErrorPart>().single;
      expect(errorPart.error, isNotNull);
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test(
        '错误帧先于任何输出到达:doStream 返回的 Future 不抛,流为 '
        '[StreamStart, ErrorPart](与 pigcode_ai_openai 的核心差异——无 '
        'throwIfStreamErrorBeforeOutput 式 probe)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamErrorFrameBeforeAnyOutput),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(parts, hasLength(2));
      expect(parts[0], isA<StreamStart>());
      expect(parts[1], isA<ErrorPart>());
      expect((parts[1] as ErrorPart).error, 'immediate failure');
    });

    test('includeUsage 默认 false:请求体不含 stream_options', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      await result.stream.drain<void>();

      expect(client.lastBody!['stream'], true);
      expect(client.lastBody!.containsKey('stream_options'), isFalse);
    });

    test('includeUsage: true:请求体带 stream_options.include_usage', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client, includeUsage: true),
      );

      final result = await model.doStream(_prompt);
      await result.stream.drain<void>();

      expect(client.lastBody!['stream'], true);
      expect(client.lastBody!['stream_options'], {'include_usage': true});
    });

    test('delta.role 空字符串容忍:正常产出文本 delta', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamEmptyRole),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(parts.whereType<TextDelta>().single.delta, 'hi');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        'metadataExtractor:processChunk 逐 chunk 调用,buildMetadata 进 '
        'FinishPart.providerMetadata', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          metadataExtractor: MetadataExtractor(
            extractMetadata: (parsedBody) async => null,
            createStreamExtractor: () {
              var count = 0;
              return StreamMetadataExtractor(
                processChunk: (_) => count++,
                buildMetadata: () => {
                  'mycustom': {'chunkCount': count},
                },
              );
            },
          ),
        ),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      // _streamText 含 5 个成功解析的数据帧([DONE] 哨兵被 SSE 解析层跳过,
      // 不会进入 processChunk)。
      expect(finish.providerMetadata?['mycustom'], {'chunkCount': 5});
    });

    test(
        'usage.completion_tokens_details 带 accepted/rejected prediction '
        'tokens 时回读进 FinishPart.providerMetadata', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamUsagePredictionTokens),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.providerMetadata?['mycustom'], {
        'acceptedPredictionTokens': 3,
        'rejectedPredictionTokens': 1,
      });
    });

    test(
        '无 completion_tokens_details 时 FinishPart.providerMetadata 不含 '
        'prediction token 键(不回归既有行为)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.providerMetadata, {'mycustom': const <String, Object?>{}});
    });

    test(
        'prediction tokens 与 streamExtractor.buildMetadata 结果合并:'
        'extractor 的其他键保留,两字段追加在其上', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamUsagePredictionTokens),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          metadataExtractor: MetadataExtractor(
            extractMetadata: (parsedBody) async => null,
            createStreamExtractor: () => StreamMetadataExtractor(
              processChunk: (_) {},
              buildMetadata: () => {
                'mycustom': {'extra': 1},
              },
            ),
          ),
        ),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.providerMetadata?['mycustom'], {
        'extra': 1,
        'acceptedPredictionTokens': 3,
        'rejectedPredictionTokens': 1,
      });
    });

    test('convertUsage 覆盖:FinishPart.usage 用自定义转换结果', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          convertUsage: (usage) => const LanguageModelUsage(
            inputTokens: InputTokens(total: 999),
            outputTokens: OutputTokens(),
          ),
        ),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.usage.inputTokens.total, 999);
    });

    test('无 usage 帧时 FinishPart.usage 全字段显式为 null(不调用自定义转换)', () async {
      var customCalled = false;
      final client = _RecordingClient(
        (request) async => _sseResponse(_flushLeft('''
        data: {"id":"chatcmpl-18","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

        data: {"id":"chatcmpl-18","created":1700000000,"model":"my-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        ''')),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          convertUsage: (usage) {
            customCalled = true;
            return const LanguageModelUsage(
              inputTokens: InputTokens(total: 999),
              outputTokens: OutputTokens(),
            );
          },
        ),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(customCalled, isFalse);
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.usage.inputTokens.total, isNull);
      expect(finish.usage.inputTokens.noCache, isNull);
      expect(finish.usage.inputTokens.cacheRead, isNull);
      expect(finish.usage.inputTokens.cacheWrite, isNull);
      expect(finish.usage.outputTokens.total, isNull);
      expect(finish.usage.outputTokens.text, isNull);
      expect(finish.usage.outputTokens.reasoning, isNull);
    });

    test('includeRawChunks: true 时逐帧产出 RawPart(含非法 JSON 帧)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamMalformedJsonFrame),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')]),
          ],
          includeRawChunks: true,
        ),
      );
      final parts = await result.stream.toList();

      final rawParts = parts.whereType<RawPart>().toList();
      // 一帧正常 + 一帧非法 JSON,均各自产出一个 RawPart(语法解析阶段失败
      // 的 rawValue 按 [ParseFailure] 文档语义通常为 null,但 RawPart 事件
      // 本身仍会产出——这正是本测试要覆盖的行为)。
      expect(rawParts, hasLength(2));
      expect(rawParts[0].rawValue, isNotNull);

      // RawPart 先于对应帧被判定为错误而终止流。
      expect(
        parts.indexWhere((p) => p is RawPart),
        lessThan(parts.indexWhere((p) => p is ErrorPart)),
      );
    });

    test('连接级传输错误:已产出文本保留,ErrorPart 为最后分块,无 FinishPart', () async {
      final client = _RecordingClient(
        (request) async => _sseResponseWithTransportError(),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      final parts = await result.stream.toList();

      expect(parts.whereType<TextDelta>().map((d) => d.delta).join(), 'one');
      final errorPart = parts.whereType<ErrorPart>().single;
      expect(errorPart.error, isA<StateError>());
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('transformRequestBody 在流式路径生效,且拿到含 stream 的完整视图', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(
          client,
          transformRequestBody: (args) => {...args, 'custom_field': 'v'},
        ),
      );

      final result = await model.doStream(_prompt);
      await result.stream.drain<void>();

      expect(client.lastBody!['custom_field'], 'v');
      expect(client.lastBody!['stream'], true);
    });

    test('doStream 结果携带请求体与响应头', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_streamText),
      );
      final model = OpenAiCompatibleChatLanguageModel(
        'my-model',
        config: _config(client),
      );

      final result = await model.doStream(_prompt);
      await result.stream.drain<void>();

      expect(
        (result.request?.body as Map<String, Object?>?)?['stream'],
        true,
      );
      expect(result.response?.headers?['content-type'], 'text/event-stream');
    });
  });
}
