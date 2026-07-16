import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 闭环 TDD 用的最小 [LanguageModel]:把最后一条 user 文本回吐成
/// 单个 [TextContent],并以 stop 收尾。
///
/// 仅供测试,不进 lib —— 契约包保持纯契约。
final class EchoModel implements LanguageModel {
  const EchoModel({this.provider = 'echo', this.modelId = 'echo-1'});

  @override
  String get specificationVersion => 'v4';

  @override
  final String provider;

  @override
  final String modelId;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  /// 取最后一条 [UserMessage] 里所有 [TextPart] 文本拼接;无则空串。
  String _lastUserText(LanguageModelPrompt prompt) {
    for (final message in prompt.reversed) {
      if (message is UserMessage) {
        return message.content
            .whereType<TextPart>()
            .map((part) => part.text)
            .join();
      }
    }
    return '';
  }

  LanguageModelUsage _usage(String text) => LanguageModelUsage(
        inputTokens: const InputTokens(total: 0),
        outputTokens: OutputTokens(total: text.length, text: text.length),
      );

  LanguageModelFinishReason get _stop =>
      const LanguageModelFinishReason(FinishReasonType.stop);

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    final text = _lastUserText(options.prompt);
    return LanguageModelGenerateResult(
      content: [TextContent(text)],
      finishReason: _stop,
      usage: _usage(text),
      warnings: const [],
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) async {
    final text = _lastUserText(options.prompt);
    return LanguageModelStreamResult(stream: _emit(text));
  }

  Stream<LanguageModelStreamPart> _emit(String text) async* {
    const id = 'text-0';
    yield const StreamStart([]);
    yield const TextStart(id);
    yield TextDelta(id, text);
    yield const TextEnd(id);
    yield FinishPart(usage: _usage(text), finishReason: _stop);
  }
}
