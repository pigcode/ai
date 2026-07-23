import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/fake_http_client.dart';

/// 把三引号字符串字面量里每一行的前导空白去掉,使跟随 Dart 源码缩进
/// 书写的 SSE fixture 文本在解析时等价于零缩进版本。`sseTransformer`
/// 按 `field:value` 原样取字段名、不裁剪前导空白,缩进的 `  event:` 会
/// 被识别成未知字段导致事件被静默丢弃(已用沙盒验证),故所有内嵌 SSE
/// fixture 必须经本函数规整。
String _flushLeft(String text) =>
    text.split('\n').map((line) => line.trimLeft()).join('\n');

final _responsesTextStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s1","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_1"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_1","delta":"Hel"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_1","delta":"lo"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_1"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":2}}}

''');

final _responsesTextStreamWithAnnotations = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s_ann","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_ann"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_ann","delta":"see sources"}

event: response.output_text.annotation.added
data: {"type":"response.output_text.annotation.added","item_id":"msg_ann","annotation":{"type":"url_citation","url":"https://example.com/a","title":"Example A"}}

event: response.output_text.annotation.added
data: {"type":"response.output_text.annotation.added","item_id":"msg_ann","annotation":{"type":"file_citation","file_id":"file_123","filename":"doc.pdf","index":3}}

event: response.output_text.annotation.added
data: {"type":"response.output_text.annotation.added","item_id":"msg_ann","annotation":{"type":"container_file_citation","container_id":"cntr_1","file_id":"cfile_123","filename":"report.csv","index":4,"start_index":11,"end_index":22}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_ann"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":2}}}

''');

final _responsesTextStreamWithLogprobs = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s_lp","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_lp"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_lp","delta":"Hel","logprobs":[{"token":"Hel","logprob":-0.2}]}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_lp","delta":"lo","logprobs":[{"token":"lo","logprob":-0.3}]}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_lp"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":2}}}

''');

final _responsesFunctionCallStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s2","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"get_weather"}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"delta":"{\\"city\\":"}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"delta":"\\"nyc\\"}"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"get_weather","arguments":"{\\"city\\":\\"nyc\\"}","status":"completed"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesWebSearchStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_web_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"web_search_call","id":"ws_1","status":"in_progress"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","queries":["dart ai sdk"],"sources":[{"type":"url","url":"https://example.com"}]}}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesFileSearchStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_file_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"file_search_call","id":"fs_1","status":"in_progress"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"file_search_call","id":"fs_1","status":"completed","queries":["embedding model"],"results":[{"attributes":{"kind":"docs"},"file_id":"file_1","filename":"ai.pdf","score":0.93,"text":"An embedding model converts data into vectors."}]}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesCodeInterpreterStream = _flushLeft(r'''
event: response.created
data: {"type":"response.created","response":{"id":"resp_code_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"code_interpreter_call","id":"ci_1","status":"in_progress","container_id":"cntr_1"}}

event: response.code_interpreter_call_code.delta
data: {"type":"response.code_interpreter_call_code.delta","item_id":"ci_1","output_index":0,"delta":"print(\"hi\")"}

event: response.code_interpreter_call_code.delta
data: {"type":"response.code_interpreter_call_code.delta","item_id":"ci_1","output_index":0,"delta":"\npath = \"C:\\\\tmp\""}

event: response.code_interpreter_call_code.done
data: {"type":"response.code_interpreter_call_code.done","item_id":"ci_1","output_index":0,"code":"print(\"hi\")\npath = \"C:\\\\tmp\""}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"code_interpreter_call","id":"ci_1","status":"completed","container_id":"cntr_1","code":"print(\"hi\")\npath = \"C:\\\\tmp\"","outputs":[{"type":"logs","logs":"hi\n"}]}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesImageGenerationStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_image_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"image_generation_call","id":"ig_1","status":"in_progress"}}

event: response.image_generation_call.partial_image
data: {"type":"response.image_generation_call.partial_image","item_id":"ig_1","output_index":0,"partial_image_index":0,"partial_image_b64":"partial_image_b64"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"image_generation_call","id":"ig_1","status":"completed","result":"final_image_b64"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesMcpStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_mcp_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_list_tools","id":"mcp_list_1","server_label":"dmcp","tools":[{"name":"search"}]}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":1,"item":{"type":"mcp_call","id":"mcp_1","status":"completed","server_label":"dmcp","name":"search","arguments":"{\\"query\\":\\"dart ai sdk\\"}","output":"{\\"ok\\":true}"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesMcpErrorStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_mcp_error_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_call","id":"mcp_1","status":"failed","server_label":"dmcp","name":"search","arguments":"{\\"query\\":\\"dart ai sdk\\"}","error":{"message":"MCP server denied the request"}}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesToolSearchStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_tool_search_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"tool_search_call","id":"tsc_1","execution":"client","call_id":"call_tool_search","status":"in_progress","arguments":{"goal":"Find weather tools"}}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"tool_search_call","id":"tsc_1","execution":"client","call_id":"call_tool_search","status":"completed","arguments":{"goal":"Find weather tools"}}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":1,"item":{"type":"tool_search_output","id":"tso_1","execution":"client","call_id":"call_tool_search","status":"completed","tools":[{"type":"function","name":"get_weather"}]}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesComputerStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_computer_stream","created_at":1700000000,"model":"gpt-5.4"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"computer_call","id":"computer_item_123","call_id":"computer_call_123","status":"in_progress"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"computer_call","id":"computer_item_123","call_id":"computer_call_123","status":"completed","pending_safety_checks":[{"id":"safety_123","code":"confirm_action","message":"Confirm this action."}],"actions":[{"type":"click","button":"left","x":100,"y":200,"keys":["CTRL"]},{"type":"screenshot"},{"type":"scroll","x":130,"y":230,"scroll_x":0,"scroll_y":500}]}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesMcpApprovalRequestStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_mcp_approval_stream","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_approval_request","id":"approval_item_1","approval_request_id":"approval_1","server_label":"dmcp","name":"search","arguments":"{\\"query\\":\\"dart ai sdk\\"}"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":3}}}

''');

final _responsesReasoningStreamStoreTrue = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s3","created_at":1700000000,"model":"o3"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1"}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_1","summary_index":0,"delta":"thinking"}

event: response.reasoning_summary_part.done
data: {"type":"response.reasoning_summary_part.done","item_id":"rs_1","summary_index":0}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","encrypted_content":null}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":6}}}}

''');

final _responsesReasoningStreamStoreFalse = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s4","created_at":1700000000,"model":"o3"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_2"}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_2","summary_index":0,"delta":"thinking-2"}

event: response.reasoning_summary_part.done
data: {"type":"response.reasoning_summary_part.done","item_id":"rs_2","summary_index":0}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_2","encrypted_content":"enc_xyz"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":6}}}}

''');

final _responsesReasoningStreamStoreFalseMultiSummary = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s5","created_at":1700000000,"model":"o3"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_3"}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_3","summary_index":0,"delta":"first"}

event: response.reasoning_summary_part.done
data: {"type":"response.reasoning_summary_part.done","item_id":"rs_3","summary_index":0}

event: response.reasoning_summary_part.added
data: {"type":"response.reasoning_summary_part.added","item_id":"rs_3","summary_index":1,"part":{"type":"summary_text","text":""}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_3","summary_index":1,"delta":"second"}

event: response.reasoning_summary_part.done
data: {"type":"response.reasoning_summary_part.done","item_id":"rs_3","summary_index":1}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_3","encrypted_content":"enc_final"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":10,"output_tokens_details":{"reasoning_tokens":8}}}}

''');

final _responsesRefusalStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s_refusal","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_refusal_1"}}

event: response.refusal.delta
data: {"type":"response.refusal.delta","item_id":"msg_refusal_1","content_index":0,"delta":"I cannot"}

event: response.refusal.delta
data: {"type":"response.refusal.delta","item_id":"msg_refusal_1","content_index":0,"delta":" help with that."}

event: response.refusal.done
data: {"type":"response.refusal.done","item_id":"msg_refusal_1","content_index":0,"refusal":"I cannot help with that."}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_refusal_1"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":4}}}

''');

final _responsesIncompleteStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s5","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_2"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_2","delta":"partial"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_2"}}

event: response.incomplete
data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":10,"output_tokens":1}}}

''');

final _responsesErrorBeforeOutputStream = _flushLeft('''
event: error
data: {"type":"error","sequence_number":1,"code":"insufficient_quota","message":"You exceeded your quota"}

''');

final _responsesErrorAfterOutputStream = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s6","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_3"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_3","delta":"partial output"}

event: response.failed
data: {"type":"response.failed","sequence_number":2,"response":{"error":{"code":"server_error","message":"internal error"}}}

''');

/// 构造一个先正常发出两帧文本 delta、随后字节流本身 `addError`(而非发出
/// 错误帧内容)的 [http.StreamedResponse],用于模拟连接级传输失败(如
/// SSE 中途断连)——区别于 `_responsesErrorAfterOutputStream` 那种"服务端
/// 下发了 `response.failed`/`error` 内容帧"的场景。
http.StreamedResponse _responsesStreamedResponseWithTransportError() {
  late StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onListen: () async {
      controller.add(utf8.encode(_flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_transport_err","created_at":1700000000,"model":"gpt-4.1"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_te"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_te","delta":"one"}

''')));
      await Future<void>.delayed(Duration.zero);
      controller.add(utf8.encode(_flushLeft('''
event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_te","delta":"two"}

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

void main() {
  // Compatibility fixture (unit): P1-OPENAI-05
  OpenAiConfig configWith(FakeHttpClient client) => OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => {'Authorization': 'Bearer test-key'},
        client: client,
      );

  LanguageModelCallOptions optionsWith({
    List<LanguageModelMessage>? prompt,
    List<LanguageModelTool>? tools,
  }) =>
      LanguageModelCallOptions(
        prompt: prompt ??
            const [
              UserMessage([TextPart('hi')])
            ],
        tools: tools,
      );

  group('OpenAiResponsesLanguageModel.doGenerate', () {
    test('maps a plain text response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_1',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello there',
                    'annotations': []
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      final text = result.content.single as TextContent;
      expect(text.text, 'hello there');
      expect(result.finishReason.unified, FinishReasonType.stop);
      expect(result.usage.inputTokens.total, 10);
      expect(result.usage.outputTokens.total, 5);
      expect(
        result.providerMetadata?['openai']?['responseId'],
        'resp_1',
      );
      expect(result.response?.id, 'resp_1');
      expect(result.response?.modelId, 'gpt-4.1');

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['model'], 'gpt-4.1');
      expect(sentBody['input'], [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hi'},
          ],
        },
      ]);
      expect(sentBody.containsKey('stream'), isFalse);
    });

    test('web_search tool is sent and auto-includes action sources', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_web_request',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.webSearch(
              filters: const OpenAiWebSearchFilters(
                allowedDomains: ['example.com'],
              ),
              searchContextSize: 'medium',
            ),
          ],
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['tools'], [
        {
          'type': 'web_search',
          'filters': {
            'allowed_domains': ['example.com'],
          },
          'search_context_size': 'medium',
        },
      ]);
      expect(sentBody['include'], ['web_search_call.action.sources']);
    });

    test('file_search tool is sent with Responses wire options', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_file_request',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.fileSearch(
              vectorStoreIds: ['vs_1'],
              maxNumResults: 3,
              ranking: const OpenAiFileSearchRanking(
                ranker: 'auto',
                scoreThreshold: 0.4,
              ),
              filters: const OpenAiFileSearchComparisonFilter(
                key: 'kind',
                type: 'eq',
                value: 'docs',
              ),
            ),
          ],
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['tools'], [
        {
          'type': 'file_search',
          'vector_store_ids': ['vs_1'],
          'max_num_results': 3,
          'ranking_options': {
            'ranker': 'auto',
            'score_threshold': 0.4,
          },
          'filters': {
            'key': 'kind',
            'type': 'eq',
            'value': 'docs',
          },
        },
      ]);
      expect(sentBody.containsKey('include'), isFalse);
    });

    test('code_interpreter tool is sent and auto-includes outputs', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_code_request',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        optionsWith(tools: [openAiTools.codeInterpreter()]),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['tools'], [
        {
          'type': 'code_interpreter',
          'container': {'type': 'auto'},
        },
      ]);
      expect(sentBody['include'], ['code_interpreter_call.outputs']);
    });

    test('image_generation tool is sent with Responses wire options', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_image_request',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.imageGeneration(
              action: 'edit',
              background: 'transparent',
              inputFidelity: 'high',
              inputImageMask: const OpenAiImageGenerationInputImageMask(
                fileId: 'file_mask',
                imageUrl: 'data:image/png;base64,mask',
              ),
              model: 'gpt-image-2',
              moderation: 'low',
              outputCompression: 80,
              outputFormat: 'webp',
              partialImages: 2,
              quality: 'high',
              size: '2048x2048',
            ),
          ],
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['tools'], [
        {
          'type': 'image_generation',
          'action': 'edit',
          'background': 'transparent',
          'input_fidelity': 'high',
          'input_image_mask': {
            'file_id': 'file_mask',
            'image_url': 'data:image/png;base64,mask',
          },
          'model': 'gpt-image-2',
          'moderation': 'low',
          'output_compression': 80,
          'output_format': 'webp',
          'partial_images': 2,
          'quality': 'high',
          'size': '2048x2048',
        },
      ]);
      expect(sentBody.containsKey('include'), isFalse);
    });

    test('mcp tool is sent with Responses wire options', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_mcp_request',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.mcp(
              serverLabel: 'dmcp',
              serverUrl: 'https://mcp.example.com',
              allowedTools: const OpenAiMcpAllowedTools.names(['search']),
            ),
          ],
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['tools'], [
        {
          'type': 'mcp',
          'server_label': 'dmcp',
          'allowed_tools': ['search'],
          'server_url': 'https://mcp.example.com',
        },
      ]);
      expect(sentBody.containsKey('include'), isFalse);
    });

    test(
        'output_text.annotations 含 url_citation + file_citation + '
        'container_file_citation 时映射为 TextContent.providerMetadata.'
        'annotations + 三条对应 SourceContent', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_ann',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_ann',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'see sources',
                    'annotations': [
                      {
                        'type': 'url_citation',
                        'url': 'https://example.com/a',
                        'title': 'Example A',
                      },
                      {
                        'type': 'file_citation',
                        'file_id': 'file_123',
                        'filename': 'doc.pdf',
                        'index': 3,
                      },
                      {
                        'type': 'container_file_citation',
                        'container_id': 'cntr_1',
                        'file_id': 'cfile_123',
                        'filename': 'report.csv',
                        'index': 4,
                        'start_index': 11,
                        'end_index': 22,
                      },
                    ],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      final text = result.content.whereType<TextContent>().single;
      expect(text.text, 'see sources');
      final annotations =
          text.providerMetadata?['openai']?['annotations'] as List<Object?>?;
      expect(annotations, hasLength(3));
      expect(annotations![0], {
        'type': 'url_citation',
        'url': 'https://example.com/a',
        'title': 'Example A',
      });
      expect(annotations[1], {
        'type': 'file_citation',
        'file_id': 'file_123',
        'filename': 'doc.pdf',
        'index': 3,
      });
      expect(annotations[2], {
        'type': 'container_file_citation',
        'container_id': 'cntr_1',
        'file_id': 'cfile_123',
        'filename': 'report.csv',
        'index': 4,
        'start_index': 11,
        'end_index': 22,
      });

      final sources = result.content.whereType<SourceContent>().toList();
      expect(sources, hasLength(3));

      final urlSource = sources[0];
      expect(urlSource.sourceType, SourceType.url);
      expect(urlSource.url, 'https://example.com/a');
      expect(urlSource.title, 'Example A');

      final fileSource = sources[1];
      expect(fileSource.sourceType, SourceType.document);
      expect(fileSource.mediaType, 'text/plain');
      expect(fileSource.title, 'doc.pdf');
      expect(fileSource.filename, 'doc.pdf');
      expect(
        fileSource.providerMetadata?['openai'],
        {'type': 'file_citation', 'fileId': 'file_123', 'index': 3},
      );

      final containerFileSource = sources[2];
      expect(containerFileSource.sourceType, SourceType.document);
      expect(containerFileSource.mediaType, 'text/plain');
      expect(containerFileSource.title, 'report.csv');
      expect(containerFileSource.filename, 'report.csv');
      expect(containerFileSource.providerMetadata?['openai'], {
        'type': 'container_file_citation',
        'containerId': 'cntr_1',
        'fileId': 'cfile_123',
        'filename': 'report.csv',
        'index': 4,
        'startIndex': 11,
        'endIndex': 22,
      });
    });

    test(
        'output_text.annotations 为空数组时 TextContent.providerMetadata 不含 '
        "'annotations' 键(回归)", () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_no_ann',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_no_ann',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'plain text',
                    'annotations': [],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      final text = result.content.single as TextContent;
      expect(
        text.providerMetadata?['openai']?.containsKey('annotations'),
        isNot(isTrue),
      );
    });

    test(
        "缺合法 'output' 数组的 2xx 响应(如误配到 Chat Completions 端点)"
        '触发带完整 wire 诊断信息的 ApiCallError', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'chatcmpl-wrong-endpoint',
            'object': 'chat.completion',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'hi'},
                'finish_reason': 'stop',
              },
            ],
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        model.doGenerate(optionsWith()),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 200)
              .having(
                (error) => error.url,
                'url',
                'https://api.openai.com/v1/responses',
              )
              .having(
                (error) => error.responseBody,
                'responseBody',
                contains('"object":"chat.completion"'),
              )
              .having(
                (error) => error.data,
                'data',
                isA<Map<String, Object?>>(),
              )
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('maps a batched computer call and preserves its stored item id',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_computer',
            'created_at': 1700000000,
            'model': 'gpt-5.4',
            'output': [
              {
                'type': 'computer_call',
                'id': 'computer_item_123',
                'call_id': 'computer_call_123',
                'status': 'completed',
                'pending_safety_checks': [
                  {
                    'id': 'safety_123',
                    'code': 'confirm_action',
                    'message': 'Confirm this action.',
                  },
                ],
                'actions': [
                  {
                    'type': 'scroll',
                    'x': 10,
                    'y': 20,
                    'scroll_x': 0,
                    'scroll_y': 100,
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 3},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-5.4',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [openAiTools.computer()]),
      );

      expect(
        jsonDecode(client.recordedBodies.single)['tools'],
        [
          {'type': 'computer'},
        ],
      );
      expect(result.content, [
        ToolCall(
          toolCallId: 'computer_call_123',
          toolName: 'computer',
          input: jsonEncode({
            'actions': [
              {
                'type': 'scroll',
                'x': 10,
                'y': 20,
                'scrollX': 0,
                'scrollY': 100,
              },
            ],
            'pendingSafetyChecks': [
              {
                'id': 'safety_123',
                'code': 'confirm_action',
                'message': 'Confirm this action.',
              },
            ],
            'status': 'completed',
          }),
          providerMetadata: const {
            'openai': {
              'itemId': 'computer_item_123',
            },
          },
        ),
      ]);
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('maps a function_call response and sets finishReason tool-calls',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_2',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'function_call',
                'id': 'fc_1',
                'call_id': 'call_1',
                'name': 'get_weather',
                'arguments': '{"city":"nyc"}',
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      final call = result.content.single as ToolCall;
      expect(call.toolCallId, 'call_1');
      expect(call.toolName, 'get_weather');
      expect(call.input, '{"city":"nyc"}');
      expect(call.providerMetadata?['openai']?['itemId'], 'fc_1');
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('maps a provider-executed web_search_call response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_web',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'web_search_call',
                'id': 'ws_1',
                'status': 'completed',
                'action': {
                  'type': 'search',
                  'queries': ['dart ai sdk'],
                  'sources': [
                    {'type': 'url', 'url': 'https://example.com'},
                  ],
                },
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [openAiTools.webSearch()]),
      );

      expect(result.content, hasLength(2));
      final call = result.content[0] as ToolCall;
      expect(call.toolCallId, 'ws_1');
      expect(call.toolName, 'web_search');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final toolResult = result.content[1] as ToolResult;
      expect(toolResult.toolCallId, 'ws_1');
      expect(toolResult.toolName, 'web_search');
      expect(toolResult.result, {
        'action': {
          'type': 'search',
          'queries': ['dart ai sdk'],
        },
        'sources': [
          {'type': 'url', 'url': 'https://example.com'},
        ],
      });
      expect(result.finishReason.unified, FinishReasonType.stop);
    });

    test('maps a provider-executed file_search_call response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_file',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'file_search_call',
                'id': 'fs_1',
                'status': 'completed',
                'queries': ['embedding model'],
                'results': [
                  {
                    'attributes': {'kind': 'docs'},
                    'file_id': 'file_1',
                    'filename': 'ai.pdf',
                    'score': 0.93,
                    'text': 'An embedding model converts data into vectors.',
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [
          openAiTools.fileSearch(vectorStoreIds: ['vs_1'])
        ]),
      );

      expect(result.content, hasLength(2));
      final call = result.content[0] as ToolCall;
      expect(call.toolCallId, 'fs_1');
      expect(call.toolName, 'file_search');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final toolResult = result.content[1] as ToolResult;
      expect(toolResult.toolCallId, 'fs_1');
      expect(toolResult.toolName, 'file_search');
      expect(toolResult.result, {
        'queries': ['embedding model'],
        'results': [
          {
            'attributes': {'kind': 'docs'},
            'fileId': 'file_1',
            'filename': 'ai.pdf',
            'score': 0.93,
            'text': 'An embedding model converts data into vectors.',
          },
        ],
      });
      expect(result.finishReason.unified, FinishReasonType.stop);
    });

    test('maps a provider-executed code_interpreter_call response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_code',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'code_interpreter_call',
                'id': 'ci_1',
                'status': 'completed',
                'container_id': 'cntr_1',
                'code': "print('hi')",
                'outputs': [
                  {'type': 'logs', 'logs': 'hi\n'},
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [openAiTools.codeInterpreter()]),
      );

      expect(result.content, hasLength(2));
      final call = result.content[0] as ToolCall;
      expect(call.toolCallId, 'ci_1');
      expect(call.toolName, 'code_interpreter');
      expect(call.input, '{"code":"print(\'hi\')","containerId":"cntr_1"}');
      expect(call.providerExecuted, isTrue);

      final toolResult = result.content[1] as ToolResult;
      expect(toolResult.toolCallId, 'ci_1');
      expect(toolResult.toolName, 'code_interpreter');
      expect(toolResult.result, {
        'outputs': [
          {'type': 'logs', 'logs': 'hi\n'},
        ],
      });
      expect(result.finishReason.unified, FinishReasonType.stop);
    });

    test('maps a provider-executed image_generation_call response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_image',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'image_generation_call',
                'id': 'ig_1',
                'status': 'completed',
                'result': 'final_image_b64',
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [openAiTools.imageGeneration()]),
      );

      expect(result.content, hasLength(2));
      final call = result.content[0] as ToolCall;
      expect(call.toolCallId, 'ig_1');
      expect(call.toolName, 'image_generation');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final toolResult = result.content[1] as ToolResult;
      expect(toolResult.toolCallId, 'ig_1');
      expect(toolResult.toolName, 'image_generation');
      expect(toolResult.result, {'result': 'final_image_b64'});
      expect(result.finishReason.unified, FinishReasonType.stop);
    });

    test('maps Responses provider-defined tool calls and outputs', () async {
      const applyPatchItem = {
        'type': 'apply_patch_call',
        'id': 'apc_1',
        'call_id': 'call_patch',
        'status': 'completed',
        'operation': {
          'type': 'update_file',
          'path': 'README.md',
          'diff': '@@ -1 +1 @@\n-old\n+new',
        },
      };
      const customToolItem = {
        'type': 'custom_tool_call',
        'id': 'ctc_1',
        'call_id': 'call_custom',
        'name': 'grammar_out',
        'input': 'emit ok',
      };
      const shellItem = {
        'type': 'shell_call',
        'id': 'shc_1',
        'call_id': 'call_shell',
        'status': 'completed',
        'action': {
          'commands': ['ls'],
          'timeout_ms': 2000,
        },
      };
      const shellOutputItem = {
        'type': 'shell_call_output',
        'id': 'sho_1',
        'call_id': 'call_shell',
        'status': 'completed',
        'max_output_length': 4096,
        'output': [
          {
            'stdout': 'README.md\n',
            'stderr': '',
            'outcome': {'type': 'exit', 'exit_code': 0},
          },
        ],
      };
      const toolSearchCallItem = {
        'type': 'tool_search_call',
        'id': 'tsc_1',
        'execution': 'client',
        'call_id': 'call_tool_search',
        'status': 'completed',
        'arguments': {'goal': 'Find weather tools'},
      };
      const toolSearchOutputItem = {
        'type': 'tool_search_output',
        'id': 'tso_1',
        'execution': 'client',
        'call_id': 'call_tool_search',
        'status': 'completed',
        'tools': [
          {'type': 'function', 'name': 'get_weather'},
        ],
      };

      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_provider_defined',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              applyPatchItem,
              customToolItem,
              shellItem,
              shellOutputItem,
              toolSearchCallItem,
              toolSearchOutputItem,
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.applyPatch(),
            openAiTools.customTool(name: 'grammar_out'),
            openAiTools.shell(),
            openAiTools.toolSearch(execution: 'client'),
          ],
        ),
      );

      final calls = result.content.whereType<ToolCall>().toList();
      expect(calls, hasLength(4));
      expect(calls.map((call) => call.toolName), [
        'apply_patch',
        'grammar_out',
        'shell',
        'tool_search',
      ]);
      expect(calls[0].toolCallId, 'call_patch');
      expect(
        calls[0].input,
        jsonEncode({
          'callId': 'call_patch',
          'operation': {
            'type': 'update_file',
            'path': 'README.md',
            'diff': '@@ -1 +1 @@\n-old\n+new',
          },
        }),
      );
      expect(calls[0].providerMetadata?['openai']?['item'], applyPatchItem);

      expect(calls[1].toolCallId, 'call_custom');
      expect(calls[1].input, jsonEncode('emit ok'));
      expect(calls[1].providerMetadata?['openai']?['item'], customToolItem);

      expect(calls[2].toolCallId, 'call_shell');
      expect(
          calls[2].input,
          jsonEncode({
            'action': {
              'commands': ['ls'],
              'timeoutMs': 2000
            },
          }));
      expect(calls[2].providerMetadata?['openai']?['item'], shellItem);

      expect(calls[3].toolCallId, 'call_tool_search');
      expect(
        calls[3].input,
        jsonEncode({
          'arguments': {'goal': 'Find weather tools'},
          'call_id': 'call_tool_search',
        }),
      );
      expect(
        calls[3].providerMetadata?['openai']?['item'],
        toolSearchCallItem,
      );

      final results = result.content.whereType<ToolResult>().toList();
      expect(results, hasLength(2));
      expect(results[0].toolCallId, 'call_shell');
      expect(results[0].toolName, 'shell');
      expect(results[0].result, {
        'maxOutputLength': 4096,
        'output': [
          {
            'stdout': 'README.md\n',
            'stderr': '',
            'outcome': {'type': 'exit', 'exitCode': 0},
          },
        ],
      });
      expect(results[0].providerMetadata?['openai']?['item'], shellOutputItem);

      expect(results[1].toolCallId, 'call_tool_search');
      expect(results[1].toolName, 'tool_search');
      expect(results[1].result, {
        'tools': [
          {'type': 'function', 'name': 'get_weather'},
        ],
      });
      expect(
        results[1].providerMetadata?['openai']?['item'],
        toolSearchOutputItem,
      );
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('maps a provider-executed mcp_call response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_mcp',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'mcp_list_tools',
                'id': 'mcp_list_1',
                'server_label': 'dmcp',
                'tools': [
                  {'name': 'search'},
                ],
              },
              {
                'type': 'mcp_call',
                'id': 'mcp_1',
                'status': 'completed',
                'server_label': 'dmcp',
                'name': 'search',
                'arguments': '{"query":"dart ai sdk"}',
                'output': '{"ok":true}',
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.mcp(
              serverLabel: 'dmcp',
              serverUrl: 'https://mcp.example.com',
            ),
          ],
        ),
      );

      final mcpListToolsItem = {
        'type': 'mcp_list_tools',
        'id': 'mcp_list_1',
        'server_label': 'dmcp',
        'tools': [
          {'name': 'search'},
        ],
      };
      final mcpCallItem = {
        'type': 'mcp_call',
        'id': 'mcp_1',
        'status': 'completed',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'output': '{"ok":true}',
      };

      expect(result.content, hasLength(3));
      final listTools = result.content.whereType<CustomContentBlock>().single;
      expect(listTools.kind, 'openai.mcp_list_tools');
      expect(
        listTools.providerMetadata?['openai']?['item'],
        mcpListToolsItem,
      );

      final call = result.content.whereType<ToolCall>().single;
      expect(call.toolCallId, 'mcp_1');
      expect(call.toolName, 'mcp.search');
      expect(call.input, '{"query":"dart ai sdk"}');
      expect(call.providerExecuted, isTrue);
      expect(call.isDynamic, isTrue);
      expect(call.providerMetadata?['openai']?['itemId'], 'mcp_1');
      expect(call.providerMetadata?['openai']?['item'], mcpCallItem);

      final toolResult = result.content.whereType<ToolResult>().single;
      expect(toolResult.toolCallId, 'mcp_1');
      expect(toolResult.toolName, 'mcp.search');
      expect(toolResult.result, {
        'type': 'call',
        'serverLabel': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'output': '{"ok":true}',
      });
      expect(toolResult.providerMetadata?['openai']?['itemId'], 'mcp_1');
      expect(toolResult.providerMetadata?['openai']?['item'], mcpCallItem);
      expect(result.finishReason.unified, FinishReasonType.stop);
    });

    test('maps a failed mcp_call response as an error result', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_mcp_error',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'mcp_call',
                'id': 'mcp_1',
                'status': 'failed',
                'server_label': 'dmcp',
                'name': 'search',
                'arguments': '{"query":"dart ai sdk"}',
                'error': {'message': 'MCP server denied the request'},
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.mcp(
              serverLabel: 'dmcp',
              serverUrl: 'https://mcp.example.com',
            ),
          ],
        ),
      );

      final toolResult = result.content.whereType<ToolResult>().single;
      expect(toolResult.toolCallId, 'mcp_1');
      expect(toolResult.toolName, 'mcp.search');
      expect(toolResult.isError, isTrue);
      expect(toolResult.result, {
        'type': 'call',
        'serverLabel': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'error': {'message': 'MCP server denied the request'},
      });
    });

    test('maps an mcp_approval_request response', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_mcp_approval',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'mcp_approval_request',
                'id': 'approval_item_1',
                'approval_request_id': 'approval_1',
                'server_label': 'dmcp',
                'name': 'search',
                'arguments': '{"query":"dart ai sdk"}',
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(
          tools: [
            openAiTools.mcp(
              serverLabel: 'dmcp',
              serverUrl: 'https://mcp.example.com',
            ),
          ],
        ),
      );

      expect(result.content, hasLength(2));
      final call = result.content[0] as ToolCall;
      expect(call.toolName, 'mcp.search');
      expect(call.input, '{"query":"dart ai sdk"}');
      expect(call.providerExecuted, isTrue);
      expect(call.isDynamic, isTrue);
      expect(call.providerMetadata?['openai']?['item'], {
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'approval_request_id': 'approval_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      });

      final approval = result.content[1] as ToolApprovalRequest;
      expect(approval.approvalId, 'approval_1');
      expect(approval.toolCallId, call.toolCallId);
      expect(approval.providerMetadata?['openai']?['item'], {
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'approval_request_id': 'approval_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      });
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('client provider-defined tool call sets finishReason tool-calls',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_patch_only',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'apply_patch_call',
                'id': 'apc_1',
                'call_id': 'call_patch',
                'status': 'completed',
                'operation': {
                  'type': 'delete_file',
                  'path': 'obsolete.dart',
                },
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        optionsWith(tools: [openAiTools.applyPatch()]),
      );

      expect(
          result.content.whereType<ToolCall>().single.toolName, 'apply_patch');
      expect(result.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('maps a reasoning response with a single summary', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_3',
            'created_at': 1700000000,
            'model': 'o3',
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_1',
                'encrypted_content': null,
                'summary': [
                  {'type': 'summary_text', 'text': 'thinking...'},
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      final reasoning = result.content.single as ReasoningContent;
      expect(reasoning.text, 'thinking...');
      expect(
        reasoning.providerMetadata?['openai']?['itemId'],
        'rs_1',
      );
    });

    test('reasoning with an empty summary list still yields one content item',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_4',
            'created_at': 1700000000,
            'model': 'o3',
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_2',
                'encrypted_content': null,
                'summary': <Object?>[],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      expect((result.content.single as ReasoningContent).text, '');
    });

    test('message with a refusal content part maps to text without throwing',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_refusal',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_refusal',
                'content': [
                  {
                    'type': 'refusal',
                    'refusal': 'I cannot help with that request.',
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      final text = result.content.single as TextContent;
      expect(text.text, 'I cannot help with that request.');
      expect(text.providerMetadata?['openai']?['refusal'], isTrue);
      expect(text.providerMetadata?['openai']?['itemId'], 'msg_refusal');
    });

    test('unrecognized output item types are safely skipped', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_5',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {'type': 'unknown_tool_call', 'id': 'unknown_1'},
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_5',
                'content': [
                  {'type': 'output_text', 'text': 'ok', 'annotations': []},
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(result.content, hasLength(1));
      expect((result.content.single as TextContent).text, 'ok');
      expect(result.warnings, isNotEmpty);
    });

    test('HTTP non-2xx surfaces ApiCallError', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 401,
          body: jsonEncode({
            'error': {
              'message': 'invalid api key',
              'type': 'invalid_request_error'
            },
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        model.doGenerate(optionsWith()),
        throwsA(isA<ApiCallError>()),
      );
    });

    test('response.error with 200 status surfaces ApiCallError', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'error': {
              'message': 'insufficient_quota',
              'type': 'insufficient_quota',
              'code': 'insufficient_quota',
            },
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        model.doGenerate(optionsWith()),
        throwsA(isA<ApiCallError>()),
      );
    });

    test('reasoning model omits temperature/topP with warnings', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_6',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.5,
        ),
      );

      expect(
        result.warnings.whereType<UnsupportedWarning>(),
        isNotEmpty,
      );
      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('temperature'), isFalse);
    });

    test('gpt-5.1 系列在 reasoningEffort=none 时保留 temperature/topP', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_7',
            'created_at': 1700000000,
            'model': 'gpt-5.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'none'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['temperature'], 0.7);
      expect(sentBody['top_p'], 0.9);
      expect(sentBody['reasoning'], {'effort': 'none'});
      expect(
        result.warnings.any((w) =>
            w is UnsupportedWarning &&
            (w.feature == 'temperature' || w.feature == 'topP')),
        isFalse,
      );
    });

    test('gpt-5.1 系列在 reasoningEffort 非 none 时仍裁剪 temperature/topP', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_8',
            'created_at': 1700000000,
            'model': 'gpt-5.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'medium'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('temperature'), isFalse);
      expect(sentBody.containsKey('top_p'), isFalse);
      expect(
        result.warnings.whereType<UnsupportedWarning>(),
        isNotEmpty,
      );
    });

    test(
        'provider 名含 azure 时,providerOptions 优先从 "azure" 键解析'
        '(逐字对齐 v7 providerOptionsName = provider.includes("azure") '
        "? 'azure' : 'openai')", () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_azure_1',
            'created_at': 1700000000,
            'model': 'gpt-5.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'azure': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['reasoning'], {'effort': 'high', 'summary': 'detailed'});
      expect(result.warnings, isEmpty);
    });

    test(
        'provider 名含 azure 且 "azure" 键缺失时,回退读取 "openai" 键'
        '(对齐 v7 openaiOptions == null && providerOptionsName !== "openai" '
        '的二次解析)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_azure_2',
            'created_at': 1700000000,
            'model': 'gpt-5.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['reasoning'], {'effort': 'high', 'summary': 'detailed'});
      expect(result.warnings, isEmpty);
    });

    test(
        '自定义(非 azure)provider 名 + "openai" 键:仍按既有行为正常解析'
        '(v7 下自定义 name 同样落到 "openai" 键,行为不变)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_custom_1',
            'created_at': 1700000000,
            'model': 'gpt-5.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5.1',
        config: OpenAiConfig(
          providerName: 'custom-openai',
          baseUrl: 'https://my-proxy.example.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'high'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['reasoning'], {'effort': 'high', 'summary': 'detailed'});
      expect(result.warnings, isEmpty);
    });

    test(
        'provider 名含 azure 时,输出侧 TextContent/ReasoningContent 的 '
        'providerMetadata key 为 "azure" 而非 "openai"'
        '(逐字对齐 v7 输出侧动态 [providerOptionsName] key)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_azure_3',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello there',
                    'annotations': [],
                  },
                ],
              },
              {
                'type': 'reasoning',
                'id': 'rs_1',
                'summary': [
                  {'type': 'summary_text', 'text': 'thinking...'},
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      final result = await model.doGenerate(optionsWith());

      final text = result.content.whereType<TextContent>().single;
      expect(text.providerMetadata?.containsKey('openai'), isFalse);
      expect(text.providerMetadata?['azure']?['itemId'], 'msg_1');

      final reasoning = result.content.whereType<ReasoningContent>().single;
      expect(reasoning.providerMetadata?.containsKey('openai'), isFalse);
      expect(reasoning.providerMetadata?['azure']?['itemId'], 'rs_1');

      expect(result.providerMetadata?.containsKey('openai'), isFalse);
      expect(result.providerMetadata?['azure']?['responseId'], 'resp_azure_3');
    });

    test(
        'provider 名含 azure + conversation + 挂 "azure" itemId 的 stored '
        '历史:input 不含这些 item(端到端,逐字对齐上游无 fallback 的 '
        'providerOptionsName 读取)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_azure_4',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: OpenAiConfig(
          providerName: 'azure-x',
          baseUrl: 'https://api.openai.com/v1',
          headers: () => {'Authorization': 'Bearer test-key'},
          client: client,
        ),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')]),
            AssistantMessage([
              TextPart(
                'hello',
                providerOptions: {
                  'azure': {'itemId': 'msg_1'},
                },
              ),
              ReasoningPart(
                'thinking...',
                providerOptions: {
                  'azure': {'itemId': 'rs_1'},
                },
              ),
              ToolCallPart(
                toolCallId: 'call_1',
                toolName: 'get_weather',
                input: {'city': 'nyc'},
                providerOptions: {
                  'azure': {'itemId': 'fc_1'},
                },
              ),
            ]),
          ],
          providerOptions: const <String, JsonObject>{
            'azure': <String, Object?>{'conversation': 'conv_abc'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final input = sentBody['input']! as List<Object?>;
      expect(input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hi'},
          ],
        },
      ]);
      expect(sentBody['conversation'], 'conv_abc');
    });

    test(
        'o3(不支持 non-reasoning 参数)在 reasoningEffort=none 时依旧裁剪 temperature/topP',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_9',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          temperature: 0.7,
          topP: 0.9,
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'reasoningEffort': 'none'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('temperature'), isFalse);
      expect(sentBody.containsKey('top_p'), isFalse);
      expect(
        result.warnings.whereType<UnsupportedWarning>(),
        isNotEmpty,
      );
    });

    test(
        'options.reasoning=providerDefault 视为未设置:请求体无 reasoning '
        '字段,且无 warning', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_10',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          reasoning: ReasoningEffort.providerDefault,
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('reasoning'), isFalse);
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isFalse,
      );
    });

    test(
        '非推理模型 + 标准 options.reasoning=medium:请求体无 reasoning 字段,'
        '且产生 warning', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_11',
            'created_at': 1700000000,
            'model': 'gpt-4o',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4o',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          reasoning: ReasoningEffort.medium,
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('reasoning'), isFalse);
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isTrue,
      );
    });

    test(
        '非推理模型 + options.reasoning=providerDefault:请求体无 reasoning '
        '字段,且无 warning(providerDefault 本就等于未设置)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_12',
            'created_at': 1700000000,
            'model': 'gpt-4o',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4o',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          reasoning: ReasoningEffort.providerDefault,
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('reasoning'), isFalse);
      expect(
        result.warnings.any(
            (w) => w is UnsupportedWarning && w.feature == 'reasoningEffort'),
        isFalse,
      );
    });

    test(
        'responseFormat schema without description omits the nested '
        'description key', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_10',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          responseFormat: ResponseFormatJson(
            schema: const JsonSchema({'type': 'object'}),
          ),
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final format = (sentBody['text']! as Map<String, Object?>)['format']!
          as Map<String, Object?>;
      expect(format.containsKey('description'), isFalse);
      expect(format['type'], 'json_schema');
      expect(format['name'], 'response');
    });

    test(
        'responseFormat schema with description keeps the nested '
        'description key', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_11',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          responseFormat: ResponseFormatJson(
            schema: const JsonSchema({'type': 'object'}),
            description: 'a structured reply',
          ),
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final format = (sentBody['text']! as Map<String, Object?>)['format']!
          as Map<String, Object?>;
      expect(format['description'], 'a structured reply');
    });

    test(
        'conversation and previousResponseId both set: request body keeps '
        'only conversation, previousResponseId is dropped, warning still '
        'present', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_12',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{
              'conversation': 'conv_123',
              'previousResponseId': 'resp_abc',
            },
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['conversation'], 'conv_123');
      expect(sentBody.containsKey('previous_response_id'), isFalse);
      expect(
        result.warnings.any(
          (w) => w is UnsupportedWarning && w.feature == 'conversation',
        ),
        isTrue,
      );
    });

    test('conversation alone is sent normally', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_13',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'conversation': 'conv_123'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['conversation'], 'conv_123');
      expect(sentBody.containsKey('previous_response_id'), isFalse);
      expect(
        result.warnings.any((w) => w is UnsupportedWarning),
        isFalse,
      );
    });

    test('previousResponseId alone is sent normally', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_14',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'previousResponseId': 'resp_abc'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['previous_response_id'], 'resp_abc');
      expect(sentBody.containsKey('conversation'), isFalse);
      expect(
        result.warnings.any((w) => w is UnsupportedWarning),
        isFalse,
      );
    });

    test(
        'previousResponseId + stored assistant history: stored items are '
        'skipped from input', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_15',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')]),
            AssistantMessage([
              ReasoningPart(
                'thinking...',
                providerOptions: {
                  'openai': {'itemId': 'rs_1'},
                },
              ),
              ToolCallPart(
                toolCallId: 'call_1',
                toolName: 'get_weather',
                input: {'city': 'nyc'},
                providerOptions: {
                  'openai': {'itemId': 'fc_1'},
                },
              ),
            ]),
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'previousResponseId': 'resp_abc'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final input = sentBody['input']! as List<Object?>;
      // 只剩下 user 消息;stored reasoning/function-call item(带 itemId)
      // 在续接模式下被跳过,不出现在 input 里(Fix 1)。
      expect(input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hi'},
          ],
        },
      ]);
    });

    test(
        'without previousResponseId, stored assistant history keeps '
        'item_reference behavior (no regression)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_16',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')]),
            AssistantMessage([
              ReasoningPart(
                'thinking...',
                providerOptions: {
                  'openai': {'itemId': 'rs_1'},
                },
              ),
            ]),
          ],
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final input = sentBody['input']! as List<Object?>;
      expect(input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hi'},
          ],
        },
        {'type': 'item_reference', 'id': 'rs_1'},
      ]);
    });

    test(
        'conversation + stored assistant history: stored items (including '
        'text) are skipped from input', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_17',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')]),
            AssistantMessage([
              TextPart(
                'hello',
                providerOptions: {
                  'openai': {'itemId': 'msg_1'},
                },
              ),
              ReasoningPart(
                'thinking...',
                providerOptions: {
                  'openai': {'itemId': 'rs_1'},
                },
              ),
              ToolCallPart(
                toolCallId: 'call_1',
                toolName: 'get_weather',
                input: {'city': 'nyc'},
                providerOptions: {
                  'openai': {'itemId': 'fc_1'},
                },
              ),
            ]),
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'conversation': 'conv_abc'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      final input = sentBody['input']! as List<Object?>;
      // conversation 续接模式下,带 itemId 的 stored text/reasoning/
      // function-call 全部跳过(与 previousResponseId 不同,text 也在
      // 跳过范围内,对齐上游 raw ~235 行),只剩 user 消息;
      // conversation 字段本身照常下发。
      expect(input, [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hi'},
          ],
        },
      ]);
      expect(sentBody['conversation'], 'conv_abc');
    });

    test(
        'store:false + reasoning model auto-includes '
        'reasoning.encrypted_content, merged with caller include without '
        'duplicates', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_inc',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{
              'store': false,
              'include': <Object?>['message.input_image.image_url'],
            },
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['include'], [
        'message.input_image.image_url',
        'reasoning.encrypted_content',
      ]);
    });

    test(
        'store unset (defaults true) or non-reasoning model: '
        'reasoning.encrypted_content is not auto-included', () async {
      for (final (modelId, options) in [
        ('o3', const <String, Object?>{}),
        ('gpt-4.1', const <String, Object?>{'store': false}),
      ]) {
        final client = FakeHttpClient(
          responseBuilder: (request) async => fakeStreamedResponse(
            statusCode: 200,
            body: jsonEncode({
              'id': 'resp_inc2',
              'created_at': 1700000000,
              'model': modelId,
              'output': <Object?>[],
              'usage': {'input_tokens': 1, 'output_tokens': 1},
            }),
          ),
        );
        final model = OpenAiResponsesLanguageModel(
          modelId,
          config: configWith(client),
        );

        await model.doGenerate(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
            providerOptions: <String, JsonObject>{'openai': options},
          ),
        );

        final sentBody =
            jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
        expect(
          sentBody.containsKey('include'),
          isFalse,
          reason: 'modelId=$modelId options=$options',
        );
      }
    });

    test(
        'store:false + reasoning model: caller include already containing '
        '"reasoning.encrypted_content" is not duplicated', () async {
      // Fix 6 补充用例:`addInclude` 的去重分支此前只被「caller include +
      // 其他 key」的场景覆盖过(见上一个 test),没有用例覆盖「caller
      // include 恰好已经包含即将被自动追加的那个 key」这一路径。
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_inc_dedupe',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{
              'store': false,
              'include': <Object?>['reasoning.encrypted_content'],
            },
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['include'], ['reasoning.encrypted_content']);
    });

    test('logprobs:true auto-includes with top_logprobs=20 (TOP_LOGPROBS_MAX)',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_inc_true',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'logprobs': true},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['include'], ['message.output_text.logprobs']);
      expect(sentBody['top_logprobs'], 20);
    });

    test(
        'logprobs:0 is rejected by the provider options schema before '
        '_buildArgs runs (schema requires integer minimum:1) — the "0 is a '
        'valid count, don\'t treat as unset" gate in _buildArgs is '
        'therefore unreachable via providerOptions for the integer branch',
        () async {
      // Fix 6 要求断言 logprobs:0 的「实际请求体行为」——核实后发现
      // `responses_options.dart` 的 JSON Schema 对 `logprobs` 的 oneOf 分支
      // 是 `boolean` 或 `integer(minimum:1, maximum:20)`,`0` 落在两个分支
      // 之外,`fromProviderOptions` 会在 `_buildArgs` 的 switch 分支执行前
      // 就因 schema 校验失败而抛出——`_buildArgs` 里 `topLogprobs != 0`
      // 的显式判断因此无法通过 `providerOptions` 触发,只在直接调用内部
      // 逻辑或未来放宽 schema 时才有意义。此用例记录该实际边界,而非按
      // 需求文案字面假设 `0` 能够送达请求体。
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_inc_zero',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        () => model.doGenerate(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
            providerOptions: const <String, JsonObject>{
              'openai': <String, Object?>{'logprobs': 0},
            },
          ),
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('logprobs request auto-includes message.output_text.logprobs',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_inc3',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'logprobs': 5},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['include'], ['message.output_text.logprobs']);
      expect(sentBody['top_logprobs'], 5);
    });

    test(
        'logprobs 选项设置 + output_text content part 带 logprobs 时收集进顶层 '
        'providerMetadata', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_logprobs1',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_lp1',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'logprobs': [
                      {'token': 'hello', 'logprob': -0.1},
                    ],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'logprobs': true},
          },
        ),
      );

      final logprobs = result.providerMetadata?['openai']?['logprobs'];
      expect(logprobs, [
        [
          {'token': 'hello', 'logprob': -0.1},
        ],
      ]);
    });

    test('未设置 logprobs 选项时即使响应带 logprobs 也不收集(gate 语义)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_logprobs2',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'id': 'msg_lp2',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'hello',
                    'logprobs': [
                      {'token': 'hello', 'logprob': -0.1},
                    ],
                  },
                ],
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(optionsWith());

      expect(
        result.providerMetadata?['openai']?.containsKey('logprobs'),
        isNot(isTrue),
      );
    });

    test('doGenerate preserves response headers in ResponseInfo', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_18',
            'created_at': 1700000000,
            'model': 'gpt-4.1',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
          headers: {'x-request-id': 'req_abc123'},
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
        ),
      );

      expect(result.response?.headers?['x-request-id'], 'req_abc123');
    });
  });

  group('OpenAiResponsesLanguageModel — service_tier capability gating', () {
    test('serviceTier=flex is dropped with a warning on unsupported models',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_17',
            'created_at': 1700000000,
            'model': 'gpt-4o',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-4o',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'flex'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('service_tier'), isFalse);
      expect(
        result.warnings
            .any((w) => w is UnsupportedWarning && w.feature == 'serviceTier'),
        isTrue,
      );
    });

    test('serviceTier=flex passes through unchanged on supported models',
        () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_18',
            'created_at': 1700000000,
            'model': 'o3',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'o3',
        config: configWith(client),
      );

      await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'flex'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody['service_tier'], 'flex');
    });

    test(
        'serviceTier=priority is dropped with a warning on unsupported '
        'models', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 'resp_19',
            'created_at': 1700000000,
            'model': 'gpt-5-nano',
            'output': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }),
        ),
      );

      final model = OpenAiResponsesLanguageModel(
        'gpt-5-nano',
        config: configWith(client),
      );

      final result = await model.doGenerate(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
          providerOptions: const <String, JsonObject>{
            'openai': <String, Object?>{'serviceTier': 'priority'},
          },
        ),
      );

      final sentBody =
          jsonDecode(client.recordedBodies.single) as Map<String, Object?>;
      expect(sentBody.containsKey('service_tier'), isFalse);
      expect(
        result.warnings
            .any((w) => w is UnsupportedWarning && w.feature == 'serviceTier'),
        isTrue,
      );
    });
  });

  Future<List<LanguageModelStreamPart>> collectStream(
    String sseText, {
    ProviderOptions? providerOptions,
    bool? includeRawChunks,
    List<LanguageModelTool>? tools,
  }) async {
    final client = FakeHttpClient(
      responseBuilder: (request) async => fakeStreamedResponse(
        statusCode: 200,
        body: sseText,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    final model = OpenAiResponsesLanguageModel(
      'gpt-4.1',
      config: OpenAiConfig(
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        headers: () => {'Authorization': 'Bearer test-key'},
        client: client,
      ),
    );
    final result = await model.doStream(
      LanguageModelCallOptions(
        prompt: const [
          UserMessage([TextPart('hi')])
        ],
        providerOptions: providerOptions,
        includeRawChunks: includeRawChunks,
        tools: tools,
      ),
    );
    return result.stream.toList();
  }

  group('OpenAiResponsesLanguageModel.doStream', () {
    test('text stream emits text-start/delta/delta/end + finish', () async {
      final parts = await collectStream(_responsesTextStream);

      expect(parts.whereType<StreamStart>(), hasLength(1));
      expect(parts.whereType<ResponseMetadata>().single.id, 'resp_s1');
      final starts = parts.whereType<TextStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.single.id, 'msg_1');
      final deltas = parts.whereType<TextDelta>().toList();
      expect(deltas.map((d) => d.delta).toList(), ['Hel', 'lo']);
      final textEnd = parts.whereType<TextEnd>().single;
      // 无 annotation.added 事件时不应带 annotations 键(回归)。
      expect(
        textEnd.providerMetadata?['openai']?.containsKey('annotations'),
        isNot(isTrue),
      );
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
      expect(finish.usage.inputTokens.total, 10);
      expect(finish.usage.outputTokens.total, 2);
    });

    test(
        'response.output_text.annotation.added(url_citation + '
        'file_citation + container_file_citation)流中产出对应 '
        'SourceContent,TextEnd.providerMetadata 并入完整 annotations 列表', () async {
      final parts = await collectStream(_responsesTextStreamWithAnnotations);

      final sources = parts.whereType<SourceContent>().toList();
      expect(sources, hasLength(3));

      final urlSource = sources[0];
      expect(urlSource.sourceType, SourceType.url);
      expect(urlSource.url, 'https://example.com/a');
      expect(urlSource.title, 'Example A');

      final fileSource = sources[1];
      expect(fileSource.sourceType, SourceType.document);
      expect(fileSource.mediaType, 'text/plain');
      expect(fileSource.title, 'doc.pdf');
      expect(fileSource.filename, 'doc.pdf');
      expect(
        fileSource.providerMetadata?['openai'],
        {'type': 'file_citation', 'fileId': 'file_123', 'index': 3},
      );

      final containerFileSource = sources[2];
      expect(containerFileSource.sourceType, SourceType.document);
      expect(containerFileSource.mediaType, 'text/plain');
      expect(containerFileSource.title, 'report.csv');
      expect(containerFileSource.filename, 'report.csv');
      expect(containerFileSource.providerMetadata?['openai'], {
        'type': 'container_file_citation',
        'containerId': 'cntr_1',
        'fileId': 'cfile_123',
        'filename': 'report.csv',
        'index': 4,
        'startIndex': 11,
        'endIndex': 22,
      });

      // 三条 SourceContent 均出现在 TextEnd 之前(对应各自
      // annotation.added 事件到达的时机,早于 output_item.done)。
      final textEndIndex = parts.indexWhere((p) => p is TextEnd);
      final sourceIndices = <int>[
        parts.indexOf(sources[0]),
        parts.indexOf(sources[1]),
        parts.indexOf(sources[2]),
      ];
      expect(sourceIndices.every((i) => i < textEndIndex), isTrue);

      final textEnd = parts.whereType<TextEnd>().single;
      final annotations =
          textEnd.providerMetadata?['openai']?['annotations'] as List<Object?>?;
      expect(annotations, hasLength(3));
      expect(annotations![0], {
        'type': 'url_citation',
        'url': 'https://example.com/a',
        'title': 'Example A',
      });
      expect(annotations[1], {
        'type': 'file_citation',
        'file_id': 'file_123',
        'filename': 'doc.pdf',
        'index': 3,
      });
      expect(annotations[2], {
        'type': 'container_file_citation',
        'container_id': 'cntr_1',
        'file_id': 'cfile_123',
        'filename': 'report.csv',
        'index': 4,
        'start_index': 11,
        'end_index': 22,
      });
    });

    test(
        'output_text.delta 带 logprobs 且调用方设置了 logprobs 选项时收集进 '
        'FinishPart providerMetadata', () async {
      final parts = await collectStream(
        _responsesTextStreamWithLogprobs,
        providerOptions: const <String, JsonObject>{
          'openai': <String, Object?>{'logprobs': true},
        },
      );

      final finish = parts.whereType<FinishPart>().single;
      final logprobs = finish.providerMetadata?['openai']?['logprobs'];
      expect(logprobs, [
        [
          {'token': 'Hel', 'logprob': -0.2},
        ],
        [
          {'token': 'lo', 'logprob': -0.3},
        ],
      ]);
    });

    test(
        '未设置 logprobs 选项时即使 output_text.delta 带 logprobs 也不收集'
        '(gate 语义)', () async {
      final parts = await collectStream(_responsesTextStreamWithLogprobs);

      final finish = parts.whereType<FinishPart>().single;
      expect(
        finish.providerMetadata?['openai']?.containsKey('logprobs'),
        isNot(isTrue),
      );
    });

    test('doStream preserves response headers in ResponseInfo', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: _responsesTextStream,
          headers: {
            'content-type': 'text/event-stream',
            'x-request-id': 'req_stream_1',
          },
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doStream(
        LanguageModelCallOptions(
          prompt: const [
            UserMessage([TextPart('hi')])
          ],
        ),
      );
      await result.stream.drain<void>();

      expect(result.response?.headers?['x-request-id'], 'req_stream_1');
    });

    test('function_call stream emits tool-input-start/delta/end + tool-call',
        () async {
      final parts = await collectStream(_responsesFunctionCallStream);

      expect(parts.whereType<ToolInputStart>().single.id, 'call_1');
      final deltas = parts.whereType<ToolInputDelta>().toList();
      expect(deltas.map((d) => d.delta).join(), '{"city":"nyc"}');
      expect(parts.whereType<ToolInputEnd>(), hasLength(1));
      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'call_1');
      expect(call.toolName, 'get_weather');
      expect(call.input, '{"city":"nyc"}');
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('web_search_call stream emits provider-executed tool call/result',
        () async {
      final parts = await collectStream(
        _responsesWebSearchStream,
        tools: [openAiTools.webSearch()],
      );

      final starts = parts.whereType<ToolInputStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.single.id, 'ws_1');
      expect(starts.single.toolName, 'web_search');
      expect(starts.single.providerExecuted, isTrue);

      expect(parts.whereType<ToolInputEnd>().single.id, 'ws_1');

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'ws_1');
      expect(call.toolName, 'web_search');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'ws_1');
      expect(result.toolName, 'web_search');
      expect(result.result, {
        'action': {
          'type': 'search',
          'queries': ['dart ai sdk'],
        },
        'sources': [
          {'type': 'url', 'url': 'https://example.com'},
        ],
      });

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test('file_search_call stream emits provider-executed tool call/result',
        () async {
      final parts = await collectStream(
        _responsesFileSearchStream,
        tools: [
          openAiTools.fileSearch(vectorStoreIds: ['vs_1'])
        ],
      );

      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'fs_1');
      expect(call.toolName, 'file_search');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'fs_1');
      expect(result.toolName, 'file_search');
      expect(result.result, {
        'queries': ['embedding model'],
        'results': [
          {
            'attributes': {'kind': 'docs'},
            'fileId': 'file_1',
            'filename': 'ai.pdf',
            'score': 0.93,
            'text': 'An embedding model converts data into vectors.',
          },
        ],
      });

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test('code_interpreter_call stream emits code input and result', () async {
      final parts = await collectStream(
        _responsesCodeInterpreterStream,
        tools: [openAiTools.codeInterpreter()],
      );

      final start = parts.whereType<ToolInputStart>().single;
      expect(start.id, 'ci_1');
      expect(start.toolName, 'code_interpreter');
      expect(start.providerExecuted, isTrue);

      final input =
          parts.whereType<ToolInputDelta>().map((d) => d.delta).join();
      const code = 'print("hi")\npath = "C:\\\\tmp"';
      expect(input, jsonEncode({'containerId': 'cntr_1', 'code': code}));

      expect(parts.whereType<ToolInputEnd>().single.id, 'ci_1');

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'ci_1');
      expect(call.toolName, 'code_interpreter');
      expect(call.input, jsonEncode({'code': code, 'containerId': 'cntr_1'}));
      expect(call.providerExecuted, isTrue);

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'ci_1');
      expect(result.toolName, 'code_interpreter');
      expect(result.result, {
        'outputs': [
          {'type': 'logs', 'logs': 'hi\n'},
        ],
      });

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test(
        'image_generation_call stream emits preliminary partial images and '
        'final result', () async {
      final parts = await collectStream(
        _responsesImageGenerationStream,
        tools: [openAiTools.imageGeneration()],
      );

      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'ig_1');
      expect(call.toolName, 'image_generation');
      expect(call.input, '{}');
      expect(call.providerExecuted, isTrue);

      final results = parts.whereType<ToolResult>().toList();
      expect(results, hasLength(2));
      expect(results[0].toolCallId, 'ig_1');
      expect(results[0].toolName, 'image_generation');
      expect(results[0].result, {'result': 'partial_image_b64'});
      expect(results[0].preliminary, isTrue);

      expect(results[1].toolCallId, 'ig_1');
      expect(results[1].toolName, 'image_generation');
      expect(results[1].result, {'result': 'final_image_b64'});
      expect(results[1].preliminary, isNull);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test('mcp_call stream emits provider-executed tool call/result', () async {
      final parts = await collectStream(
        _responsesMcpStream,
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
          ),
        ],
      );

      expect(parts.whereType<ToolInputStart>(), isEmpty);
      expect(parts.whereType<ToolInputEnd>(), isEmpty);

      final listTools = parts.whereType<CustomContentBlock>().single;
      expect(listTools.kind, 'openai.mcp_list_tools');
      expect(listTools.providerMetadata?['openai']?['item'], {
        'type': 'mcp_list_tools',
        'id': 'mcp_list_1',
        'server_label': 'dmcp',
        'tools': [
          {'name': 'search'},
        ],
      });
      final mcpCallItem = {
        'type': 'mcp_call',
        'id': 'mcp_1',
        'status': 'completed',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'output': '{"ok":true}',
      };

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'mcp_1');
      expect(call.toolName, 'mcp.search');
      expect(call.input, '{"query":"dart ai sdk"}');
      expect(call.providerExecuted, isTrue);
      expect(call.isDynamic, isTrue);
      expect(call.providerMetadata?['openai']?['itemId'], 'mcp_1');
      expect(call.providerMetadata?['openai']?['item'], mcpCallItem);

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'mcp_1');
      expect(result.toolName, 'mcp.search');
      expect(result.result, {
        'type': 'call',
        'serverLabel': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'output': '{"ok":true}',
      });
      expect(result.providerMetadata?['openai']?['itemId'], 'mcp_1');
      expect(result.providerMetadata?['openai']?['item'], mcpCallItem);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test('tool_search stream emits tool call/output result', () async {
      final parts = await collectStream(
        _responsesToolSearchStream,
        tools: [openAiTools.toolSearch(execution: 'client')],
      );

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'call_tool_search');
      expect(call.toolName, 'tool_search');
      expect(
        call.input,
        jsonEncode({
          'arguments': {'goal': 'Find weather tools'},
          'call_id': 'call_tool_search',
        }),
      );
      expect(call.providerExecuted, isNull);
      expect(call.providerMetadata?['openai']?['item'], {
        'type': 'tool_search_call',
        'id': 'tsc_1',
        'execution': 'client',
        'call_id': 'call_tool_search',
        'status': 'completed',
        'arguments': {'goal': 'Find weather tools'},
      });

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'call_tool_search');
      expect(result.toolName, 'tool_search');
      expect(result.result, {
        'tools': [
          {'type': 'function', 'name': 'get_weather'},
        ],
      });
      expect(result.providerMetadata?['openai']?['item'], {
        'type': 'tool_search_output',
        'id': 'tso_1',
        'execution': 'client',
        'call_id': 'call_tool_search',
        'status': 'completed',
        'tools': [
          {'type': 'function', 'name': 'get_weather'},
        ],
      });

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('computer stream emits one complete batched tool input', () async {
      final parts = await collectStream(
        _responsesComputerStream,
        tools: [openAiTools.computer()],
      );

      expect(
        parts.whereType<ToolInputStart>().single,
        const ToolInputStart(
          id: 'computer_call_123',
          toolName: 'computer',
        ),
      );
      final delta = parts.whereType<ToolInputDelta>().single;
      expect(jsonDecode(delta.delta), {
        'actions': [
          {
            'type': 'click',
            'button': 'left',
            'x': 100,
            'y': 200,
            'keys': ['CTRL'],
          },
          {'type': 'screenshot'},
          {
            'type': 'scroll',
            'x': 130,
            'y': 230,
            'scrollX': 0,
            'scrollY': 500,
          },
        ],
        'pendingSafetyChecks': [
          {
            'id': 'safety_123',
            'code': 'confirm_action',
            'message': 'Confirm this action.',
          },
        ],
        'status': 'completed',
      });
      expect(parts.whereType<ToolInputEnd>().single.id, 'computer_call_123');
      final call = parts.whereType<ToolCall>().single;
      expect(call.toolCallId, 'computer_call_123');
      expect(call.toolName, 'computer');
      expect(call.input, delta.delta);
      expect(
        call.providerMetadata?['openai']?['itemId'],
        'computer_item_123',
      );
      expect(
        parts.whereType<FinishPart>().single.finishReason.unified,
        FinishReasonType.toolCalls,
      );
    });

    test('failed mcp_call stream emits an error tool result', () async {
      final parts = await collectStream(
        _responsesMcpErrorStream,
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
          ),
        ],
      );

      final result = parts.whereType<ToolResult>().single;
      expect(result.toolCallId, 'mcp_1');
      expect(result.toolName, 'mcp.search');
      expect(result.isError, isTrue);
      expect(result.result, {
        'type': 'call',
        'serverLabel': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
        'error': {'message': 'MCP server denied the request'},
      });
    });

    test('mcp_approval_request stream emits tool call and approval request',
        () async {
      final parts = await collectStream(
        _responsesMcpApprovalRequestStream,
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
          ),
        ],
      );

      final call = parts.whereType<ToolCall>().single;
      expect(call.toolName, 'mcp.search');
      expect(call.input, '{"query":"dart ai sdk"}');
      expect(call.providerExecuted, isTrue);
      expect(call.isDynamic, isTrue);
      expect(call.providerMetadata?['openai']?['item'], {
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'approval_request_id': 'approval_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      });

      final approval = parts.whereType<ToolApprovalRequest>().single;
      expect(approval.approvalId, 'approval_1');
      expect(approval.toolCallId, call.toolCallId);
      expect(approval.providerMetadata?['openai']?['item'], {
        'type': 'mcp_approval_request',
        'id': 'approval_item_1',
        'approval_request_id': 'approval_1',
        'server_label': 'dmcp',
        'name': 'search',
        'arguments': '{"query":"dart ai sdk"}',
      });

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.toolCalls);
    });

    test('refusal.delta events emit text-delta and complete the block',
        () async {
      final parts = await collectStream(_responsesRefusalStream);

      expect(parts.whereType<TextStart>().single.id, 'msg_refusal_1');
      final deltas = parts.whereType<TextDelta>().toList();
      expect(deltas.map((d) => d.delta).toList(),
          ['I cannot', ' help with that.']);
      expect(parts.whereType<TextEnd>(), hasLength(1));
      // refusal 驱动的文本块收尾带 refusal 标记(与非流式 refusal
      // content part 及 chat 双路对称),供 streamText 聚合后区分拒绝
      // 回复与普通文本。
      final endMetadata =
          parts.whereType<TextEnd>().single.providerMetadata?['openai'];
      expect(endMetadata?['refusal'], isTrue);
      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.stop);
    });

    test('plain output_text block does not carry a refusal marker', () async {
      final parts = await collectStream(_responsesTextStream);

      final endMetadata =
          parts.whereType<TextEnd>().single.providerMetadata?['openai'];
      expect(endMetadata?.containsKey('refusal'), isNot(isTrue));
    });

    test(
        'reasoning stream (store=true) concludes at reasoning_summary_part.done',
        () async {
      final parts = await collectStream(_responsesReasoningStreamStoreTrue);

      expect(parts.whereType<ReasoningStart>(), hasLength(1));
      expect(parts.whereType<ReasoningDelta>().single.delta, 'thinking');
      final ends = parts.whereType<ReasoningEnd>().toList();
      expect(ends, hasLength(1));
      // store=true: reasoning-end 在 output_item.done 之前(由
      // reasoning_summary_part.done 立即触发)。
      final doneIndex = parts.indexWhere(
        (p) => p is ReasoningEnd,
      );
      expect(doneIndex, greaterThanOrEqualTo(0));
    });

    test(
        'reasoning stream (store=false) defers conclusion to output_item.done '
        'and carries encrypted_content', () async {
      final parts = await collectStream(
        _responsesReasoningStreamStoreFalse,
        providerOptions: const {
          'openai': {'store': false},
        },
      );

      final end = parts.whereType<ReasoningEnd>().single;
      expect(
        end.providerMetadata?['openai']?['reasoningEncryptedContent'],
        'enc_xyz',
      );
    });

    test(
        'reasoning stream (store=false, multi-summary) only the final '
        'reasoning-end carries encrypted_content', () async {
      // 回归 codex PR #4 round-8 P2:store:false 且一个 reasoning item 有
      // 多个 summary part 时,前一个 summary 在下一个 summary
      // part.added 时被 can-conclude 提前 conclude——此时
      // encrypted_content 尚不可用(只在 item 级别的 output_item.done
      // 才就位),逐字对齐 raw ~2037-2045 行:该 reasoning-end 的
      // providerMetadata 只有 itemId,不带 reasoningEncryptedContent
      // 键。只有仍处于 active/can-conclude 状态、活到
      // output_item.done 的最后一个 summary part 才会带上真正的
      // encrypted_content(raw ~1865-1877 行)。
      final parts = await collectStream(
        _responsesReasoningStreamStoreFalseMultiSummary,
        providerOptions: const {
          'openai': {'store': false},
        },
      );

      expect(parts.whereType<ReasoningStart>(), hasLength(2));
      final ends = parts.whereType<ReasoningEnd>().toList();
      expect(ends, hasLength(2));

      final firstEnd = ends.firstWhere((e) => e.id == 'rs_3:0');
      final secondEnd = ends.firstWhere((e) => e.id == 'rs_3:1');

      // 事件顺序与上游语义一致:第一个 summary 的 reasoning-end 在新
      // summary part.added 时提前发出,排在第二个 summary 的
      // reasoning-start 之前。
      final firstEndIndex = parts.indexOf(firstEnd);
      final secondStartIndex = parts.indexWhere(
        (p) => p is ReasoningStart && p.id == 'rs_3:1',
      );
      expect(firstEndIndex, lessThan(secondStartIndex));

      // 提前 conclude 的第一个 summary:没有 encrypted_content 键。
      expect(
        firstEnd.providerMetadata?['openai']?.containsKey(
          'reasoningEncryptedContent',
        ),
        isFalse,
      );

      // 活到 output_item.done 的第二个(最后一个)summary:带上真正的
      // encrypted_content。
      expect(
        secondEnd.providerMetadata?['openai']?['reasoningEncryptedContent'],
        'enc_final',
      );
    });

    test('incomplete stream sets finishReason=length and flushes usage',
        () async {
      final parts = await collectStream(_responsesIncompleteStream);

      final finish = parts.whereType<FinishPart>().single;
      expect(finish.finishReason.unified, FinishReasonType.length);
      expect(finish.finishReason.raw, 'max_output_tokens');
      expect(finish.usage.outputTokens.total, 1);
    });

    test(
        'flat "error" event before any output: doStream Future throws '
        'ApiCallError (probe extended to per-wire matchers)', () async {
      // codex PR #4 round-16 P2 修复后:`throwIfStreamErrorBeforeOutput`
      // 的错误判定改由调用方按各自 wire 的形状传入 `getError`(见
      // `responses_language_model.dart` `doStream` 调用点),responses
      // 侧的 `getError` 识别顶层 `{type:'error',...}` 帧(与带 error 的
      // `response.failed` 帧)——不再局限于 chat 的嵌套 `{error:{...}}`
      // 信封。此扁平错误帧现在会从 `doStream` 的 Future 层同步 throw
      // `ApiCallError`,不再原样前拼回流、也不再产出 ErrorPart。
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: _responsesErrorBeforeOutputStream,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        () => model.doStream(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'You exceeded your quota',
          ),
        ),
      );
    });

    test(
        '"response.created" then flat "error" before any output: doStream '
        'Future throws ApiCallError (probe window extends past the first '
        'metadata frame)', () async {
      // 窗口扩展的核心新行为:probe 不再只 peek 首帧——response.created
      // 是元数据帧(非输出、非错误),探测应继续读下一帧并在其上命中
      // error 判定。
      final streamWithMetadataThenError = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_meta_err","created_at":1700000000,"model":"gpt-4.1"}}

event: error
data: {"type":"error","sequence_number":1,"code":"insufficient_quota","message":"You exceeded your quota"}

''');
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: streamWithMetadataThenError,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        () => model.doStream(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'You exceeded your quota',
          ),
        ),
      );
    });

    test(
        'first frame "response.failed" with error: doStream Future throws '
        'ApiCallError', () async {
      final responseFailedFirstFrame = _flushLeft('''
event: response.failed
data: {"type":"response.failed","sequence_number":1,"response":{"error":{"code":"server_error","message":"internal error"}}}

''');
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: responseFailedFirstFrame,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        () => model.doStream(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'internal error',
          ),
        ),
      );
    });

    test(
        '"response.created" then unmodeled "response.in_progress" then '
        '"error": doStream Future throws ApiCallError (probe window stays '
        'open through unmodeled metadata frames)', () async {
      // 回归 Fix 1:`response.in_progress` 不在上游 discriminated union
      // 内(上游 schema fallback 会把它转成 `unknown_chunk`),白名单版
      // `_isResponsesOutputChunk` 必须把它当成"非输出 chunk"继续探测,
      // 而不是像旧的黑名单实现那样把它误判成输出、提前关闭探测窗口——
      // 否则紧随其后的 `error` 帧只会在流内产出 `ErrorPart`,doStream 的
      // Future 不会抛出。
      final streamWithInProgressThenError = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_in_progress","created_at":1700000000,"model":"gpt-4.1"}}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_in_progress"}}

event: error
data: {"type":"error","sequence_number":1,"code":"insufficient_quota","message":"You exceeded your quota"}

''');
      final client = FakeHttpClient(
        responseBuilder: (request) async => fakeStreamedResponse(
          statusCode: 200,
          body: streamWithInProgressThenError,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      await expectLater(
        () => model.doStream(
          LanguageModelCallOptions(
            prompt: const [
              UserMessage([TextPart('hi')])
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>().having(
            (e) => e.message,
            'message',
            'You exceeded your quota',
          ),
        ),
      );
    });

    test(
        '"response.created" then "response.in_progress" then normal output: '
        'no regression', () async {
      // 确认 Fix 1 的白名单不会误伤正常流:`response.in_progress` 之后
      // 紧跟真正的输出 chunk 时,探测窗口应在 `response.output_item.added`
      // 上停止,后续照常流出 TextDelta/FinishPart,不产出 ErrorPart。
      final streamWithInProgressThenOutput = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_in_progress_ok","created_at":1700000000,"model":"gpt-4.1"}}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_in_progress_ok"}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_ip"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_ip","delta":"ok"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_ip"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}

''');

      final parts = await collectStream(streamWithInProgressThenOutput);

      expect(parts.whereType<TextDelta>().single.delta, 'ok');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), hasLength(1));
    });

    test('error after output starts emits ErrorPart as a terminal event',
        () async {
      // `_responsesErrorAfterOutputStream`(created → output_item.added →
      // delta → failed):output_item.added 已是输出 chunk,探测窗口在
      // 它上面停止,后续的 `response.failed` 帧留给流状态机按既有
      // error-as-terminal-event 语义处理,行为不变——确认窗口扩展不影响
      // 已经产出过输出内容的场景。
      final parts = await collectStream(_responsesErrorAfterOutputStream);

      expect(parts.whereType<TextDelta>(), isNotEmpty);
      expect(parts.whereType<ErrorPart>(), hasLength(1));
      // error-as-terminal-event: ErrorPart 之后不应再有分块。
      final errorIndex = parts.indexWhere((p) => p is ErrorPart);
      expect(errorIndex, parts.length - 1);
    });

    test(
        '连接级 Stream error(字节流 addError,非错误帧内容):流内下发 '
        'ErrorPart(不逃逸为未捕获异常),且其后无任何分块'
        '(error 即终端事件,无 FinishPart)', () async {
      final client = FakeHttpClient(
        responseBuilder: (request) async =>
            _responsesStreamedResponseWithTransportError(),
      );
      final model = OpenAiResponsesLanguageModel(
        'gpt-4.1',
        config: configWith(client),
      );

      final result = await model.doStream(
        LanguageModelCallOptions(
          prompt: const [
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
      // 不应再出现 FinishPart 或任何其他分块。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('unrecognized event types are safely ignored mid-stream', () async {
      final streamWithUnknownEvent = _flushLeft('''
event: response.created
data: {"type":"response.created","response":{"id":"resp_s7","created_at":1700000000,"model":"gpt-4.1"}}

event: response.some_future_event
data: {"type":"response.some_future_event","foo":"bar"}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_7"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_7","delta":"ok"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_7"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}

''');

      final parts = await collectStream(streamWithUnknownEvent);

      expect(parts.whereType<TextDelta>().single.delta, 'ok');
      expect(parts.whereType<ErrorPart>(), isEmpty);
      expect(parts.whereType<FinishPart>(), hasLength(1));
    });

    test(
        '帧级解析失败(SSE data 行为非法 JSON):流内下发 ErrorPart 作为终态'
        '分块,不再产出 FinishPart(与 chat 侧同一 error-as-terminal-event '
        '语义,回归 Fix 6 补充的模型级测试)', () async {
      final malformedThenValid = 'data: {not-valid-json}\n\n'
          'data: {"type":"response.output_text.delta","item_id":"msg_bad",'
          '"delta":"hi"}\n\n'
          'data: {"type":"response.completed","response":{"usage":'
          '{"input_tokens":1,"output_tokens":1}}}\n\n';

      final parts = await collectStream(malformedThenValid);

      final errorParts = parts.whereType<ErrorPart>().toList();
      expect(errorParts, hasLength(1));
      // error-as-terminal-event: ErrorPart 必须是流的最后一个分块,其后
      // 不应再出现 TextDelta/FinishPart。
      expect(parts.last, isA<ErrorPart>());
      expect(parts.whereType<TextDelta>(), isEmpty);
      expect(parts.whereType<FinishPart>(), isEmpty);
    });

    test('includeRawChunks 开启时每个事件前置发出 RawPart', () async {
      final parts = await collectStream(
        _responsesTextStream,
        includeRawChunks: true,
      );

      // RawPart 数量应等于成功解析的 SSE 事件数(本 fixture 6 个 event)。
      expect(parts.whereType<RawPart>(), hasLength(6));
    });

    test('includeRawChunks 缺省/false 时零发射 RawPart', () async {
      final defaultParts = await collectStream(_responsesTextStream);
      expect(defaultParts.whereType<RawPart>(), isEmpty);

      final explicitFalseParts = await collectStream(
        _responsesTextStream,
        includeRawChunks: false,
      );
      expect(explicitFalseParts.whereType<RawPart>(), isEmpty);
    });
  });
}
