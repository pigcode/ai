import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart';

final class ScriptedLanguageModel implements LanguageModel {
  ScriptedLanguageModel(this.outputs);

  final List<String> outputs;
  var _index = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'scripted';

  @override
  String get modelId => 'task-11-scripted';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async {
    if (_index >= outputs.length) throw StateError('Script exhausted.');
    return LanguageModelGenerateResult(
      content: <LanguageModelContent>[TextContent(outputs[_index++])],
      finishReason: const LanguageModelFinishReason(FinishReasonType.stop),
      usage: const LanguageModelUsage(
        inputTokens: InputTokens(total: 1),
        outputTokens: OutputTokens(total: 1),
      ),
      warnings: const <Warning>[],
    );
  }

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) =>
      throw UnsupportedError('This Task 11 fixture exercises generate().');
}
