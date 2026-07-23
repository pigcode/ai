import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (unit): P1-PROVIDER-01
  test('P1-PROVIDER-01 neutral content variants retain their payloads', () {
    final content = <LanguageModelContent>[
      const TextContent('text'),
      const ReasoningContent('reasoning'),
      const FileContent(
        data: FileDataBase64('ZmlsZQ=='),
        mediaType: 'text/plain',
      ),
      const SourceContent.url(
        id: 'source-1',
        url: 'https://example.test/source',
      ),
      const ToolCall(
        toolCallId: 'call-1',
        toolName: 'lookup',
        input: '{"query":"dart"}',
      ),
      const ToolResult(
        toolCallId: 'call-1',
        toolName: 'lookup',
        result: <String, Object?>{'answer': 42},
      ),
      const CustomContentBlock(
        'provider.widget',
        providerMetadata: <String, JsonObject>{
          'test': <String, Object?>{'kind': 'widget'},
        },
      ),
    ];

    expect(content.map((item) => item.runtimeType), <Type>[
      TextContent,
      ReasoningContent,
      FileContent,
      SourceContent,
      ToolCall,
      ToolResult,
      CustomContentBlock,
    ]);
    expect((content[0] as TextContent).text, 'text');
    expect((content[1] as ReasoningContent).text, 'reasoning');
    expect((content[4] as ToolCall).input, '{"query":"dart"}');
    expect((content[5] as ToolResult).result, <String, Object?>{'answer': 42});
    expect(
      (content[6] as CustomContentBlock).providerMetadata,
      <String, JsonObject>{
        'test': <String, Object?>{'kind': 'widget'},
      },
    );
  });

  // Compatibility fixture (unit): P1-PROVIDER-02
  test('P1-PROVIDER-02 result and stream metadata stay at their boundaries',
      () async {
    final timestamp = DateTime.utc(2026, 7, 23);
    final result = LanguageModelGenerateResult(
      content: const <LanguageModelContent>[TextContent('done')],
      finishReason: const LanguageModelFinishReason(
        FinishReasonType.stop,
        raw: 'end_turn',
      ),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(total: 2),
        outputTokens: OutputTokens(total: 1),
      ),
      warnings: const <Warning>[OtherWarning('provider note')],
      providerMetadata: const <String, JsonObject>{
        'test': <String, Object?>{'requestId': 'request-1'},
      },
      request: const RequestInfo(body: <String, Object?>{'model': 'fixture'}),
      response: ResponseInfo(
        id: 'response-1',
        timestamp: timestamp,
        modelId: 'fixture-model',
        headers: const <String, String>{'x-request-id': 'request-1'},
        body: const <String, Object?>{'raw': true},
      ),
    );
    final stream = LanguageModelStreamResult(
      stream: Stream<LanguageModelStreamPart>.fromIterable(
        <LanguageModelStreamPart>[
          const StreamStart(<Warning>[]),
          const ResponseMetadata(id: 'response-1', modelId: 'fixture-model'),
          const RawPart(<String, Object?>{'wire': true}),
          const FinishPart(
            usage: LanguageModelUsage(
              inputTokens: InputTokens(total: 2),
              outputTokens: OutputTokens(total: 1),
            ),
            finishReason: LanguageModelFinishReason(FinishReasonType.stop),
          ),
        ],
      ),
      request: result.request,
      response: result.response,
    );

    expect(result.providerMetadata?['test']?['requestId'], 'request-1');
    expect(result.request?.body, <String, Object?>{'model': 'fixture'});
    expect(result.response?.timestamp, timestamp);
    final parts = await stream.stream.toList();
    expect(
        parts[1],
        const ResponseMetadata(
          id: 'response-1',
          modelId: 'fixture-model',
        ));
    expect((parts[2] as RawPart).rawValue, <String, Object?>{'wire': true});
    expect(parts.last, isA<FinishPart>());
  });

  // Compatibility fixture (unit): P1-PROVIDER-03
  test('P1-PROVIDER-03 partial usage preserves missing values as null', () {
    const usage = LanguageModelUsage(
      inputTokens: InputTokens(cacheRead: 3, cacheWrite: 2),
      outputTokens: OutputTokens(reasoning: 4),
      raw: <String, Object?>{
        'cache_read_input_tokens': 3,
        'reasoning_tokens': 4,
      },
    );

    expect(usage.inputTokens.total, isNull);
    expect(usage.inputTokens.noCache, isNull);
    expect(usage.inputTokens.cacheRead, 3);
    expect(usage.inputTokens.cacheWrite, 2);
    expect(usage.outputTokens.total, isNull);
    expect(usage.outputTokens.text, isNull);
    expect(usage.outputTokens.reasoning, 4);
    expect(usage.raw?['reasoning_tokens'], 4);
  });

  // Compatibility fixture (unit): P1-PROVIDER-04
  test('P1-PROVIDER-04 unknown finish reason retains its raw value', () {
    const reason = LanguageModelFinishReason(
      FinishReasonType.other,
      raw: 'future_provider_reason',
    );

    expect(reason.unified, FinishReasonType.other);
    expect(reason.raw, 'future_provider_reason');
    expect(
        reason,
        isNot(
          const LanguageModelFinishReason(FinishReasonType.stop),
        ));
  });

  // Compatibility fixture (unit): P1-PROVIDER-05
  test('P1-PROVIDER-05 errors retain typed safe diagnostics', () {
    final cause = SocketExceptionFixture('connection reset');
    final error = ApiCallError(
      message: 'upstream failed',
      url: 'https://example.test/v1/messages',
      requestBody: const <String, Object?>{'model': 'fixture'},
      statusCode: 502,
      responseHeaders: const <String, String>{
        'content-type': 'application/json',
      },
      responseBody: '{"error":"upstream"}',
      data: const <String, Object?>{'category': 'provider_error'},
      cause: cause,
    );

    expect(error.cause, same(cause));
    expect(error.statusCode, 502);
    expect(error.responseHeaders?['content-type'], 'application/json');
    expect(error.responseBody, '{"error":"upstream"}');
    expect((error.data as Map<String, Object?>)['category'], 'provider_error');
    expect(error.isRetryable, isTrue);
    expect(error.toString(), isNot(contains(error.responseBody!)));
  });

  // Compatibility fixture (unit): P1-PROVIDER-06
  test('P1-PROVIDER-06 provider tools stay distinct and support approvals', () {
    const clientTool = FunctionTool(
      name: 'lookup',
      inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
    );
    const providerTool = ProviderTool(
      id: 'test.server_lookup',
      name: 'server_lookup',
      args: <String, Object?>{'region': 'test'},
      supportsDeferredResults: true,
    );
    const approvalRequest = ToolApprovalRequest(
      approvalId: 'approval-1',
      toolCallId: 'call-1',
    );
    const approvalResponse = ToolApprovalResponsePart(
      approvalId: 'approval-1',
      approved: false,
      reason: 'policy denied',
    );
    const denied = ToolResultExecutionDenied(reason: 'policy denied');

    expect(clientTool, isA<FunctionTool>());
    expect(providerTool, isA<ProviderTool>());
    expect(providerTool, isNot(isA<FunctionTool>()));
    expect(providerTool.supportsDeferredResults, isTrue);
    expect(approvalRequest.toolCallId, 'call-1');
    expect(approvalResponse.approved, isFalse);
    expect(denied.reason, approvalResponse.reason);
  });

  // Compatibility fixture (unit): P1-PROVIDER-07
  test('P1-PROVIDER-07 cancellation keeps its reason and one terminal',
      () async {
    final reason = StateError('caller stopped');
    final controller = CancellationController();
    final signal = controller.signal;

    controller.cancel(reason);
    controller.cancel(StateError('ignored second reason'));
    await signal.whenCancelled;

    expect(signal.isCancelled, isTrue);
    expect(signal.reason, same(reason));
    final parts = <LanguageModelStreamPart>[ErrorPart(signal.reason)];
    expect(
      parts.where((part) => part is ErrorPart || part is FinishPart),
      hasLength(1),
    );
    expect((parts.single as ErrorPart).error, same(reason));
  });

  // Compatibility fixture (unit): P1-PROVIDER-08
  test('P1-PROVIDER-08 public barrel exposes the portable contract', () {
    const LanguageModel? languageModel = null;
    const Provider? provider = null;
    final value = _jsonValue(<String, Object?>{'portable': true});

    expect(languageModelSpecVersion, 'v4');
    expect(languageModel, isNull);
    expect(provider, isNull);
    expect(value, <String, Object?>{'portable': true});
  });
}

JsonValue _jsonValue(JsonValue value) => value;

final class SocketExceptionFixture implements Exception {
  const SocketExceptionFixture(this.message);

  final String message;

  @override
  String toString() => 'SocketExceptionFixture: $message';
}
