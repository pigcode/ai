import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // 复用的最小 prompt:一条 system 消息。
  final prompt = <LanguageModelMessage>[const SystemMessage('sys')];

  LanguageModelCallOptions makeOptions({CancellationSignal? cancellation}) {
    return LanguageModelCallOptions(
      prompt: prompt,
      maxOutputTokens: 100,
      temperature: 0.7,
      topP: 0.9,
      topK: 40,
      presencePenalty: 0.1,
      frequencyPenalty: 0.2,
      seed: 42,
      stopSequences: const ['STOP'],
      responseFormat: const ResponseFormatText(),
      tools: const <LanguageModelTool>[],
      toolChoice: const ToolChoiceAuto(),
      reasoning: ReasoningEffort.medium,
      includeRawChunks: true,
      cancellation: cancellation,
      headers: const {'x-a': '1'},
      providerOptions: const {
        'openai': {'store': true},
      },
    );
  }

  group('LanguageModelCallOptions.copyWith', () {
    test('no args equals original by value fields', () {
      final original = makeOptions();
      final copy = original.copyWith();
      expect(copy, equals(original));
    });

    test('overriding temperature keeps every other field', () {
      final original = makeOptions();
      final copy = original.copyWith(temperature: 0.1);

      expect(copy.temperature, 0.1);
      expect(copy.prompt, same(original.prompt));
      expect(copy.maxOutputTokens, original.maxOutputTokens);
      expect(copy.topP, original.topP);
      expect(copy.topK, original.topK);
      expect(copy.presencePenalty, original.presencePenalty);
      expect(copy.frequencyPenalty, original.frequencyPenalty);
      expect(copy.seed, original.seed);
      expect(copy.stopSequences, original.stopSequences);
      expect(copy.responseFormat, original.responseFormat);
      expect(copy.tools, original.tools);
      expect(copy.toolChoice, original.toolChoice);
      expect(copy.reasoning, original.reasoning);
      expect(copy.includeRawChunks, original.includeRawChunks);
      expect(copy.headers, original.headers);
      expect(copy.providerOptions, original.providerOptions);
    });

    test('can reset a nullable field (seed) to null via sentinel', () {
      final original = makeOptions();
      expect(original.seed, 42);

      final copy = original.copyWith(seed: null);
      expect(copy.seed, isNull);
      // 其余可空字段未传时保留原值,不被 null 覆盖。
      expect(copy.temperature, original.temperature);
      expect(copy.maxOutputTokens, original.maxOutputTokens);
    });

    test('can reset an object nullable field (responseFormat) to null', () {
      final original = makeOptions();
      expect(original.responseFormat, isNotNull);

      final copy = original.copyWith(responseFormat: null);
      expect(copy.responseFormat, isNull);
      expect(copy.tools, original.tools);
    });

    test('preserves the cancellation signal through copyWith', () {
      // cancellation 不入值相等,相等测试无法守护它;这里显式验证 copyWith
      // 逐字段透传时(无参、以及改其它字段)取消信号身份被保留,防未来回归。
      final signal = CancellationController().signal;
      final original = makeOptions(cancellation: signal);
      expect(original.cancellation, same(signal));

      expect(original.copyWith().cancellation, same(signal));
      expect(original.copyWith(temperature: 0.1).cancellation, same(signal));
    });
  });

  group('LanguageModelCallOptions equality', () {
    test('ignores cancellation identity', () {
      final controllerA = CancellationController();
      final controllerB = CancellationController();

      final withA = makeOptions(cancellation: controllerA.signal);
      final withB = makeOptions(cancellation: controllerB.signal);
      final withNone = makeOptions();

      // cancellation 不入 props:仅按值字段判等。
      expect(withA, equals(withB));
      expect(withA, equals(withNone));
      expect(withA.hashCode, equals(withB.hashCode));
    });

    test('differs when a value field differs', () {
      final a = makeOptions();
      final b = a.copyWith(temperature: 0.999);
      expect(a, isNot(equals(b)));
    });
  });
}
