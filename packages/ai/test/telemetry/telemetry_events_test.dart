import 'package:pigcode_ai/src/telemetry/telemetry_events.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('LanguageModelCallStartEvent', () {
    test('holds fields and is value-equal', () {
      final a = LanguageModelCallStartEvent(
        callId: 'call_1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        messages: const [],
      );
      final b = LanguageModelCallStartEvent(
        callId: 'call_1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        messages: const [],
      );
      expect(a.callId, 'call_1');
      expect(a.providerId, 'openai');
      expect(a.modelId, 'gpt-4o');
      expect(a.stepNumber, 0);
      expect(a.messages, isEmpty);
      expect(a, equals(b));
    });
  });

  group('LanguageModelCallEndEvent', () {
    test('holds fields and is value-equal', () {
      final a = LanguageModelCallEndEvent(
        callId: 'call_1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        content: const [provider.TextContent('hi')],
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        warnings: const [],
        response: const provider.ResponseInfo(id: 'resp_1'),
        responseTime: const Duration(milliseconds: 12),
      );
      final b = LanguageModelCallEndEvent(
        callId: 'call_1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        content: const [provider.TextContent('hi')],
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        warnings: const [],
        response: const provider.ResponseInfo(id: 'resp_1'),
        responseTime: const Duration(milliseconds: 12),
      );
      expect(a.response?.id, 'resp_1');
      expect(a.responseTime, const Duration(milliseconds: 12));
      expect(a.content, hasLength(1));
      expect(a, equals(b));
    });

    test('content list is unmodifiable', () {
      final event = LanguageModelCallEndEvent(
        callId: 'call_1',
        providerId: 'openai',
        modelId: 'gpt-4o',
        stepNumber: 0,
        content: [const provider.TextContent('hi')],
        usage: const provider.LanguageModelUsage(
          inputTokens: provider.InputTokens(),
          outputTokens: provider.OutputTokens(),
        ),
        finishReason: const provider.LanguageModelFinishReason(
          provider.FinishReasonType.stop,
        ),
        warnings: [],
        response: null,
        responseTime: Duration.zero,
      );
      expect(
        () => event.content.add(const provider.TextContent('x')),
        throwsUnsupportedError,
      );
      expect(() => event.warnings.add(const provider.OtherWarning('x')),
          throwsUnsupportedError);
    });
  });

  group('ToolExecutionStartEvent', () {
    test('holds fields (no ToolCall) and is value-equal', () {
      const a = ToolExecutionStartEvent(
        callId: 'exec_1',
        toolCallId: 'tc_1',
        toolName: 'lookup',
        input: {'q': 'dart'},
        toolContext: {'region': 'us'},
      );
      const b = ToolExecutionStartEvent(
        callId: 'exec_1',
        toolCallId: 'tc_1',
        toolName: 'lookup',
        input: {'q': 'dart'},
        toolContext: {'region': 'us'},
      );
      expect(a.toolCallId, 'tc_1');
      expect(a.toolName, 'lookup');
      expect(a.input, {'q': 'dart'});
      expect(a.toolContext, {'region': 'us'});
      expect(a, equals(b));
    });
  });

  group('ToolExecutionEndEvent', () {
    test('success variant carries output', () {
      const event = ToolExecutionEndSuccess(
        callId: 'exec_1',
        toolCallId: 'tc_1',
        toolName: 'lookup',
        output: {'ok': true},
        toolExecutionMs: 5,
      );
      expect(event, isA<ToolExecutionEndEvent>());
      expect(event.output, {'ok': true});
      expect(event.toolExecutionMs, 5);
      expect(
        event,
        equals(const ToolExecutionEndSuccess(
          callId: 'exec_1',
          toolCallId: 'tc_1',
          toolName: 'lookup',
          output: {'ok': true},
          toolExecutionMs: 5,
        )),
      );
    });

    test('error variant carries error', () {
      const event = ToolExecutionEndError(
        callId: 'exec_1',
        toolCallId: 'tc_1',
        toolName: 'lookup',
        error: 'boom',
        toolExecutionMs: 7,
      );
      expect(event, isA<ToolExecutionEndEvent>());
      expect(event.error, 'boom');
      expect(event.toolExecutionMs, 7);
      expect(
          event,
          isNot(equals(const ToolExecutionEndSuccess(
            callId: 'exec_1',
            toolCallId: 'tc_1',
            toolName: 'lookup',
            output: null,
            toolExecutionMs: 7,
          ))));
    });
  });
}
