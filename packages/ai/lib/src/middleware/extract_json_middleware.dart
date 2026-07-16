import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// Text transform used by [extractJsonMiddleware].
typedef ExtractJsonTransform = String Function(String text);

/// Extracts JSON text by stripping markdown code fences from model text output.
///
/// This is useful with structured outputs when a provider wraps JSON in
/// markdown blocks such as ````json ... ````. Non-text content and non-text
/// stream parts are preserved unchanged.
provider.LanguageModelMiddleware extractJsonMiddleware({
  ExtractJsonTransform? transform,
}) {
  final textTransform = transform ?? _defaultTransform;
  final hasCustomTransform = transform != null;

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
            if (part is provider.TextContent)
              provider.TextContent(
                textTransform(part.text),
                providerMetadata: part.providerMetadata,
              )
            else
              part,
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
        stream: _transformStream(
          result.stream,
          transform: textTransform,
          hasCustomTransform: hasCustomTransform,
        ),
        request: result.request,
        response: result.response,
      );
    },
  );
}

final _openingFence = RegExp(
  r'^\s*```[ \t]*(?:json[ \t]*)?(?:\r?\n|$)',
  caseSensitive: false,
);
final _openingFenceWithNewline = RegExp(
  r'^\s*```[ \t]*(?:json[ \t]*)?\r?\n',
  caseSensitive: false,
);
final _closingFence = RegExp(r'(?:\r?\n)?```\s*$');

String _defaultTransform(String text) {
  final openingMatch = _openingFence.firstMatch(text);
  if (openingMatch == null) {
    return text.trim();
  }
  return text
      .substring(openingMatch.end)
      .replaceFirst(_closingFence, '')
      .trim();
}

String _stripMarkdownCodeFenceSuffix(String text) {
  final match = _closingFence.firstMatch(text);
  if (match == null) {
    return text;
  }
  return text.replaceRange(match.start, match.end, '').trimRight();
}

Stream<provider.LanguageModelStreamPart> _transformStream(
  Stream<provider.LanguageModelStreamPart> stream, {
  required ExtractJsonTransform transform,
  required bool hasCustomTransform,
}) async* {
  const suffixBufferSize = 12;
  final textBlocks = <String, _TextBlock>{};
  String? activeBufferingTextId;

  await for (final chunk in stream) {
    if (chunk is provider.TextStart) {
      final block = _TextBlock(
        startEvent: chunk,
        phase: hasCustomTransform ? _TextPhase.buffering : _TextPhase.prefix,
      );
      textBlocks[chunk.id] = block;
      if (block.phase == _TextPhase.buffering) {
        activeBufferingTextId = chunk.id;
      }
      continue;
    }

    if (chunk is provider.TextDelta) {
      final block = textBlocks[chunk.id];
      if (block == null) {
        yield chunk;
        continue;
      }

      block.buffer += chunk.delta;
      block.mergeMetadata(chunk.providerMetadata);

      if (block.phase == _TextPhase.buffering) {
        activeBufferingTextId = chunk.id;
        continue;
      }

      if (block.phase == _TextPhase.prefix &&
          _advancePastPrefixIfReady(block)) {
        yield block.startEvent;
      }

      final streamEnd = _streamablePrefixEnd(
        block.buffer,
        suffixBufferSize: suffixBufferSize,
      );
      if (block.phase == _TextPhase.streaming && streamEnd > 0) {
        final toStream = block.buffer.substring(0, streamEnd);
        block.buffer = block.buffer.substring(streamEnd);
        yield provider.TextDelta(
          chunk.id,
          toStream,
          providerMetadata: block.providerMetadata,
        );
      }
      continue;
    }

    if (chunk is provider.TextEnd) {
      final block = textBlocks.remove(chunk.id);
      if (block == null) {
        yield chunk;
        continue;
      }
      if (activeBufferingTextId == chunk.id) {
        activeBufferingTextId = null;
      }

      for (final flushed in _flushTextBlock(
        id: chunk.id,
        block: block,
        transform: transform,
      )) {
        yield flushed;
      }
      for (final pending in block.pendingChunks) {
        yield pending;
      }
      yield chunk;
      continue;
    }

    if (chunk is provider.ErrorPart) {
      for (final MapEntry(:key, :value) in textBlocks.entries.toList()) {
        for (final flushed in _flushTextBlock(
          id: key,
          block: value,
          transform: transform,
        )) {
          yield flushed;
        }
        for (final pending in value.pendingChunks) {
          yield pending;
        }
      }
      textBlocks.clear();
      yield chunk;
      continue;
    }

    if (chunk is provider.RawPart) {
      final bufferingBlock = _activeBufferingBlock(
        textBlocks,
        activeBufferingTextId,
      );
      if (bufferingBlock != null) {
        bufferingBlock.pendingChunks.add(chunk);
        continue;
      }
      for (final flushed in _flushReadyPendingTextBlocks(
        textBlocks: textBlocks,
        transform: transform,
        suffixBufferSize: suffixBufferSize,
      )) {
        yield flushed;
      }
      yield chunk;
      continue;
    }

    final bufferingBlock = _activeBufferingBlock(
      textBlocks,
      activeBufferingTextId,
    );
    if (bufferingBlock != null) {
      bufferingBlock.pendingChunks.add(chunk);
      continue;
    }

    for (final flushed in _flushReadyPendingTextBlocks(
      textBlocks: textBlocks,
      transform: transform,
      suffixBufferSize: suffixBufferSize,
    )) {
      yield flushed;
    }

    yield chunk;
  }
}

_TextBlock? _activeBufferingBlock(
  Map<String, _TextBlock> textBlocks,
  String? activeBufferingTextId,
) {
  final activeBlock =
      activeBufferingTextId == null ? null : textBlocks[activeBufferingTextId];
  if (activeBlock?.phase == _TextPhase.buffering) {
    return activeBlock;
  }

  for (final block in textBlocks.values) {
    if (block.phase == _TextPhase.buffering) {
      return block;
    }
  }
  return null;
}

Iterable<provider.LanguageModelStreamPart> _flushReadyPendingTextBlocks({
  required Map<String, _TextBlock> textBlocks,
  required ExtractJsonTransform transform,
  int? suffixBufferSize,
}) sync* {
  for (final MapEntry(:key, :value) in textBlocks.entries.toList()) {
    if (value.phase == _TextPhase.buffering) {
      continue;
    }
    if (value.phase == _TextPhase.prefix && !_advancePastPrefixIfReady(value)) {
      continue;
    }
    if (!value.hasPendingOutput) {
      continue;
    }
    if (suffixBufferSize != null && value.prefixStripped) {
      yield* _flushStreamableTextBlockPrefix(
        id: key,
        block: value,
        suffixBufferSize: suffixBufferSize,
      );
      continue;
    }
    yield* _flushPendingTextBlock(
      id: key,
      block: value,
      transform: transform,
    );
  }
}

Iterable<provider.LanguageModelStreamPart> _flushStreamableTextBlockPrefix({
  required String id,
  required _TextBlock block,
  required int suffixBufferSize,
}) sync* {
  final streamEnd = _streamablePrefixEnd(
    block.buffer,
    suffixBufferSize: suffixBufferSize,
  );
  if (streamEnd <= 0) {
    return;
  }

  final toStream = block.buffer.substring(0, streamEnd);
  block.buffer = block.buffer.substring(streamEnd);
  yield provider.TextDelta(
    id,
    toStream,
    providerMetadata: block.providerMetadata,
  );
}

bool _advancePastPrefixIfReady(_TextBlock block) {
  final trimmedLeft = block.buffer.trimLeft();

  if (trimmedLeft.isNotEmpty && !trimmedLeft.startsWith('`')) {
    block.phase = _TextPhase.streaming;
    return true;
  }

  if (trimmedLeft.startsWith('```')) {
    final match = _openingFenceWithNewline.firstMatch(block.buffer);
    if (match != null) {
      block.buffer = block.buffer.substring(match.end);
      block.prefixStripped = true;
      block.phase = _TextPhase.streaming;
      return true;
    }

    if (!trimmedLeft.contains('\n')) {
      return false;
    }

    block.phase = _TextPhase.streaming;
    return true;
  }

  if (trimmedLeft.length >= 2 &&
      trimmedLeft.startsWith('`') &&
      trimmedLeft[1] != '`') {
    block.phase = _TextPhase.streaming;
    return true;
  }

  if (trimmedLeft.length >= 3 && !trimmedLeft.startsWith('```')) {
    block.phase = _TextPhase.streaming;
    return true;
  }

  return false;
}

int _streamablePrefixEnd(
  String text, {
  required int suffixBufferSize,
}) {
  if (text.length <= suffixBufferSize) {
    return 0;
  }

  final closingFence = _closingFence.firstMatch(text);
  if (closingFence != null) {
    return closingFence.start;
  }

  return text.length - suffixBufferSize;
}

Iterable<provider.LanguageModelStreamPart> _flushPendingTextBlock({
  required String id,
  required _TextBlock block,
  required ExtractJsonTransform transform,
}) sync* {
  yield* _flushTextBlock(id: id, block: block, transform: transform);
  block.buffer = '';
  block.phase = _TextPhase.streaming;
}

Iterable<provider.LanguageModelStreamPart> _flushTextBlock({
  required String id,
  required _TextBlock block,
  required ExtractJsonTransform transform,
}) sync* {
  if (block.phase == _TextPhase.prefix || block.phase == _TextPhase.buffering) {
    yield block.startEvent;
  }

  var remaining = block.buffer;
  if (block.phase == _TextPhase.buffering) {
    remaining = transform(remaining);
  } else if (block.prefixStripped) {
    remaining = _stripMarkdownCodeFenceSuffix(remaining);
  } else if (block.phase == _TextPhase.prefix) {
    remaining = transform(remaining);
  }

  if (remaining.isNotEmpty) {
    yield provider.TextDelta(
      id,
      remaining,
      providerMetadata: block.providerMetadata,
    );
  }
}

enum _TextPhase {
  prefix,
  streaming,
  buffering,
}

final class _TextBlock {
  _TextBlock({
    required this.startEvent,
    required this.phase,
  });

  final provider.TextStart startEvent;
  _TextPhase phase;
  String buffer = '';
  bool prefixStripped = false;
  provider.ProviderMetadata? providerMetadata;
  final pendingChunks = <provider.LanguageModelStreamPart>[];

  bool get hasPendingOutput =>
      phase == _TextPhase.prefix ||
      phase == _TextPhase.buffering ||
      buffer.isNotEmpty;

  void mergeMetadata(provider.ProviderMetadata? next) {
    providerMetadata = next ?? providerMetadata;
  }
}
