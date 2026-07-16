import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// Simulates a streaming response from a non-streaming language model result.
///
/// The middleware implements [provider.LanguageModelMiddleware.wrapStream] by
/// calling `doGenerate` and expanding generated content into stream parts.
provider.LanguageModelMiddleware simulateStreamingMiddleware() {
  return provider.LanguageModelMiddleware(
    wrapStream: ({
      required provider.LanguageModelDoGenerate doGenerate,
      required provider.LanguageModelDoStream doStream,
      required provider.LanguageModelCallOptions params,
      required provider.LanguageModel model,
    }) async {
      final provider.LanguageModelGenerateResult result;
      try {
        result = await doGenerate();
      } catch (error) {
        return provider.LanguageModelStreamResult(
          stream: Stream.value(provider.ErrorPart(error)),
        );
      }

      return provider.LanguageModelStreamResult(
        stream: _simulateStream(result),
        request: result.request,
        response: result.response,
      );
    },
  );
}

Stream<provider.LanguageModelStreamPart> _simulateStream(
  provider.LanguageModelGenerateResult result,
) async* {
  yield provider.StreamStart(result.warnings);
  yield provider.ResponseMetadata(
    id: result.response?.id,
    timestamp: result.response?.timestamp,
    modelId: result.response?.modelId,
  );

  var id = 0;
  for (final part in result.content) {
    switch (part) {
      case provider.TextContent(:final text, :final providerMetadata):
        if (text.isEmpty) {
          continue;
        }
        final textId = '${id++}';
        yield provider.TextStart(
          textId,
          providerMetadata: providerMetadata,
        );
        yield provider.TextDelta(
          textId,
          text,
          providerMetadata: providerMetadata,
        );
        yield provider.TextEnd(
          textId,
          providerMetadata: providerMetadata,
        );
      case provider.ReasoningContent(
          :final text,
          :final providerMetadata,
        ):
        final reasoningId = '${id++}';
        yield provider.ReasoningStart(
          reasoningId,
          providerMetadata: providerMetadata,
        );
        yield provider.ReasoningDelta(reasoningId, text);
        yield provider.ReasoningEnd(reasoningId);
      case final provider.LanguageModelStreamPart streamPart:
        yield streamPart;
    }
  }

  yield provider.FinishPart(
    usage: result.usage,
    finishReason: result.finishReason,
    providerMetadata: result.providerMetadata,
  );
}
