import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// Extracts XML-tagged reasoning from model text output.
///
/// Text enclosed in `<tagName>...</tagName>` is emitted as reasoning content,
/// while the remaining text stays in text content. The stream path handles tags
/// split across text deltas.
provider.LanguageModelMiddleware extractReasoningMiddleware({
  required String tagName,
  String separator = '\n',
  bool startWithReasoning = false,
}) {
  final openingTag = '<$tagName>';
  final closingTag = '</$tagName>';

  return provider.LanguageModelMiddleware(
    wrapGenerate: ({
      required provider.LanguageModelDoGenerate doGenerate,
      required provider.LanguageModelDoStream doStream,
      required provider.LanguageModelCallOptions params,
      required provider.LanguageModel model,
    }) async {
      final result = await doGenerate();
      return provider.LanguageModelGenerateResult(
        content: [
          for (final part in result.content)
            ...switch (part) {
              provider.TextContent(:final text) => _extractGeneratedText(
                  text: startWithReasoning ? openingTag + text : text,
                  openingTag: openingTag,
                  closingTag: closingTag,
                  separator: separator,
                  fallback: part,
                ),
              _ => [part],
            },
        ],
        finishReason: result.finishReason,
        usage: result.usage,
        warnings: result.warnings,
        providerMetadata: result.providerMetadata,
        request: result.request,
        response: result.response,
      );
    },
    wrapStream: ({
      required provider.LanguageModelDoGenerate doGenerate,
      required provider.LanguageModelDoStream doStream,
      required provider.LanguageModelCallOptions params,
      required provider.LanguageModel model,
    }) async {
      final result = await doStream();
      return provider.LanguageModelStreamResult(
        stream: _extractStream(
          result.stream,
          openingTag: openingTag,
          closingTag: closingTag,
          separator: separator,
          startWithReasoning: startWithReasoning,
        ),
        request: result.request,
        response: result.response,
      );
    },
  );
}

List<provider.LanguageModelContent> _extractGeneratedText({
  required String text,
  required String openingTag,
  required String closingTag,
  required String separator,
  required provider.TextContent fallback,
}) {
  final reasoningPieces = <String>[];
  final textPieces = <String>[];
  var isReasoning = false;
  var foundTag = false;
  var index = 0;

  while (index < text.length) {
    final tag = isReasoning ? closingTag : openingTag;
    final tagIndex = text.indexOf(tag, index);
    if (tagIndex == -1) {
      final remaining = text.substring(index);
      if (isReasoning) {
        reasoningPieces.add(remaining);
      } else {
        textPieces.add(remaining);
      }
      break;
    }

    final beforeTag = text.substring(index, tagIndex);
    if (isReasoning) {
      reasoningPieces.add(beforeTag);
    } else {
      textPieces.add(beforeTag);
    }
    foundTag = true;
    index = tagIndex + tag.length;
    isReasoning = !isReasoning;
  }

  if (!foundTag) {
    return [fallback];
  }

  final reasoningText = _joinNonEmpty(reasoningPieces, separator);
  final textWithoutReasoning = _joinNonEmpty(textPieces, separator);

  return [
    provider.ReasoningContent(
      reasoningText,
      providerMetadata: fallback.providerMetadata,
    ),
    provider.TextContent(
      textWithoutReasoning,
      providerMetadata: fallback.providerMetadata,
    ),
  ];
}

String _joinNonEmpty(List<String> pieces, String separator) {
  return pieces.where((piece) => piece.isNotEmpty).join(separator);
}

Stream<provider.LanguageModelStreamPart> _extractStream(
  Stream<provider.LanguageModelStreamPart> stream, {
  required String openingTag,
  required String closingTag,
  required String separator,
  required bool startWithReasoning,
}) async* {
  final extractions = <String, _ReasoningExtraction>{};
  final delayedTextStarts = <String, provider.TextStart>{};
  final pendingInputs = <provider.LanguageModelStreamPart>[];
  final usedReasoningIds = <String>{};
  final nativeReasoningIdRewrites = <String, String>{};
  var nextReasoningId = 0;

  String allocateReasoningId() {
    while (true) {
      final id = 'extracted-reasoning-${nextReasoningId++}';
      if (usedReasoningIds.add(id)) {
        return id;
      }
    }
  }

  await for (final input in stream) {
    pendingInputs.add(input);
    while (pendingInputs.isNotEmpty) {
      final chunk = pendingInputs.removeAt(0);

      if (chunk is provider.TextStart) {
        delayedTextStarts[chunk.id] = chunk;
        continue;
      }

      if (chunk is provider.TextEnd) {
        final pendingExtraction = _firstPendingExtraction(extractions);
        if (pendingExtraction != null && pendingExtraction.textId != chunk.id) {
          pendingExtraction.pendingChunks.add(chunk);
          continue;
        }

        final extraction = extractions.remove(chunk.id);
        final pendingCountBeforeFlush = pendingInputs.length;
        if (extraction != null) {
          extraction.mergeMetadata(chunk.providerMetadata);
          for (final part in _flushExtraction(
            extraction,
            separator: separator,
            delayedTextStarts: delayedTextStarts,
            closeReasoning: true,
            allocateReasoningId: allocateReasoningId,
            pendingInputs: pendingInputs,
          )) {
            yield part;
          }
        }
        if (pendingInputs.length > pendingCountBeforeFlush) {
          pendingInputs.add(chunk);
          continue;
        }
        final delayed = delayedTextStarts.remove(chunk.id);
        if (delayed != null) {
          yield delayed;
        }
        yield chunk;
        continue;
      }

      if (chunk is! provider.TextDelta) {
        if (chunk is provider.ErrorPart || chunk is provider.FinishPart) {
          for (final extraction in extractions.values) {
            for (final part in _flushExtraction(
              extraction,
              separator: separator,
              delayedTextStarts: delayedTextStarts,
              closeReasoning: true,
              allocateReasoningId: allocateReasoningId,
              pendingInputs: pendingInputs,
            )) {
              yield part;
            }
          }
          extractions.clear();
          for (final delayed in delayedTextStarts.values) {
            yield delayed;
          }
          delayedTextStarts.clear();
          if (pendingInputs.isNotEmpty) {
            pendingInputs.add(chunk);
            continue;
          }
        } else {
          final pendingExtraction = _firstPendingExtraction(extractions);
          if (pendingExtraction != null) {
            pendingExtraction.pendingChunks.add(chunk);
            continue;
          }
          for (final delayed in delayedTextStarts.values) {
            yield delayed;
          }
          delayedTextStarts.clear();
        }
        yield _rewriteReasoningIdOnCollision(
          chunk,
          usedReasoningIds,
          nativeReasoningIdRewrites,
          allocateReasoningId,
        );
        continue;
      }

      final textDelta = chunk;
      final pendingExtraction = _firstPendingExtraction(extractions);
      if (pendingExtraction != null &&
          pendingExtraction.textId != textDelta.id) {
        pendingExtraction.pendingChunks.add(textDelta);
        continue;
      }

      final extraction = extractions.putIfAbsent(
        textDelta.id,
        () => _ReasoningExtraction(
          isReasoning: startWithReasoning,
          textId: textDelta.id,
          startProviderMetadata:
              delayedTextStarts[textDelta.id]?.providerMetadata,
        ),
      );
      extraction.buffer += textDelta.delta;
      extraction.mergeMetadata(textDelta.providerMetadata);

      while (true) {
        final nextTag = extraction.isReasoning ? closingTag : openingTag;
        final startIndex = _getPotentialStartIndex(extraction.buffer, nextTag);

        if (startIndex == null) {
          final publishedText = extraction.buffer;
          for (final part in _publish(
            extraction,
            publishedText,
            separator: separator,
            delayedTextStarts: delayedTextStarts,
            allocateReasoningId: allocateReasoningId,
            pendingInputs: pendingInputs,
          )) {
            yield part;
          }
          extraction.buffer = '';
          if (publishedText.isNotEmpty) {
            extraction.providerMetadata = null;
          }
          break;
        }

        for (final part in _publish(
          extraction,
          extraction.buffer.substring(0, startIndex),
          separator: separator,
          delayedTextStarts: delayedTextStarts,
          allocateReasoningId: allocateReasoningId,
          pendingInputs: pendingInputs,
        )) {
          yield part;
        }

        final foundFullMatch =
            startIndex + nextTag.length <= extraction.buffer.length;
        if (!foundFullMatch) {
          extraction.buffer = extraction.buffer.substring(startIndex);
          break;
        }

        extraction.buffer =
            extraction.buffer.substring(startIndex + nextTag.length);

        if (extraction.isReasoning) {
          final reasoningId = extraction.ensureReasoningId(allocateReasoningId);
          final providerMetadata = textDelta.providerMetadata ??
              extraction.providerMetadata ??
              extraction.startProviderMetadata;
          if (extraction.isFirstReasoning) {
            yield provider.ReasoningStart(
              reasoningId,
              providerMetadata: providerMetadata,
            );
            extraction.hasActiveReasoningStart = true;
          }
          if (!extraction.hasActiveReasoningStart) {
            yield provider.ReasoningStart(
              reasoningId,
              providerMetadata: providerMetadata,
            );
          }
          yield provider.ReasoningEnd(
            reasoningId,
            providerMetadata: providerMetadata,
          );
          extraction.hasActiveReasoningStart = false;
          if (extraction.buffer.isEmpty) {
            extraction.providerMetadata = null;
          }
          if (extraction.pendingChunks.isNotEmpty) {
            final remaining = extraction.buffer;
            final remainingMetadata = extraction.providerMetadata;
            extraction.buffer = '';
            extraction.providerMetadata = null;
            _enqueuePendingChunks(
              pendingInputs,
              extraction,
              trailingChunk: remaining.isEmpty
                  ? null
                  : provider.TextDelta(
                      extraction.textId,
                      remaining,
                      providerMetadata: remainingMetadata,
                    ),
            );
            extraction.reasoningId = null;
            extraction.isReasoning = false;
            extraction.afterSwitch = true;
            break;
          }
          extraction.reasoningId = null;
        }

        extraction.isReasoning = !extraction.isReasoning;
        extraction.afterSwitch = true;
      }
    }
  }
}

provider.LanguageModelStreamPart _rewriteReasoningIdOnCollision(
  provider.LanguageModelStreamPart chunk,
  Set<String> usedReasoningIds,
  Map<String, String> nativeReasoningIdRewrites,
  String Function() allocateReasoningId,
) {
  switch (chunk) {
    case provider.ReasoningStart(:final id, :final providerMetadata):
      if (usedReasoningIds.add(id)) {
        return chunk;
      }
      final rewrittenId = allocateReasoningId();
      nativeReasoningIdRewrites[id] = rewrittenId;
      return provider.ReasoningStart(
        rewrittenId,
        providerMetadata: providerMetadata,
      );
    case provider.ReasoningDelta(
        :final id,
        :final delta,
        :final providerMetadata,
      ):
      final rewrittenId = nativeReasoningIdRewrites[id];
      if (rewrittenId == null) {
        usedReasoningIds.add(id);
        return chunk;
      }
      return provider.ReasoningDelta(
        rewrittenId,
        delta,
        providerMetadata: providerMetadata,
      );
    case provider.ReasoningEnd(:final id, :final providerMetadata):
      final rewrittenId = nativeReasoningIdRewrites.remove(id);
      if (rewrittenId == null) {
        usedReasoningIds.add(id);
        return chunk;
      }
      return provider.ReasoningEnd(
        rewrittenId,
        providerMetadata: providerMetadata,
      );
    default:
      return chunk;
  }
}

_ReasoningExtraction? _firstPendingExtraction(
  Map<String, _ReasoningExtraction> extractions,
) {
  for (final extraction in extractions.values) {
    if (extraction.buffer.isNotEmpty || extraction.isReasoning) {
      return extraction;
    }
  }
  return null;
}

Iterable<provider.LanguageModelStreamPart> _flushExtraction(
  _ReasoningExtraction extraction, {
  required String separator,
  required Map<String, provider.TextStart> delayedTextStarts,
  required bool closeReasoning,
  required String Function() allocateReasoningId,
  required List<provider.LanguageModelStreamPart> pendingInputs,
}) sync* {
  for (final part in _publish(
    extraction,
    extraction.buffer,
    separator: separator,
    delayedTextStarts: delayedTextStarts,
    allocateReasoningId: allocateReasoningId,
    pendingInputs: pendingInputs,
  )) {
    yield part;
  }
  extraction.buffer = '';
  if (closeReasoning && extraction.isReasoning) {
    final reasoningId = extraction.ensureReasoningId(allocateReasoningId);
    final providerMetadata =
        extraction.providerMetadata ?? extraction.startProviderMetadata;
    if (extraction.isFirstReasoning) {
      yield provider.ReasoningStart(
        reasoningId,
        providerMetadata: providerMetadata,
      );
      extraction.hasActiveReasoningStart = true;
    }
    if (!extraction.hasActiveReasoningStart) {
      yield provider.ReasoningStart(
        reasoningId,
        providerMetadata: providerMetadata,
      );
    }
    yield provider.ReasoningEnd(
      reasoningId,
      providerMetadata: providerMetadata,
    );
    extraction.hasActiveReasoningStart = false;
    _enqueuePendingChunks(pendingInputs, extraction);
    extraction.reasoningId = null;
  }
  extraction.providerMetadata = null;
}

Iterable<provider.LanguageModelStreamPart> _publish(
  _ReasoningExtraction extraction,
  String text, {
  required String separator,
  required Map<String, provider.TextStart> delayedTextStarts,
  required String Function() allocateReasoningId,
  required List<provider.LanguageModelStreamPart> pendingInputs,
}) sync* {
  if (text.isEmpty) {
    return;
  }

  final needsSeparator = extraction.afterSwitch &&
      (extraction.isReasoning
          ? !extraction.isFirstReasoning
          : !extraction.isFirstText);
  final outputText = needsSeparator ? separator + text : text;

  if (extraction.isReasoning) {
    final reasoningId = extraction.ensureReasoningId(allocateReasoningId);
    final providerMetadata =
        extraction.providerMetadata ?? extraction.startProviderMetadata;
    if (extraction.afterSwitch || extraction.isFirstReasoning) {
      yield provider.ReasoningStart(
        reasoningId,
        providerMetadata: providerMetadata,
      );
      extraction.hasActiveReasoningStart = true;
    }
    yield provider.ReasoningDelta(
      reasoningId,
      outputText,
      providerMetadata: providerMetadata,
    );
    extraction.isFirstReasoning = false;
  } else {
    final delayed = delayedTextStarts.remove(extraction.textId);
    if (delayed != null) {
      yield delayed;
    }
    yield provider.TextDelta(
      extraction.textId,
      outputText,
      providerMetadata: extraction.providerMetadata,
    );
    extraction.isFirstText = false;
    _enqueuePendingChunks(pendingInputs, extraction);
  }

  extraction.afterSwitch = false;
}

int? _getPotentialStartIndex(String text, String searchedText) {
  if (searchedText.isEmpty) {
    return null;
  }

  final directIndex = text.indexOf(searchedText);
  if (directIndex != -1) {
    return directIndex;
  }

  for (var i = text.length - 1; i >= 0; i--) {
    final suffix = text.substring(i);
    if (searchedText.startsWith(suffix)) {
      return i;
    }
  }

  return null;
}

void _enqueuePendingChunks(
  List<provider.LanguageModelStreamPart> pendingInputs,
  _ReasoningExtraction extraction, {
  provider.LanguageModelStreamPart? trailingChunk,
}) {
  if (extraction.pendingChunks.isEmpty) {
    if (trailingChunk != null) {
      pendingInputs.insert(0, trailingChunk);
    }
    return;
  }
  pendingInputs.insertAll(0, [
    ...extraction.pendingChunks,
    if (trailingChunk != null) trailingChunk,
  ]);
  extraction.pendingChunks.clear();
}

final class _ReasoningExtraction {
  _ReasoningExtraction({
    required this.isReasoning,
    required this.textId,
    required this.startProviderMetadata,
  });

  bool isFirstReasoning = true;
  bool isFirstText = true;
  bool hasActiveReasoningStart = false;
  bool afterSwitch = false;
  bool isReasoning;
  String buffer = '';
  final String textId;
  final provider.ProviderMetadata? startProviderMetadata;
  provider.ProviderMetadata? providerMetadata;
  String? reasoningId;
  final pendingChunks = <provider.LanguageModelStreamPart>[];

  String ensureReasoningId(String Function() allocateReasoningId) {
    return reasoningId ??= allocateReasoningId();
  }

  void mergeMetadata(provider.ProviderMetadata? next) {
    providerMetadata = next ?? providerMetadata;
  }
}
