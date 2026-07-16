import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:test/test.dart';

void main() {
  group('StepResult', () {
    final usage = const provider.LanguageModelUsage(
      inputTokens: provider.InputTokens(total: 10),
      outputTokens: provider.OutputTokens(total: 5),
    );
    final finishReason = const provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop);
    final performance = StepResultPerformance.empty();

    test('text concatenates all TextContent items in order', () {
      final step = StepResult(
        content: const [
          provider.TextContent('Hello, '),
          provider.ToolCall(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: '{}',
          ),
          provider.TextContent('world!'),
        ],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(step.text, 'Hello, world!');
    });

    test('text is empty when content has no TextContent items', () {
      final step = StepResult(
        content: const [
          provider.ToolCall(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: '{}',
          ),
        ],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(step.text, '');
    });

    test('toolCalls filters ToolCall items out of content', () {
      const call1 = provider.ToolCall(
        toolCallId: 'call_1',
        toolName: 'lookup',
        input: '{"q":"a"}',
      );
      const call2 = provider.ToolCall(
        toolCallId: 'call_2',
        toolName: 'lookup',
        input: '{"q":"b"}',
      );
      final step = StepResult(
        content: const [
          provider.TextContent('thinking...'),
          call1,
          call2,
        ],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(step.toolCalls, [call1, call2]);
    });

    test('toolResults returns the executed tool results', () {
      const result1 = provider.ToolResult(
        toolCallId: 'call_1',
        toolName: 'lookup',
        result: 'a',
      );
      final step = StepResult(
        content: const [],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [result1],
        performance: performance,
      );

      expect(step.toolResults, [result1]);
    });

    test('derived content getters filter reasoning, files, and sources', () {
      const reasoning = provider.ReasoningContent('think');
      const reasoningFile = provider.ReasoningFileContent(
        data: provider.FileDataBase64('eyJrIjoidiJ9'),
        mediaType: 'application/json',
      );
      const file = provider.FileContent(
        data: provider.FileDataBase64('AAA='),
        mediaType: 'image/png',
      );
      const source = provider.SourceContent.url(
        id: 'source-1',
        url: 'https://example.com/a',
        title: 'Example',
      );
      final step = StepResult(
        content: const [
          reasoning,
          provider.TextContent('answer'),
          reasoningFile,
          file,
          source,
        ],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(step.reasoning, const [reasoning, reasoningFile]);
      expect(step.reasoningText, 'think');
      expect(step.files, const [file]);
      expect(step.sources, const [source]);
    });

    test('reasoningText is null when there is no reasoning text', () {
      final step = StepResult(
        content: const [
          provider.ReasoningFileContent(
            data: provider.FileDataBase64('eyJrIjoidiJ9'),
            mediaType: 'application/json',
          ),
          provider.TextContent('answer'),
        ],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(step.reasoningText, isNull);
    });

    test('equality compares all fields including executedToolResults', () {
      const call = provider.ToolCall(
        toolCallId: 'call_1',
        toolName: 'lookup',
        input: '{}',
      );
      const result = provider.ToolResult(
        toolCallId: 'call_1',
        toolName: 'lookup',
        result: 'ok',
      );

      final a = StepResult(
        content: const [provider.TextContent('hi'), call],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [result],
        performance: performance,
      );
      final b = StepResult(
        content: const [provider.TextContent('hi'), call],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [result],
        performance: performance,
      );
      final c = StepResult(
        content: const [provider.TextContent('bye'), call],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [result],
        performance: performance,
      );

      expect(a, equals(b));
      expect(a == c, isFalse);
    });

    test('providerMetadata defaults to null and factors into equality', () {
      final withMetadata = StepResult(
        content: const [provider.TextContent('hi')],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        providerMetadata: const {
          'anthropic': {
            'container': {'id': 'container-1'},
          },
        },
        performance: performance,
      );
      final sameMetadata = StepResult(
        content: const [provider.TextContent('hi')],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        providerMetadata: const {
          'anthropic': {
            'container': {'id': 'container-1'},
          },
        },
        performance: performance,
      );
      final differentMetadata = StepResult(
        content: const [provider.TextContent('hi')],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        providerMetadata: const {
          'anthropic': {
            'container': {'id': 'container-2'},
          },
        },
        performance: performance,
      );
      final withoutMetadata = StepResult(
        content: const [provider.TextContent('hi')],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: const [],
        performance: performance,
      );

      expect(withoutMetadata.providerMetadata, isNull);
      expect(withMetadata, equals(sameMetadata));
      // metadata 不同的两步不相等(漏加 props 会误判相等)。
      expect(withMetadata, isNot(equals(differentMetadata)));
      expect(withMetadata, isNot(equals(withoutMetadata)));
    });

    test(
        'list fields are frozen as unmodifiable views (immutable value object)',
        () {
      // 传入可变列表:若构造未固化,.clear() 会成功;固化后应抛出。
      final step = StepResult(
        content: [const provider.TextContent('x')],
        finishReason: finishReason,
        usage: usage,
        response: null,
        executedToolResults: [
          const provider.ToolResult(
            toolCallId: 'c1',
            toolName: 'echo',
            result: 'r',
          ),
        ],
        toolResultOutputs: [const provider.ToolResultText('r')],
        performance: performance,
      );

      expect(() => step.content.clear(), throwsUnsupportedError);
      expect(() => step.executedToolResults.clear(), throwsUnsupportedError);
      expect(() => step.toolResultOutputs.clear(), throwsUnsupportedError);
    });
  });
}
