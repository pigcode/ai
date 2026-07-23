import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (scripted-peer): P1-PROVIDER-01
  // Compatibility fixture (scripted-peer): P1-PROVIDER-02
  // Compatibility fixture (scripted-peer): P1-PROVIDER-03
  // Compatibility fixture (scripted-peer): P1-PROVIDER-04
  // Compatibility fixture (scripted-peer): P1-PROVIDER-05
  // Compatibility fixture (scripted-peer): P1-PROVIDER-06
  // Compatibility fixture (scripted-peer): P1-PROVIDER-07
  // Compatibility fixture (scripted-peer): P1-PROVIDER-08
  test('public provider contracts exchange all P1 provider fixtures', () async {
    final peer = _ScriptedProviderPeer();
    const clientTool = FunctionTool(
      name: 'client_lookup',
      inputSchema: JsonSchema(<String, Object?>{'type': 'object'}),
    );
    const providerTool = ProviderTool(
      id: 'fixture.server_lookup',
      name: 'server_lookup',
      args: <String, Object?>{'region': 'test'},
      supportsDeferredResults: true,
    );
    const options = LanguageModelCallOptions(
      prompt: <LanguageModelMessage>[
        SystemMessage('fixture system'),
        UserMessage(<UserContentPart>[
          TextPart('hello'),
          FilePart(
            data: FileDataBase64('ZmlsZQ=='),
            mediaType: 'text/plain',
          ),
        ]),
      ],
      tools: <LanguageModelTool>[clientTool, providerTool],
      toolChoice: ToolChoiceAuto(),
      includeRawChunks: true,
      providerOptions: <String, JsonObject>{
        'fixture': <String, Object?>{'mode': 'scripted'},
      },
    );

    final generated = await peer.doGenerate(options);
    expect(peer.lastOptions, same(options));
    expect(generated.content.whereType<TextContent>().single.text, 'hello');
    expect(generated.content.whereType<ReasoningContent>().single.text, 'why');
    expect(generated.content.whereType<FileContent>(), hasLength(1));
    expect(generated.content.whereType<SourceContent>(), hasLength(1));
    expect(generated.content.whereType<ToolCall>(), hasLength(1));
    expect(generated.content.whereType<ToolResult>(), hasLength(1));
    expect(generated.content.whereType<CustomContentBlock>(), hasLength(1));
    expect(generated.finishReason.unified, FinishReasonType.other);
    expect(generated.finishReason.raw, 'fixture_future_reason');
    expect(generated.usage.inputTokens.total, isNull);
    expect(generated.usage.inputTokens.cacheRead, 2);
    expect(generated.usage.outputTokens.reasoning, 3);
    expect(generated.warnings.single, isA<CompatibilityWarning>());
    expect(generated.providerMetadata?['fixture']?['requestId'], 'scripted-1');
    expect(generated.response?.headers?['x-fixture'], 'scripted');
    expect(
      options.tools!.whereType<FunctionTool>().single.name,
      'client_lookup',
    );
    expect(
      options.tools!.whereType<ProviderTool>().single.supportsDeferredResults,
      isTrue,
    );

    final normalParts = await (await peer.doStream(options)).stream.toList();
    expect(normalParts.whereType<RawPart>(), hasLength(1));
    expect(normalParts.whereType<ToolApprovalRequest>(), hasLength(1));
    expect(normalParts.whereType<FinishPart>(), hasLength(1));
    expect(normalParts.whereType<ErrorPart>(), isEmpty);

    final cancellation = CancellationController();
    final reason = StateError('scripted abort');
    cancellation.cancel(reason);
    final cancelledParts = await (await peer.doStream(
      options.copyWith(cancellation: cancellation.signal),
    ))
        .stream
        .toList();
    expect(cancelledParts.whereType<ErrorPart>(), hasLength(1));
    expect(cancelledParts.whereType<FinishPart>(), isEmpty);
    expect(
      cancelledParts.whereType<ErrorPart>().single.error,
      same(reason),
    );
    expect(
      cancelledParts.where((part) => part is ErrorPart || part is FinishPart),
      hasLength(1),
    );
    expect(languageModelSpecVersion, 'v4');
  });
}

final class _ScriptedProviderPeer implements LanguageModel {
  LanguageModelCallOptions? lastOptions;

  @override
  String get specificationVersion => languageModelSpecVersion;

  @override
  String get provider => 'fixture';

  @override
  String get modelId => 'scripted-provider-peer';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls =>
      const <String, List<RegExp>>{};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    lastOptions = options;
    return LanguageModelGenerateResult(
      content: const <LanguageModelContent>[
        TextContent('hello'),
        ReasoningContent('why'),
        FileContent(
          data: FileDataBase64('ZmlsZQ=='),
          mediaType: 'text/plain',
        ),
        SourceContent.url(
          id: 'source-1',
          url: 'https://example.test/source',
        ),
        ToolCall(
          toolCallId: 'call-1',
          toolName: 'client_lookup',
          input: '{"query":"dart"}',
        ),
        ToolResult(
          toolCallId: 'call-1',
          toolName: 'client_lookup',
          result: <String, Object?>{'answer': 42},
        ),
        CustomContentBlock(
          'fixture.widget',
          providerMetadata: <String, JsonObject>{
            'fixture': <String, Object?>{'kind': 'widget'},
          },
        ),
      ],
      finishReason: const LanguageModelFinishReason(
        FinishReasonType.other,
        raw: 'fixture_future_reason',
      ),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(cacheRead: 2),
        outputTokens: OutputTokens(reasoning: 3),
        raw: <String, Object?>{'cache_read': 2, 'reasoning': 3},
      ),
      warnings: const <Warning>[
        CompatibilityWarning('fixture', details: 'scripted peer'),
      ],
      providerMetadata: const <String, JsonObject>{
        'fixture': <String, Object?>{'requestId': 'scripted-1'},
      },
      request: const RequestInfo(body: <String, Object?>{'scripted': true}),
      response: const ResponseInfo(
        id: 'scripted-1',
        modelId: 'scripted-provider-peer',
        headers: <String, String>{'x-fixture': 'scripted'},
        body: <String, Object?>{'ok': true},
      ),
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    lastOptions = options;
    final cancellation = options.cancellation;
    if (cancellation?.isCancelled ?? false) {
      return LanguageModelStreamResult(
        stream: Stream<LanguageModelStreamPart>.fromIterable(
          <LanguageModelStreamPart>[
            const StreamStart(<Warning>[]),
            ErrorPart(cancellation!.reason),
          ],
        ),
      );
    }
    return LanguageModelStreamResult(
      stream: Stream<LanguageModelStreamPart>.fromIterable(
        const <LanguageModelStreamPart>[
          StreamStart(<Warning>[]),
          ResponseMetadata(
            id: 'scripted-1',
            modelId: 'scripted-provider-peer',
          ),
          RawPart(<String, Object?>{'wire': true}),
          ToolApprovalRequest(
            approvalId: 'approval-1',
            toolCallId: 'call-1',
          ),
          FinishPart(
            usage: LanguageModelUsage(
              inputTokens: InputTokens(cacheRead: 2),
              outputTokens: OutputTokens(reasoning: 3),
            ),
            finishReason: LanguageModelFinishReason(
              FinishReasonType.other,
              raw: 'fixture_future_reason',
            ),
          ),
        ],
      ),
    );
  }
}
