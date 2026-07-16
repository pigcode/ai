import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as lm;
import 'package:test/test.dart';

void main() {
  const prompt = <lm.LanguageModelMessage>[
    lm.UserMessage([lm.TextPart('hi')]),
  ];
  const finishReason = lm.LanguageModelFinishReason(
    lm.FinishReasonType.stop,
  );
  const usage = lm.LanguageModelUsage(
    inputTokens: lm.InputTokens(total: 1),
    outputTokens: lm.OutputTokens(total: 2),
  );

  group('simulateStreamingMiddleware', () {
    test('streams generated text, reasoning, and stream-capable content',
        () async {
      final timestamp = DateTime.utc(2026, 7, 5);
      const source = lm.SourceContent.url(
        id: 'source-1',
        url: 'https://example.com/doc',
        title: 'Doc',
      );
      const providerMetadata = {
        'test': {'traceId': 'trace-1'},
      };
      const textMetadata = {
        'test': {'textId': 'text-1'},
      };
      const reasoningMetadata = {
        'test': {'kind': 'thinking'},
      };
      const request = lm.RequestInfo(body: {'prompt': 'hi'});
      final response = lm.ResponseInfo(
        id: 'response-1',
        timestamp: timestamp,
        modelId: 'model-from-provider',
        headers: const {'x-test': 'ok'},
        body: const {'raw': true},
      );
      final model = _GenerateOnlyModel(
        lm.LanguageModelGenerateResult(
          content: const [
            lm.TextContent('Hello', providerMetadata: textMetadata),
            lm.ReasoningContent(
              'thinking',
              providerMetadata: reasoningMetadata,
            ),
            source,
          ],
          finishReason: finishReason,
          usage: usage,
          warnings: const [lm.OtherWarning('heads up')],
          providerMetadata: providerMetadata,
          request: request,
          response: response,
        ),
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.simulateStreamingMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: prompt),
      );

      expect(result.request, request);
      expect(result.response, response);
      expect(model.generateCallCount, 1);
      expect(model.streamCallCount, 0);
      expect(await result.stream.toList(), [
        const lm.StreamStart([lm.OtherWarning('heads up')]),
        lm.ResponseMetadata(
          id: 'response-1',
          timestamp: timestamp,
          modelId: 'model-from-provider',
        ),
        const lm.TextStart('0', providerMetadata: textMetadata),
        const lm.TextDelta('0', 'Hello', providerMetadata: textMetadata),
        const lm.TextEnd('0', providerMetadata: textMetadata),
        const lm.ReasoningStart(
          '1',
          providerMetadata: reasoningMetadata,
        ),
        const lm.ReasoningDelta('1', 'thinking'),
        const lm.ReasoningEnd('1'),
        source,
        const lm.FinishPart(
          usage: usage,
          finishReason: finishReason,
          providerMetadata: providerMetadata,
        ),
      ]);
    });

    test('skips empty generated text blocks', () async {
      final model = _GenerateOnlyModel(
        const lm.LanguageModelGenerateResult(
          content: [
            lm.TextContent(''),
            lm.ToolCall(
              toolCallId: 'call-1',
              toolName: 'weather',
              input: '{"city":"Paris"}',
            ),
          ],
          finishReason: finishReason,
          usage: usage,
          warnings: [],
        ),
      );
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.simulateStreamingMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: prompt),
      );

      expect(await result.stream.toList(), [
        const lm.StreamStart([]),
        const lm.ResponseMetadata(),
        const lm.ToolCall(
          toolCallId: 'call-1',
          toolName: 'weather',
          input: '{"city":"Paris"}',
        ),
        const lm.FinishPart(
          usage: usage,
          finishReason: finishReason,
        ),
      ]);
    });

    test('converts generate failures into terminal error stream parts',
        () async {
      final error = StateError('boom');
      final model = _ThrowingGenerateModel(error);
      final wrapped = ai.wrapLanguageModel(
        model,
        ai.simulateStreamingMiddleware(),
      );

      final result = await wrapped.doStream(
        const lm.LanguageModelCallOptions(prompt: prompt),
      );
      final parts = await result.stream.toList();

      expect(result.request, isNull);
      expect(result.response, isNull);
      expect(model.generateCallCount, 1);
      expect(model.streamCallCount, 0);
      expect(parts, hasLength(1));
      expect(parts.single, isA<lm.ErrorPart>());
      expect((parts.single as lm.ErrorPart).error, same(error));
    });
  });
}

final class _GenerateOnlyModel implements lm.LanguageModel {
  _GenerateOnlyModel(this.result);

  final lm.LanguageModelGenerateResult result;
  int generateCallCount = 0;
  int streamCallCount = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'generate-only';

  @override
  String get modelId => 'generate-only-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    generateCallCount++;
    return result;
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    streamCallCount++;
    throw UnsupportedError('doStream should not be called');
  }
}

final class _ThrowingGenerateModel implements lm.LanguageModel {
  _ThrowingGenerateModel(this.error);

  final Object error;
  int generateCallCount = 0;
  int streamCallCount = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'throwing-generate';

  @override
  String get modelId => 'throwing-generate-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<lm.LanguageModelGenerateResult> doGenerate(
    lm.LanguageModelCallOptions options,
  ) async {
    generateCallCount++;
    throw error;
  }

  @override
  Future<lm.LanguageModelStreamResult> doStream(
    lm.LanguageModelCallOptions options,
  ) async {
    streamCallCount++;
    throw UnsupportedError('doStream should not be called');
  }
}
