import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:test/test.dart';

/// 断言一组能力字段全值,减少逐字段重复。
void expectCapabilities(
  String modelId, {
  required int maxOutputTokens,
  required bool supportsStructuredOutput,
  required bool supportsAdaptiveThinking,
  required bool rejectsSamplingParameters,
  required bool supportsXhighEffort,
  required bool isKnownModel,
}) {
  final capabilities = getAnthropicModelCapabilities(modelId);
  expect(
    capabilities.maxOutputTokens,
    maxOutputTokens,
    reason: '$modelId maxOutputTokens',
  );
  expect(
    capabilities.supportsStructuredOutput,
    supportsStructuredOutput,
    reason: '$modelId supportsStructuredOutput',
  );
  expect(
    capabilities.supportsAdaptiveThinking,
    supportsAdaptiveThinking,
    reason: '$modelId supportsAdaptiveThinking',
  );
  expect(
    capabilities.rejectsSamplingParameters,
    rejectsSamplingParameters,
    reason: '$modelId rejectsSamplingParameters',
  );
  expect(
    capabilities.supportsXhighEffort,
    supportsXhighEffort,
    reason: '$modelId supportsXhighEffort',
  );
  expect(
    capabilities.isKnownModel,
    isKnownModel,
    reason: '$modelId isKnownModel',
  );
}

void main() {
  // Compatibility fixture (unit): P1-ANTHROPIC-01
  // Compatibility fixture (unit): P1-ANTHROPIC-07
  group('getAnthropicModelCapabilities', () {
    test('128k adaptive tier: opus-4-8 / opus-4-7 / fable-5 / sonnet-5', () {
      for (final modelId in <String>[
        'claude-opus-4-8',
        'claude-opus-4-7',
        'claude-fable-5',
        'claude-sonnet-5',
      ]) {
        expectCapabilities(
          modelId,
          maxOutputTokens: 128000,
          supportsStructuredOutput: true,
          supportsAdaptiveThinking: true,
          rejectsSamplingParameters: true,
          supportsXhighEffort: true,
          isKnownModel: true,
        );
      }
    });

    test('128k adaptive tier without sampling rejection: sonnet-4-6 / opus-4-6',
        () {
      for (final modelId in <String>['claude-sonnet-4-6', 'claude-opus-4-6']) {
        expectCapabilities(
          modelId,
          maxOutputTokens: 128000,
          supportsStructuredOutput: true,
          supportsAdaptiveThinking: true,
          rejectsSamplingParameters: false,
          supportsXhighEffort: false,
          isKnownModel: true,
        );
      }
    });

    test('64k structured tier: sonnet-4-5 / opus-4-5 / haiku-4-5', () {
      for (final modelId in <String>[
        'claude-sonnet-4-5',
        'claude-opus-4-5',
        'claude-haiku-4-5',
      ]) {
        expectCapabilities(
          modelId,
          maxOutputTokens: 64000,
          supportsStructuredOutput: true,
          supportsAdaptiveThinking: false,
          rejectsSamplingParameters: false,
          supportsXhighEffort: false,
          isKnownModel: true,
        );
      }
    });

    test('32k structured tier: opus-4-1', () {
      expectCapabilities(
        'claude-opus-4-1',
        maxOutputTokens: 32000,
        supportsStructuredOutput: true,
        supportsAdaptiveThinking: false,
        rejectsSamplingParameters: false,
        supportsXhighEffort: false,
        isKnownModel: true,
      );
    });

    test('64k legacy tier: claude-sonnet-4- without structured output', () {
      expectCapabilities(
        'claude-sonnet-4-20250514',
        maxOutputTokens: 64000,
        supportsStructuredOutput: false,
        supportsAdaptiveThinking: false,
        rejectsSamplingParameters: false,
        supportsXhighEffort: false,
        isKnownModel: true,
      );
    });

    test('32k legacy tier: claude-opus-4- without structured output', () {
      expectCapabilities(
        'claude-opus-4-20250514',
        maxOutputTokens: 32000,
        supportsStructuredOutput: false,
        supportsAdaptiveThinking: false,
        rejectsSamplingParameters: false,
        supportsXhighEffort: false,
        isKnownModel: true,
      );
    });

    test('4k tier: claude-3-haiku', () {
      expectCapabilities(
        'claude-3-haiku-20240307',
        maxOutputTokens: 4096,
        supportsStructuredOutput: false,
        supportsAdaptiveThinking: false,
        rejectsSamplingParameters: false,
        supportsXhighEffort: false,
        isKnownModel: true,
      );
    });

    test('fallback tier: unknown models get 4096 and isKnownModel=false', () {
      for (final modelId in <String>['gpt-4o', 'some-unknown-model']) {
        expectCapabilities(
          modelId,
          maxOutputTokens: 4096,
          supportsStructuredOutput: false,
          supportsAdaptiveThinking: false,
          rejectsSamplingParameters: false,
          supportsXhighEffort: false,
          isKnownModel: false,
        );
      }
    });

    test('branch order: claude-sonnet-4-6 hits 128k tier, not claude-sonnet-4-',
        () {
      expect(
        getAnthropicModelCapabilities('claude-sonnet-4-6').maxOutputTokens,
        128000,
      );
    });

    test(
        'branch order: claude-sonnet-4-5-20250929 hits 64k structured tier '
        'before claude-sonnet-4-', () {
      final capabilities =
          getAnthropicModelCapabilities('claude-sonnet-4-5-20250929');
      expect(capabilities.maxOutputTokens, 64000);
      expect(capabilities.supportsStructuredOutput, isTrue);
    });

    test('contains semantics: bedrock-style id matches mid-string', () {
      final capabilities =
          getAnthropicModelCapabilities('anthropic.claude-sonnet-4-5-v1:0');
      expect(capabilities.maxOutputTokens, 64000);
      expect(capabilities.supportsStructuredOutput, isTrue);
      expect(capabilities.isKnownModel, isTrue);
    });
  });

  group('isAnthropicModel', () {
    test('known model ids are Anthropic models', () {
      expect(isAnthropicModel('claude-sonnet-4-5'), isTrue);
      expect(isAnthropicModel('anthropic.claude-sonnet-4-5-v1:0'), isTrue);
    });

    test('unknown claude- prefixed ids are still Anthropic models', () {
      expect(isAnthropicModel('claude-brand-new'), isTrue);
    });

    test('non-claude unknown ids are not Anthropic models', () {
      expect(isAnthropicModel('some-unknown-model'), isFalse);
      expect(isAnthropicModel('gpt-4o'), isFalse);
    });
  });
}
