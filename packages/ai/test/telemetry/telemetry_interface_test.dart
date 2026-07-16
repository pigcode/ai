import 'dart:async';

import 'package:pigcode_ai/src/generate_text/lifecycle_events.dart';
import 'package:pigcode_ai/src/generate_text/step_result.dart';
import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_events.dart';
import 'package:test/test.dart';

/// 只覆写部分方法的集成,验证 `with Telemetry` + 未覆写方法默认 no-op。
final class RecordingTelemetry with Telemetry {
  final List<String> calls = [];
  TelemetryMetadata? lastMetadata;

  @override
  FutureOr<void> onLanguageModelCallStart(
    LanguageModelCallStartEvent e,
    TelemetryMetadata m,
  ) {
    calls.add('lmStart:${e.callId}');
    lastMetadata = m;
  }

  @override
  FutureOr<void> onToolExecutionStart(
    ToolExecutionStartEvent e,
    TelemetryMetadata m,
  ) {
    calls.add('toolStart:${e.toolCallId}');
    lastMetadata = m;
  }

  @override
  Future<void> onToolExecutionEnd(
    ToolExecutionEndEvent e,
    TelemetryMetadata m,
  ) async {
    calls.add('toolEnd:${e.toolCallId}');
  }
}

/// 覆写所有方法(编译期校验全部签名存在且形态为 `(event, TelemetryMetadata)`)。
final class FullTelemetry with Telemetry {
  @override
  FutureOr<void> onStart(GenerateTextStartEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onStepStart(
      GenerateTextStepStartEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onLanguageModelCallStart(
      LanguageModelCallStartEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onLanguageModelCallEnd(
      LanguageModelCallEndEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onToolExecutionStart(
      ToolExecutionStartEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onToolExecutionEnd(
      ToolExecutionEndEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onStepEnd(StepResult step, TelemetryMetadata m) {}
  @override
  FutureOr<void> onEnd(GenerateTextEndEvent e, TelemetryMetadata m) {}
  @override
  FutureOr<void> onError(Object? error, TelemetryMetadata m) {}
}

void main() {
  group('TelemetryMetadata', () {
    test('defaults recordInputs/recordOutputs to true', () {
      const m = TelemetryMetadata();
      expect(m.functionId, isNull);
      expect(m.recordInputs, isTrue);
      expect(m.recordOutputs, isTrue);
    });

    test('holds functionId and record flags', () {
      const m = TelemetryMetadata(
        functionId: 'chatbot',
        recordInputs: false,
        recordOutputs: true,
      );
      expect(m.functionId, 'chatbot');
      expect(m.recordInputs, isFalse);
      expect(m.recordOutputs, isTrue);
    });
  });

  group('Telemetry mixin', () {
    test('partial override records; non-overridden methods are no-op',
        () async {
      final t = RecordingTelemetry();
      const meta = TelemetryMetadata(functionId: 'f1');

      t.onLanguageModelCallStart(
        LanguageModelCallStartEvent(
          callId: 'call_1',
          providerId: 'openai',
          modelId: 'gpt-4o',
          stepNumber: 0,
          messages: const [],
        ),
        meta,
      );
      t.onToolExecutionStart(
        const ToolExecutionStartEvent(
          callId: 'exec_1',
          toolCallId: 'tc_1',
          toolName: 'lookup',
          input: null,
          toolContext: null,
        ),
        meta,
      );
      await t.onToolExecutionEnd(
        const ToolExecutionEndSuccess(
          callId: 'exec_1',
          toolCallId: 'tc_1',
          toolName: 'lookup',
          output: null,
          toolExecutionMs: 1,
        ),
        meta,
      );

      // 未覆写的默认方法调用应为 no-op,不抛错。
      final noop = t.onError(StateError('x'), meta);
      if (noop is Future) await noop;

      expect(t.calls, ['lmStart:call_1', 'toolStart:tc_1', 'toolEnd:tc_1']);
      expect(t.lastMetadata?.functionId, 'f1');
    });

    test('a class overriding every method instantiates', () {
      expect(FullTelemetry(), isA<Telemetry>());
    });
  });
}
