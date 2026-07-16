import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('TextStreamPart 值相等', () {
    test('TextStartPart 按 id 判等', () {
      expect(const TextStartPart('a'), equals(const TextStartPart('a')));
      expect(const TextStartPart('a'), isNot(equals(const TextStartPart('b'))));
      expect(
        const TextStartPart('a', providerMetadata: {
          'test': {'id': 'text-1'},
        }),
        equals(const TextStartPart('a', providerMetadata: {
          'test': {'id': 'text-1'},
        })),
      );
    });

    test('TextDeltaPart 按 id+delta 判等', () {
      expect(
        const TextDeltaPart('a', 'hi'),
        equals(const TextDeltaPart('a', 'hi')),
      );
      expect(
        const TextDeltaPart('a', 'hi'),
        isNot(equals(const TextDeltaPart('a', 'bye'))),
      );
      expect(
        const TextDeltaPart('a', 'hi', providerMetadata: {
          'test': {'signature': 'sig-1'},
        }),
        equals(const TextDeltaPart('a', 'hi', providerMetadata: {
          'test': {'signature': 'sig-1'},
        })),
      );
    });

    test('TextEndPart 按 id 判等', () {
      expect(const TextEndPart('a'), equals(const TextEndPart('a')));
      expect(
        const TextEndPart('a', providerMetadata: {
          'test': {'final': true},
        }),
        equals(const TextEndPart('a', providerMetadata: {
          'test': {'final': true},
        })),
      );
    });

    test('ReasoningStart/Delta/EndPart 按 id、delta 与 metadata 判等', () {
      const metadata = {
        'test': {'signature': 'sig-1'},
      };
      expect(
        const ReasoningStartPart('r1', providerMetadata: metadata),
        equals(const ReasoningStartPart('r1', providerMetadata: metadata)),
      );
      expect(
        const ReasoningDeltaPart(
          'r1',
          'thinking',
          providerMetadata: metadata,
        ),
        equals(const ReasoningDeltaPart(
          'r1',
          'thinking',
          providerMetadata: metadata,
        )),
      );
      expect(
        const ReasoningEndPart('r1', providerMetadata: metadata),
        equals(const ReasoningEndPart('r1', providerMetadata: metadata)),
      );
    });

    test('ToolCallStreamPart 包裹契约 ToolCall 判等', () {
      const call = provider.ToolCall(
        toolCallId: 't1',
        toolName: 'search',
        input: '{"q":"dart"}',
      );
      const other = provider.ToolCall(
        toolCallId: 't1',
        toolName: 'search',
        input: '{"q":"go"}',
      );
      expect(
        const ToolCallStreamPart(call),
        equals(const ToolCallStreamPart(call)),
      );
      expect(
        const ToolCallStreamPart(call),
        isNot(equals(ToolCallStreamPart(other))),
      );
    });

    test('ToolResultStreamPart 包裹契约 ToolResult 判等', () {
      const result = provider.ToolResult(
        toolCallId: 't1',
        toolName: 'search',
        result: 'ok',
      );
      expect(
        const ToolResultStreamPart(result),
        equals(const ToolResultStreamPart(result)),
      );
    });

    test('ToolApprovalRequest/ResponseStreamPart 包裹契约审批 part 判等', () {
      const request = provider.ToolApprovalRequest(
        approvalId: 'a1',
        toolCallId: 't1',
      );
      const response = provider.ToolApprovalResponsePart(
        approvalId: 'a1',
        approved: true,
      );
      expect(
        const ToolApprovalRequestStreamPart(request),
        equals(const ToolApprovalRequestStreamPart(request)),
      );
      expect(
        const ToolApprovalResponseStreamPart(response),
        equals(const ToolApprovalResponseStreamPart(response)),
      );
    });

    test('ToolInputStart/Delta/End 判等', () {
      expect(
        const ToolInputStartPart('t1', 'search'),
        equals(const ToolInputStartPart('t1', 'search')),
      );
      expect(
        const ToolInputDeltaPart('t1', '{"q":'),
        equals(const ToolInputDeltaPart('t1', '{"q":')),
      );
      expect(
        const ToolInputEndPart('t1'),
        equals(const ToolInputEndPart('t1')),
      );
    });

    test('StartStepPart 按 request+warnings 判等', () {
      expect(
        StartStepPart(warnings: const []),
        equals(StartStepPart(warnings: const [])),
      );
      expect(
        StartStepPart(
          request: const provider.RequestInfo(body: 'req'),
          warnings: const [],
        ),
        equals(StartStepPart(
          request: const provider.RequestInfo(body: 'req'),
          warnings: const [],
        )),
      );
    });

    test('StartStepPart 的 warnings 为不可变视图(缓冲重放的共享实例不被订阅者污染)', () {
      final part = StartStepPart(
        warnings: [const provider.UnsupportedWarning('topK')],
      );

      expect(() => part.warnings.clear(), throwsUnsupportedError);
    });

    test('FinishStepPart 按 usage+finishReason+response 判等', () {
      const usage = provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      );
      const finishReason = provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      );
      expect(
        const FinishStepPart(usage: usage, finishReason: finishReason),
        equals(const FinishStepPart(usage: usage, finishReason: finishReason)),
      );
    });

    test('StartPart 无字段恒等', () {
      expect(const StartPart(), equals(const StartPart()));
    });

    test('FinishPart 按 finishReason+totalUsage 判等', () {
      const usage = provider.LanguageModelUsage(
        inputTokens: provider.InputTokens(),
        outputTokens: provider.OutputTokens(),
      );
      const finishReason = provider.LanguageModelFinishReason(
        provider.FinishReasonType.stop,
      );
      expect(
        const FinishPart(finishReason: finishReason, totalUsage: usage),
        equals(const FinishPart(finishReason: finishReason, totalUsage: usage)),
      );
    });

    test('ErrorPart 按 error 判等,允许 null', () {
      expect(const ErrorPart('boom'), equals(const ErrorPart('boom')));
      expect(const ErrorPart(null), equals(const ErrorPart(null)));
    });

    test('AbortPart 按可空 reason 判等', () {
      expect(const AbortPart(), equals(const AbortPart()));
      expect(
        const AbortPart(reason: 'timeout'),
        equals(const AbortPart(reason: 'timeout')),
      );
    });

    test('RawStreamPart 按 rawValue 判等', () {
      expect(const RawStreamPart('x'), equals(const RawStreamPart('x')));
    });
  });

  group('sealed switch 穷尽性', () {
    test('每个成员都能被 switch 语句精确匹配且无 default', () {
      String describe(TextStreamPart part) => switch (part) {
            TextStartPart() => 'text-start',
            TextDeltaPart() => 'text-delta',
            TextEndPart() => 'text-end',
            ReasoningStartPart() => 'reasoning-start',
            ReasoningDeltaPart() => 'reasoning-delta',
            ReasoningEndPart() => 'reasoning-end',
            ToolCallStreamPart() => 'tool-call',
            ToolResultStreamPart() => 'tool-result',
            ToolApprovalRequestStreamPart() => 'tool-approval-request',
            ToolApprovalResponseStreamPart() => 'tool-approval-response',
            ToolInputStartPart() => 'tool-input-start',
            ToolInputDeltaPart() => 'tool-input-delta',
            ToolInputEndPart() => 'tool-input-end',
            StartStepPart() => 'start-step',
            FinishStepPart() => 'finish-step',
            StartPart() => 'start',
            FinishPart() => 'finish',
            ErrorPart() => 'error',
            AbortPart() => 'abort',
            RawStreamPart() => 'raw',
          };

      expect(describe(const TextStartPart('a')), 'text-start');
      expect(describe(const TextDeltaPart('a', 'x')), 'text-delta');
      expect(describe(const TextEndPart('a')), 'text-end');
      expect(describe(const ReasoningStartPart('r')), 'reasoning-start');
      expect(
        describe(const ReasoningDeltaPart('r', 'thinking')),
        'reasoning-delta',
      );
      expect(describe(const ReasoningEndPart('r')), 'reasoning-end');
      expect(
        describe(const ToolCallStreamPart(provider.ToolCall(
          toolCallId: 't1',
          toolName: 'search',
          input: '{}',
        ))),
        'tool-call',
      );
      expect(
        describe(const ToolResultStreamPart(provider.ToolResult(
          toolCallId: 't1',
          toolName: 'search',
          result: 'ok',
        ))),
        'tool-result',
      );
      expect(
        describe(const ToolApprovalRequestStreamPart(
          provider.ToolApprovalRequest(approvalId: 'a1', toolCallId: 't1'),
        )),
        'tool-approval-request',
      );
      expect(
        describe(const ToolApprovalResponseStreamPart(
          provider.ToolApprovalResponsePart(approvalId: 'a1', approved: true),
        )),
        'tool-approval-response',
      );
      expect(describe(const ToolInputStartPart('t1', 'search')),
          'tool-input-start');
      expect(describe(const ToolInputDeltaPart('t1', 'x')), 'tool-input-delta');
      expect(describe(const ToolInputEndPart('t1')), 'tool-input-end');
      expect(describe(StartStepPart(warnings: const [])), 'start-step');
      expect(
        describe(const FinishStepPart(
          usage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
          finishReason: provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop),
        )),
        'finish-step',
      );
      expect(describe(const StartPart()), 'start');
      expect(
        describe(const FinishPart(
          finishReason: provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop),
          totalUsage: provider.LanguageModelUsage(
            inputTokens: provider.InputTokens(),
            outputTokens: provider.OutputTokens(),
          ),
        )),
        'finish',
      );
      expect(describe(const ErrorPart('boom')), 'error');
      expect(describe(const AbortPart()), 'abort');
      expect(describe(const RawStreamPart('x')), 'raw');
    });
  });
}
