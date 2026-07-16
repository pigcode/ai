import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'text_stream_part.dart';

/// 从缓冲文本中检测下一段可发出的 chunk。
///
/// 返回 `null` 表示缓冲内容尚不足以形成稳定 chunk。返回值必须非空,
/// 且必须是输入 [buffer] 的前缀。
typedef ChunkDetector = String? Function(String buffer);

/// `smoothStream` 的文本切分策略。
sealed class SmoothStreamChunking {
  const SmoothStreamChunking._();

  /// 尽量按完整单词和其后的空白输出。
  static const SmoothStreamChunking word = _WordSmoothStreamChunking();

  /// 按换行输出。
  static const SmoothStreamChunking line = _LineSmoothStreamChunking();

  /// 使用正则表达式检测下一段 chunk。
  ///
  /// 如果正则不从缓冲开头匹配,输出会包含匹配前的文本以及匹配本身,
  /// 与上游 `smoothStream` 的 RegExp chunking 语义一致。
  static SmoothStreamChunking regExp(RegExp pattern) {
    return _RegExpSmoothStreamChunking(pattern);
  }

  /// 使用自定义回调检测下一段 chunk。
  static SmoothStreamChunking custom(ChunkDetector detector) {
    return _CustomSmoothStreamChunking(detector);
  }
}

final class _WordSmoothStreamChunking extends SmoothStreamChunking {
  const _WordSmoothStreamChunking() : super._();
}

final class _LineSmoothStreamChunking extends SmoothStreamChunking {
  const _LineSmoothStreamChunking() : super._();
}

final class _RegExpSmoothStreamChunking extends SmoothStreamChunking {
  const _RegExpSmoothStreamChunking(this.pattern) : super._();

  final RegExp pattern;
}

final class _CustomSmoothStreamChunking extends SmoothStreamChunking {
  const _CustomSmoothStreamChunking(this.detector) : super._();

  final ChunkDetector detector;
}

/// 平滑 `TextDeltaPart` 与 `ReasoningDeltaPart` 输出的流转换器。
///
/// 只处理文本/推理 delta;遇到其他 part 时会先输出当前缓冲,再原样透传该
/// part。[delay] 为 `null` 时不等待,便于测试或需要最快转发的场景。
StreamTransformer<TextStreamPart, TextStreamPart> smoothStream({
  Duration? delay = const Duration(milliseconds: 10),
  SmoothStreamChunking chunking = SmoothStreamChunking.word,
}) {
  final detectChunk = _chunkDetectorFor(chunking);

  return StreamTransformer<TextStreamPart, TextStreamPart>.fromBind(
    (stream) async* {
      final buffer = StringBuffer();
      String? id;
      _SmoothDeltaKind? kind;
      provider.ProviderMetadata? providerMetadata;

      TextStreamPart? flushBuffer() {
        final currentId = id;
        final currentKind = kind;
        if (currentId == null || currentKind == null || buffer.isEmpty) {
          return null;
        }
        final text = buffer.toString();
        final part = switch (currentKind) {
          _SmoothDeltaKind.text => TextDeltaPart(
              currentId,
              text,
              providerMetadata: providerMetadata,
            ),
          _SmoothDeltaKind.reasoning => ReasoningDeltaPart(
              currentId,
              text,
              providerMetadata: providerMetadata,
            ),
        };
        buffer.clear();
        providerMetadata = null;
        return part;
      }

      Future<void> maybeDelay() async {
        final currentDelay = delay;
        if (currentDelay != null && currentDelay > Duration.zero) {
          await Future<void>.delayed(currentDelay);
        }
      }

      await for (final part in stream) {
        final deltaKind = switch (part) {
          TextDeltaPart() => _SmoothDeltaKind.text,
          ReasoningDeltaPart() => _SmoothDeltaKind.reasoning,
          _ => null,
        };

        if (deltaKind == null) {
          final flushed = flushBuffer();
          if (flushed != null) {
            yield flushed;
          }
          yield part;
          continue;
        }

        final partId = switch (part) {
          TextDeltaPart(:final id) => id,
          ReasoningDeltaPart(:final id) => id,
          _ => throw StateError('unreachable'),
        };
        final delta = switch (part) {
          TextDeltaPart(:final delta) => delta,
          ReasoningDeltaPart(:final delta) => delta,
          _ => throw StateError('unreachable'),
        };
        final metadata = switch (part) {
          TextDeltaPart(:final providerMetadata) => providerMetadata,
          ReasoningDeltaPart(:final providerMetadata) => providerMetadata,
          _ => throw StateError('unreachable'),
        };

        if (id != null && (id != partId || kind != deltaKind)) {
          final flushed = flushBuffer();
          if (flushed != null) {
            yield flushed;
          }
        }

        id = partId;
        kind = deltaKind;
        buffer.write(delta);
        if (metadata != null) {
          providerMetadata = metadata;
        }

        while (true) {
          final text = buffer.toString();
          final match = detectChunk(text);
          if (match == null) {
            break;
          }
          if (match.isEmpty) {
            throw ArgumentError.value(
              match,
              'chunking',
              'must return a non-empty string',
            );
          }
          if (!text.startsWith(match)) {
            throw ArgumentError.value(
              match,
              'chunking',
              'must return a prefix of the buffered text',
            );
          }

          yield switch (deltaKind) {
            _SmoothDeltaKind.text => TextDeltaPart(
                partId,
                match,
                providerMetadata: providerMetadata,
              ),
            _SmoothDeltaKind.reasoning => ReasoningDeltaPart(
                partId,
                match,
                providerMetadata: providerMetadata,
              ),
          };
          buffer
            ..clear()
            ..write(text.substring(match.length));
          if (buffer.isEmpty) {
            providerMetadata = null;
          }
          await maybeDelay();
        }
      }

      final flushed = flushBuffer();
      if (flushed != null) {
        yield flushed;
      }
    },
  );
}

enum _SmoothDeltaKind { text, reasoning }

ChunkDetector _chunkDetectorFor(SmoothStreamChunking chunking) {
  return switch (chunking) {
    _WordSmoothStreamChunking() => _wordChunkDetector,
    _LineSmoothStreamChunking() => _lineChunkDetector,
    _RegExpSmoothStreamChunking(:final pattern) => (buffer) {
        final match = pattern.firstMatch(buffer);
        if (match == null) {
          return null;
        }
        return buffer.substring(0, match.end);
      },
    _CustomSmoothStreamChunking(:final detector) => detector,
  };
}

String? _wordChunkDetector(String buffer) {
  final match = RegExp(r'\S+\s+', multiLine: true).firstMatch(buffer);
  if (match == null) {
    return null;
  }
  return buffer.substring(0, match.end);
}

String? _lineChunkDetector(String buffer) {
  final match = RegExp(r'\n+', multiLine: true).firstMatch(buffer);
  if (match == null) {
    return null;
  }
  return buffer.substring(0, match.end);
}
