import 'package:pigcode_ai/src/middleware/wrap_language_model.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

import '../support/scripted_model.dart';

typedef _LanguageModelCallOptions = provider.LanguageModelCallOptions;
typedef _LanguageModelGenerateResult = provider.LanguageModelGenerateResult;
typedef _LanguageModelStreamResult = provider.LanguageModelStreamResult;

void main() {
  // Compatibility fixture (unit): P1-CORE-12
  const prompt = <provider.LanguageModelMessage>[
    provider.UserMessage([provider.TextPart('hi')]),
  ];

  ScriptedTurn textTurn(String text) {
    return ScriptedTurn(
      content: [provider.TextContent(text)],
      finishReason: const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      ),
      usage: const provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      ),
    );
  }

  group('wrapLanguageModel', () {
    test('reports v4 even when the wrapped model advertises an older version',
        () {
      final wrapped = wrapLanguageModel(
        _LegacyVersionLanguageModel(),
        const provider.LanguageModelMiddleware(),
      );

      expect(wrapped.specificationVersion, provider.languageModelSpecVersion);
    });

    test('transformParams changes temperature but preserves other fields',
        () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );

      final wrapped = wrapLanguageModel(
        scripted,
        provider.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              params.copyWith(temperature: 0.42),
        ),
      );

      const options = provider.LanguageModelCallOptions(
        prompt: prompt,
        temperature: 0.1,
        maxOutputTokens: 256,
        stopSequences: ['STOP'],
      );

      await wrapped.doGenerate(options);

      final seen = scripted.receivedCallOptions.single;
      expect(seen.temperature, 0.42);
      expect(seen.maxOutputTokens, 256);
      expect(seen.stopSequences, ['STOP']);
      expect(seen.prompt, same(prompt));
    });

    test('wrapGenerate intercepts and can short-circuit doGenerate', () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('from-model')],
      );

      final wrapped = wrapLanguageModel(
        scripted,
        provider.LanguageModelMiddleware(
          wrapGenerate: ({
            required provider.LanguageModelDoGenerate doGenerate,
            required provider.LanguageModelDoStream doStream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              provider.LanguageModelGenerateResult(
            content: const [provider.TextContent('from-middleware')],
            finishReason: const provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop,
            ),
            usage: const provider.LanguageModelUsage(
              inputTokens: provider.InputTokens(),
              outputTokens: provider.OutputTokens(),
            ),
            warnings: const [],
          ),
        ),
      );

      final result = await wrapped.doGenerate(
        const provider.LanguageModelCallOptions(prompt: prompt),
      );

      expect(
        (result.content.single as provider.TextContent).text,
        'from-middleware',
      );
      expect(scripted.callCount, 0);
    });

    test('override* hooks apply provider/modelId/supportedUrls', () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );

      final wrapped = wrapLanguageModel(
        scripted,
        provider.LanguageModelMiddleware(
          overrideProvider: (m) => 'wrapped-${m.provider}',
          overrideModelId: (m) => 'wrapped-${m.modelId}',
          overrideSupportedUrls: (m) async => {
            'image/*': [RegExp(r'^https://cdn\.example\.com/')],
          },
        ),
      );

      expect(wrapped.provider, 'wrapped-scripted');
      expect(wrapped.modelId, 'wrapped-m-1');
      final urls = await wrapped.supportedUrls;
      expect(urls.keys, contains('image/*'));
    });

    test('with no middleware hooks set, delegates provider/modelId as-is',
        () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );

      final wrapped =
          wrapLanguageModel(scripted, const provider.LanguageModelMiddleware());

      expect(wrapped.provider, 'scripted');
      expect(wrapped.modelId, 'm-1');
    });

    test('nested wrapLanguageModel applies both layers of transformParams',
        () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );

      final once = wrapLanguageModel(
        scripted,
        provider.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              params.copyWith(temperature: 0.5),
        ),
      );
      final twice = wrapLanguageModel(
        once,
        provider.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              params.copyWith(maxOutputTokens: 999),
        ),
      );

      await twice.doGenerate(
        const provider.LanguageModelCallOptions(prompt: prompt),
      );

      final seen = scripted.receivedCallOptions.single;
      expect(seen.temperature, 0.5);
      expect(seen.maxOutputTokens, 999);
    });

    test(
        'nested wrapLanguageModel: on a conflicting field, the inner '
        '(last-wrapped, closest-to-model) transformParams wins over the '
        'outer (first-wrapped) one — matches v7 order', () async {
      final scripted = ScriptedModel(
        provider: 'scripted',
        modelId: 'm-1',
        turns: [textTurn('ok')],
      );

      final inner = wrapLanguageModel(
        scripted,
        provider.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              params.copyWith(temperature: 0.5),
        ),
      );
      final outer = wrapLanguageModel(
        inner,
        provider.LanguageModelMiddleware(
          transformParams: ({
            required bool stream,
            required provider.LanguageModelCallOptions params,
            required provider.LanguageModel model,
          }) async =>
              params.copyWith(temperature: 0.9),
        ),
      );

      await outer.doGenerate(
        const provider.LanguageModelCallOptions(prompt: prompt),
      );

      // inner 是「最后包裹、离真实模型最近」的一层：它的 transformParams
      // 最后执行，故在 temperature 冲突时其值(0.5)覆盖 outer 的值(0.9),
      // 是真正送达模型的值。
      final seen = scripted.receivedCallOptions.single;
      expect(seen.temperature, 0.5);
    });
  });
}

final class _LegacyVersionLanguageModel implements provider.LanguageModel {
  @override
  String get specificationVersion => 'v3';

  @override
  String get provider => 'legacy';

  @override
  String get modelId => 'legacy-model';

  @override
  Map<String, List<RegExp>> get supportedUrls => const {};

  @override
  Future<_LanguageModelGenerateResult> doGenerate(
    _LanguageModelCallOptions options,
  ) {
    throw UnsupportedError('doGenerate not needed in specification test');
  }

  @override
  Future<_LanguageModelStreamResult> doStream(
    _LanguageModelCallOptions options,
  ) {
    throw UnsupportedError('doStream not needed in specification test');
  }
}
