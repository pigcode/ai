import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:test/test.dart';

void main() {
  group('getOpenAiLanguageModelCapabilities', () {
    test('gpt-4o: not reasoning, system mode, no flex, priority processing',
        () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-4o');

      expect(capabilities.isReasoningModel, isFalse);
      expect(capabilities.systemMessageMode, SystemMessageMode.system);
      expect(capabilities.supportsFlexProcessing, isFalse);
      expect(capabilities.supportsPriorityProcessing, isTrue);
      expect(capabilities.supportsNonReasoningParameters, isFalse);
    });

    test('o1: reasoning model, developer mode, no flex/priority', () {
      final capabilities = getOpenAiLanguageModelCapabilities('o1');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.systemMessageMode, SystemMessageMode.developer);
      expect(capabilities.supportsFlexProcessing, isFalse);
      expect(capabilities.supportsPriorityProcessing, isFalse);
      expect(capabilities.supportsNonReasoningParameters, isFalse);
    });

    test('o1-mini: prefix "o1" still counts as reasoning', () {
      final capabilities = getOpenAiLanguageModelCapabilities('o1-mini');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.systemMessageMode, SystemMessageMode.developer);
    });

    test('o3: reasoning, flex + priority processing supported', () {
      final capabilities = getOpenAiLanguageModelCapabilities('o3');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.systemMessageMode, SystemMessageMode.developer);
      expect(capabilities.supportsFlexProcessing, isTrue);
      expect(capabilities.supportsPriorityProcessing, isTrue);
    });

    test('o4-mini: reasoning, flex + priority processing supported', () {
      final capabilities = getOpenAiLanguageModelCapabilities('o4-mini');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.systemMessageMode, SystemMessageMode.developer);
      expect(capabilities.supportsFlexProcessing, isTrue);
      expect(capabilities.supportsPriorityProcessing, isTrue);
    });

    test('gpt-5: reasoning, flex + priority processing supported', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.systemMessageMode, SystemMessageMode.developer);
      expect(capabilities.supportsFlexProcessing, isTrue);
      expect(capabilities.supportsPriorityProcessing, isTrue);
    });

    test('gpt-5-chat: excluded from reasoning despite gpt-5 prefix', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5-chat');

      expect(capabilities.isReasoningModel, isFalse);
      expect(capabilities.systemMessageMode, SystemMessageMode.system);
      expect(capabilities.supportsFlexProcessing, isFalse);
      // gpt-4* 前缀不匹配、gpt-5* 分支因 gpt-5-chat 被排除,o3/o4-mini 均不
      // 匹配 —— priority processing 应为 false。
      expect(capabilities.supportsPriorityProcessing, isFalse);
    });

    test('gpt-5-nano: reasoning true, priority processing excluded', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5-nano');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.supportsFlexProcessing, isTrue);
      expect(capabilities.supportsPriorityProcessing, isFalse);
    });

    test('gpt-5.4-nano: priority processing excluded by dedicated prefix', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5.4-nano');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.supportsPriorityProcessing, isFalse);
      // gpt-5.4* 前缀命中 supportsNonReasoningParameters。
      expect(capabilities.supportsNonReasoningParameters, isTrue);
    });

    test('gpt-5.1: supports non-reasoning parameters', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5.1');

      expect(capabilities.isReasoningModel, isTrue);
      expect(capabilities.supportsNonReasoningParameters, isTrue);
    });

    test('gpt-5.5-mini: gpt-5.5 prefix supports non-reasoning parameters', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-5.5-mini');

      expect(capabilities.supportsNonReasoningParameters, isTrue);
    });

    test('gpt-3.5-turbo: no capability flags set', () {
      final capabilities = getOpenAiLanguageModelCapabilities('gpt-3.5-turbo');

      expect(capabilities.isReasoningModel, isFalse);
      expect(capabilities.systemMessageMode, SystemMessageMode.system);
      expect(capabilities.supportsFlexProcessing, isFalse);
      expect(capabilities.supportsPriorityProcessing, isFalse);
      expect(capabilities.supportsNonReasoningParameters, isFalse);
    });

    test('unknown/custom modelId: falls back to all-false, system mode', () {
      final capabilities =
          getOpenAiLanguageModelCapabilities('my-custom-finetune-v1');

      expect(capabilities.isReasoningModel, isFalse);
      expect(capabilities.systemMessageMode, SystemMessageMode.system);
      expect(capabilities.supportsFlexProcessing, isFalse);
      expect(capabilities.supportsPriorityProcessing, isFalse);
      expect(capabilities.supportsNonReasoningParameters, isFalse);
    });
  });
}
