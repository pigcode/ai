import 'dart:async';

import 'package:pigcode_ai/src/generate_text/text_stream_part.dart';
import 'package:pigcode_ai/src/text_stream/to_text_stream.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('toTextStream', () {
    test('keeps only text delta parts', () async {
      final result = await toTextStream(
        Stream<TextStreamPart>.fromIterable([
          const StartPart(),
          StartStepPart(warnings: const []),
          const TextStartPart('txt_1'),
          const TextDeltaPart('txt_1', 'Hello'),
          const TextDeltaPart('txt_1', ', world!'),
          const TextEndPart('txt_1'),
          FinishPart(
            finishReason: const provider.LanguageModelFinishReason(
              provider.FinishReasonType.stop,
            ),
            totalUsage: const provider.LanguageModelUsage(
              inputTokens: provider.InputTokens(),
              outputTokens: provider.OutputTokens(),
            ),
          ),
        ]),
      ).toList();

      expect(result, ['Hello', ', world!']);
    });

    test('ignores reasoning, tool, approval, raw, abort, and error parts',
        () async {
      final result = await toTextStream(
        Stream<TextStreamPart>.fromIterable([
          const ReasoningStartPart('rsn_1'),
          const ReasoningDeltaPart('rsn_1', 'thinking'),
          const ReasoningEndPart('rsn_1'),
          const ToolInputStartPart('call_1', 'lookup'),
          const ToolInputDeltaPart('call_1', '{"q"'),
          const ToolInputEndPart('call_1'),
          const ToolCallStreamPart(provider.ToolCall(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: '{"q":"dart"}',
          )),
          const ToolApprovalRequestStreamPart(provider.ToolApprovalRequest(
            approvalId: 'approval_1',
            toolCallId: 'call_1',
          )),
          const ToolApprovalResponseStreamPart(
            provider.ToolApprovalResponsePart(
              approvalId: 'approval_1',
              approved: true,
            ),
          ),
          const ToolResultStreamPart(provider.ToolResult(
            toolCallId: 'call_1',
            toolName: 'lookup',
            result: 'ok',
          )),
          const RawStreamPart({'raw': true}),
          const AbortPart(reason: 'cancelled'),
          ErrorPart(StateError('secret')),
        ]),
      ).toList();

      expect(result, isEmpty);
    });

    test('propagates source stream errors', () async {
      final controller = StreamController<TextStreamPart>();
      final error = StateError('boom');
      final expectation = expectLater(
        toTextStream(controller.stream).toList(),
        throwsA(same(error)),
      );

      controller
        ..add(const TextDeltaPart('txt_1', 'before'))
        ..addError(error)
        ..add(const TextDeltaPart('txt_1', 'after'));
      await controller.close();
      await expectation;
    });
  });
}
