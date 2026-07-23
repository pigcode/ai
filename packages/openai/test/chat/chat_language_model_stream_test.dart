import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// 把三引号字符串字面量里每一行的前导空白去掉,使跟随 Dart 源码缩进
/// 书写的 SSE fixture 文本在解析时等价于零缩进版本(见
/// `test/responses/responses_language_model_test.dart` 的同名辅助函数)。
String _flushLeft(String text) =>
    text.split('\n').map((line) => line.trimLeft()).join('\n');

final _chatStreamText = _flushLeft('''
data: {"id":"chatcmpl-1","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":" world"}}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-1","created":1700000000,"model":"gpt-4o","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}

data: [DONE]

''');

final _chatStreamToolCall = _flushLeft('''
data: {"id":"chatcmpl-2","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"city\\""}}]}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"sf\\"}"}}]}}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: {"id":"chatcmpl-2","created":1700000000,"model":"gpt-4o","choices":[],"usage":{"prompt_tokens":8,"completion_tokens":6,"total_tokens":14}}

data: [DONE]

''');

final _chatStreamUsageOnly = _flushLeft('''
data: {"id":"chatcmpl-3","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

data: {"id":"chatcmpl-3","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":1,"total_tokens":4}}

data: [DONE]

''');

final _chatStreamRefusal = _flushLeft('''
data: {"id":"chatcmpl-5","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","refusal":"I cannot"}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"refusal":" help with that."}}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-5","created":1700000000,"model":"gpt-4o","choices":[],"usage":{"prompt_tokens":6,"completion_tokens":4,"total_tokens":10}}

data: [DONE]

''');

final _chatStreamLogprobsAndPrediction = _flushLeft('''
data: {"id":"chatcmpl-9","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

data: {"id":"chatcmpl-9","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop","logprobs":{"content":[{"token":"hi","logprob":-0.1,"bytes":[104,105],"top_logprobs":[]}]}}]}

data: {"id":"chatcmpl-9","created":1700000000,"model":"gpt-4o","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7,"completion_tokens_details":{"accepted_prediction_tokens":3,"rejected_prediction_tokens":1}}}

data: [DONE]

''');

final _chatStreamAnnotations = _flushLeft('''
data: {"id":"chatcmpl-8","created":1700000000,"model":"gpt-4o-search-preview","choices":[{"index":0,"delta":{"role":"assistant","content":"See "}}]}

data: {"id":"chatcmpl-8","created":1700000000,"model":"gpt-4o-search-preview","choices":[{"index":0,"delta":{"content":"below."}}]}

data: {"id":"chatcmpl-8","created":1700000000,"model":"gpt-4o-search-preview","choices":[{"index":0,"delta":{"annotations":[{"type":"url_citation","url_citation":{"url":"https://example.com/a","title":"Example A"}}]}}]}

data: {"id":"chatcmpl-8","created":1700000000,"model":"gpt-4o-search-preview","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-8","created":1700000000,"model":"gpt-4o-search-preview","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":3,"total_tokens":8}}

data: [DONE]

''');

final _chatStreamErrorBeforeOutput = _flushLeft('''
data: {"error":{"message":"The server had an error processing your request","type":"server_error","code":null}}

''');

final _chatStreamMetadataFrameThenErrorBeforeOutput = _flushLeft('''
data: {"id":"chatcmpl-7","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant"}}]}

data: {"error":{"message":"The server had an error processing your request","type":"server_error","code":null}}

''');

final _chatStreamErrorAfterOutput = _flushLeft('''
data: {"id":"chatcmpl-4","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"partial"}}]}

data: {"error":{"message":"stream interrupted","type":"server_error","code":null}}

''');

http.StreamedResponse _sseResponse(String sseText) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(sseText)),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// 构造一个先正常发出两帧文本 delta、随后字节流本身 `addError`(而非发出
/// 错误帧内容)的 [http.StreamedResponse],用于模拟连接级传输失败(如
/// SSE 中途断连)——区别于 `_chatStreamErrorAfterOutput` 那种"服务端下发
/// 了 `{"error":{...}}` 内容帧"的场景。
http.StreamedResponse _sseResponseWithTransportError() {
  late StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () async {
      controller.add(utf8.encode(_flushLeft('''
data: {"id":"chatcmpl-6","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":"one"}}]}

''')));
      await Future<void>.delayed(Duration.zero);
      controller.add(utf8.encode(_flushLeft('''
data: {"id":"chatcmpl-6","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"content":"two"}}]}

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

/// 构造一个字节流未产出任何内容就直接 `addError`(而非先发出正常帧)的
/// [http.StreamedResponse],用于模拟 probe 窗口内(首个可解析事件之前)
/// 发生的连接级传输失败——区别于 `_sseResponseWithTransportError` 那种
/// "先有正常输出、之后才断连"的场景。
http.StreamedResponse _sseResponseWithTransportErrorBeforeOutput() {
  late StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () async {
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

OpenAiConfig _config(http.Client client) {
  return OpenAiConfig(
    providerName: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
  );
}

void main() {
  // Compatibility fixture (unit): P1-OPENAI-03
  group('OpenAiChatLanguageModel.doStream', () {
    test('请求体无条件带 stream_options.include_usage', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamText),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      await result.stream.drain<void>();

      expect(client.lastBody!['stream'], true);
      expect(client.lastBody!['stream_options'], {'include_usage': true});
    });

    test('文本流:惰性 text-start + text-delta + text-end,usage 覆盖', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamText),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      expect(parts.whereType<StreamStart>(), hasLength(1));
      expect(parts.whereType<ResponseMetadata>(), hasLength(1));
      expect(
        (parts.whereType<ResponseMetadata>().single).id,
        'chatcmpl-1',
      );

      final textStarts = parts.whereType<TextStart>().toList();
      expect(textStarts, hasLength(1));
      expect(textStarts.single.id, '0');

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.delta).join(), 'Hello world');
      for (final delta in textDeltas) {
        expect(delta.id, '0');
      }

      final textEnd = parts.whereType<TextEnd>().single;
      // 正常文本流(非 refusal)不应带 refusal 标记。
      expect(textEnd.providerMetadata, isNull);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.usage.inputTokens.total, 10);
      expect(finish.usage.outputTokens.total, 2);

      // finish 必须是最后一个分块。
      expect(parts.last, isA<FinishPart>());
    });

    test('工具调用流:经 StreamingToolCallTracker 拼接完整 ToolCall', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamToolCall),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('call a tool')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      expect(parts.whereType<ToolInputStart>(), hasLength(1));
      final toolCall = parts.whereType<ToolCall>().single;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, '{"city":"sf"}');

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('refusal delta 流:两帧 refusal 合并为 TextDelta ×2 + 正常 Finish', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamRefusal),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas, hasLength(2));
      expect(textDeltas.map((d) => d.delta).join(), 'I cannot help with that.');

      final textEnd = parts.whereType<TextEnd>().single;
      expect(textEnd.providerMetadata?['openai']?['refusal'], isTrue);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(parts.last, isA<FinishPart>());
    });

    test(
        'refusal delta 流 + azure provider 名:TextEnd.providerMetadata 的 '
        "refusal 标记键为 'azure' 而非 'openai'", () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamRefusal),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-4o',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final textEnd = parts.whereType<TextEnd>().single;
      expect(textEnd.providerMetadata?['azure']?['refusal'], isTrue);
      expect(textEnd.providerMetadata?['openai'], isNull);
    });

    test(
        'choice.logprobs.content + usage.completion_tokens_details 非空时 '
        'FinishPart.providerMetadata 含 logprobs/acceptedPredictionTokens/'
        'rejectedPredictionTokens', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamLogprobsAndPrediction),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: <String, JsonObject>{
            'openai': <String, Object?>{'logprobs': true},
          },
        ),
      );
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.providerMetadata?['openai']?['logprobs'], isNotNull);
      expect(
          finish.providerMetadata?['openai']?['acceptedPredictionTokens'], 3);
      expect(
          finish.providerMetadata?['openai']?['rejectedPredictionTokens'], 1);
    });

    test('无 logprobs/prediction tokens 字段时 FinishPart.providerMetadata 不含对应键',
        () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamText),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      final openaiMetadata = finish.providerMetadata?['openai'];
      expect(openaiMetadata, isNotNull);
      expect(openaiMetadata!.containsKey('logprobs'), isFalse);
      expect(openaiMetadata.containsKey('acceptedPredictionTokens'), isFalse);
      expect(openaiMetadata.containsKey('rejectedPredictionTokens'), isFalse);
    });

    test(
        "azure provider 名下 doStream 的 FinishPart.providerMetadata 用 'azure' "
        '派生 key', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamLogprobsAndPrediction),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-4o',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.providerMetadata?['azure']?['logprobs'], isNotNull);
      expect(finish.providerMetadata?['azure']?['acceptedPredictionTokens'], 3);
      expect(finish.providerMetadata?.containsKey('openai'), isFalse);
    });

    test(
        'refusal delta 视为 output chunk:其后的错误帧走流内 ErrorPart,'
        '不再被 probe 误判为 before-output 从 Future 抛出', () async {
      // refusal 帧后跟服务端错误帧:probe 的 output 判定含非空
      // `delta.refusal`(本实现超上游把 refusal 映射为文本输出,判定
      // 须自洽),故探测在首个 refusal 帧即停止,错误帧由流状态机按
      // error-as-terminal-event 语义处理。
      final refusalThenError = _flushLeft('''
data: {"id":"chatcmpl-6","created":1700000000,"model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","refusal":"I cannot"}}]}

data: {"error":{"message":"server exploded","type":"server_error"}}

data: [DONE]

''');
      final client = _RecordingClient(
        (request) async => _sseResponse(refusalThenError),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('do something disallowed')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.delta).join(), 'I cannot');
      expect(parts.whereType<ErrorPart>(), hasLength(1));
      // error-as-terminal-event:ErrorPart 即最后一个分块,无 FinishPart。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('delta.annotations 流:在对应 text 之后产出 SourceContent part', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamAnnotations),
      );
      final model = OpenAiChatLanguageModel(
        'gpt-4o-search-preview',
        config: _config(client),
      );

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('what is the source?')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.delta).join(), 'See below.');

      final textEndIndex = parts.indexWhere((p) => p is TextEnd);
      final sourceIndex = parts.indexWhere((p) => p is SourceContent);
      expect(sourceIndex, greaterThan(-1));
      expect(sourceIndex, lessThan(textEndIndex));

      final source = parts.whereType<SourceContent>().single;
      expect(source.sourceType, SourceType.url);
      expect(source.url, 'https://example.com/a');
      expect(source.title, 'Example A');
      expect(source.id, isNotEmpty);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(parts.last, isA<FinishPart>());
    });

    test('usage-only 结尾 chunk(choices 为空数组)不产出多余 text/tool 事件', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamUsageOnly),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      expect(parts.whereType<TextDelta>(), hasLength(1));
      expect(parts.whereType<TextDelta>().single.delta, 'hi');

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.usage.inputTokens.total, 3);
      expect(finish.usage.outputTokens.total, 1);
    });

    test('输出前错误帧:doStream 的 Future 直接抛 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamErrorBeforeOutput),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      await expectLater(
        () => model.doStream(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(isA<ApiCallError>()),
      );
    });

    test(
        '首帧空 delta(role-only 元数据帧)后跟错误帧:探测窗口不止 peek '
        '首帧,doStream 的 Future 仍抛 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async =>
            _sseResponse(_chatStreamMetadataFrameThenErrorBeforeOutput),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      await expectLater(
        () => model.doStream(
          const LanguageModelCallOptions(
            prompt: [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'The server had an error processing your request',
          ),
        ),
      );
    });

    test(
        '输出后错误帧:流内下发 ErrorPart(不 throw),且 ErrorPart 后无任何分块'
        '(error 即终端事件,无 TextEnd/无 FinishPart)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamErrorAfterOutput),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      expect(parts.whereType<TextDelta>().single.delta, 'partial');
      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));

      // error-as-terminal-event: ErrorPart 必须是流的最后一个分块,其后
      // 不应再出现 TextEnd/FinishPart 或任何其他分块。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test(
        '连接级 Stream error(字节流 addError,非错误帧内容):流内下发 '
        'ErrorPart(不逃逸为未捕获异常),且其后无任何分块'
        '(error 即终端事件,无 TextEnd/无 FinishPart)', () async {
      final client = _RecordingClient(
        (request) async => _sseResponseWithTransportError(),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final textDeltas = parts.whereType<TextDelta>().toList();
      expect(textDeltas, hasLength(2));
      expect(textDeltas.map((d) => d.delta).join(), 'onetwo');

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));

      // error-as-terminal-event: ErrorPart 必须是流的最后一个分块,其后
      // 不应再出现 TextEnd/FinishPart 或任何其他分块。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test(
        'probe 窗口内的连接级 Stream error(首个可解析事件前字节流即 '
        'addError):doStream 的 Future 正常完成(不抛异常),流内下发 '
        'ErrorPart 作为唯一终态分块', () async {
      final client = _RecordingClient(
        (request) async => _sseResponseWithTransportErrorBeforeOutput(),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      // doStream 本身不应 throw——与「错误帧 → Future 抛 ApiCallError」的
      // 既定语义是两条不同路径:这里是连接级传输失败,走流内 ErrorPart。
      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextDelta>(), isEmpty);
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test(
        '帧级解析失败(SSE data 行为非法 JSON):流内下发 ErrorPart 作为终态'
        '分块,不再产出 FinishPart(与 wire 错误信封/连接级错误同一 '
        'error-as-terminal-event 语义)', () async {
      final malformedThenValid = 'data: {not-valid-json}\n\n'
          'data: {"id":"chatcmpl-bad","created":1700000000,"model":"gpt-4o",'
          '"choices":[{"index":0,"delta":{"content":"hi"}}]}\n\n'
          'data: [DONE]\n\n';
      final client = _RecordingClient(
        (request) async => _sseResponse(malformedThenValid),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      final parts = await result.stream.toList();

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      // error-as-terminal-event: ErrorPart 必须是流的最后一个分块,其后
      // 不应再出现 TextStart/TextDelta/TextEnd/FinishPart。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextStart>(), isEmpty);
      expect(parts.whereType<TextDelta>(), isEmpty);
      expect(parts.whereType<TextEnd>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('includeRawChunks 开启时每个事件前置发出 RawPart', () async {
      final client = _RecordingClient(
        (request) async => _sseResponse(_chatStreamText),
      );
      final model = OpenAiChatLanguageModel('gpt-4o', config: _config(client));

      final result = await model.doStream(
        const LanguageModelCallOptions(
          prompt: [
            UserMessage([TextPart('hi')])
          ],
          includeRawChunks: true,
        ),
      );
      final parts = await result.stream.toList();

      expect(parts.whereType<RawPart>(), isNotEmpty);
      // RawPart 数量应等于成功解析的 SSE 帧数(本 fixture 5 帧,不含 [DONE])。
      expect(parts.whereType<RawPart>(), hasLength(5));
    });
  });
}
