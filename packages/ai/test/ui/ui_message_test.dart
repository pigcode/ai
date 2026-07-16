import 'package:pigcode_ai/src/ui/ui_message.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('UiMessage', () {
    test('is immutable and compares by value', () {
      final parts = <UiMessagePart>[const TextUiPart('hello')];
      final message = UiMessage(
        id: 'm1',
        role: UiMessageRole.assistant,
        parts: parts,
        metadata: const <String, provider.JsonObject>{
          'conversation': {'id': 'c1'},
        },
      );
      parts.add(const TextUiPart('mutated'));

      expect(message.parts, const [TextUiPart('hello')]);
      expect(
        message,
        equals(UiMessage(
          id: 'm1',
          role: UiMessageRole.assistant,
          parts: const [TextUiPart('hello')],
          metadata: const <String, provider.JsonObject>{
            'conversation': {'id': 'c1'},
          },
        )),
      );
      expect(
        () => message.parts.add(const TextUiPart('x')),
        throwsUnsupportedError,
      );
    });

    test('copyWith updates and clears metadata', () {
      final message = UiMessage(
        id: 'm1',
        role: UiMessageRole.assistant,
        parts: const [TextUiPart('hello')],
        metadata: const <String, provider.JsonObject>{
          'conversation': {'id': 'c1'},
        },
      );

      expect(
        message.copyWith(
          id: 'm2',
          metadata: const <String, provider.JsonObject>{
            'conversation': {'id': 'c2'},
          },
        ),
        equals(UiMessage(
          id: 'm2',
          role: UiMessageRole.assistant,
          parts: const [TextUiPart('hello')],
          metadata: const <String, provider.JsonObject>{
            'conversation': {'id': 'c2'},
          },
        )),
      );
      expect(message.copyWith(metadata: null).metadata, isNull);
    });
  });

  group('UiMessagePart', () {
    test('text/reasoning/file/custom/data parts compare by value', () {
      expect(
        const TextUiPart(
          'hello',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'id': 'txt_1'},
          },
        ),
        equals(const TextUiPart(
          'hello',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'id': 'txt_1'},
          },
        )),
      );
      expect(
        const TextUiPart('hello', state: UiPartState.streaming),
        isNot(equals(const TextUiPart('hello', state: UiPartState.done))),
      );
      expect(
        const ReasoningUiPart('thinking', state: UiPartState.done),
        equals(const ReasoningUiPart('thinking', state: UiPartState.done)),
      );
      expect(
        const ReasoningUiPart(
          'thinking',
          providerMetadata: {
            'openai': {'reasoning': 'meta'},
          },
        ),
        isNot(equals(const ReasoningUiPart(
          'thinking',
          providerMetadata: {
            'openai': {'reasoning': 'different'},
          },
        ))),
      );
      expect(
        FileUiPart(
          url: Uri.parse('https://example.com/a.png'),
          mediaType: 'image/png',
          filename: 'a.png',
          providerReference: const {'openai': 'file_1'},
          providerMetadata: const {
            'openai': {'file': 'meta'},
          },
        ),
        equals(FileUiPart(
          url: Uri.parse('https://example.com/a.png'),
          mediaType: 'image/png',
          filename: 'a.png',
          providerReference: const {'openai': 'file_1'},
          providerMetadata: const {
            'openai': {'file': 'meta'},
          },
        )),
      );
      expect(
        FileUiPart(
          url: Uri.parse('https://example.com/a.png'),
          mediaType: 'image/png',
          providerMetadata: const {
            'openai': {'file': 'meta'},
          },
        ),
        isNot(equals(FileUiPart(
          url: Uri.parse('https://example.com/a.png'),
          mediaType: 'image/png',
          providerMetadata: const {
            'openai': {'file': 'different'},
          },
        ))),
      );
      expect(
        ReasoningFileUiPart(
          url: Uri.parse('data:text/plain;base64,YQ=='),
          mediaType: 'text/plain',
          providerMetadata: const {
            'openai': {'reasoning_file': 'meta'},
          },
        ),
        equals(ReasoningFileUiPart(
          url: Uri.parse('data:text/plain;base64,YQ=='),
          mediaType: 'text/plain',
          providerMetadata: const {
            'openai': {'reasoning_file': 'meta'},
          },
        )),
      );
      expect(
        ReasoningFileUiPart(
          url: Uri.parse('data:text/plain;base64,YQ=='),
          mediaType: 'text/plain',
          providerMetadata: const {
            'openai': {'reasoning_file': 'meta'},
          },
        ),
        isNot(equals(ReasoningFileUiPart(
          url: Uri.parse('data:text/plain;base64,YQ=='),
          mediaType: 'text/plain',
          providerMetadata: const {
            'openai': {'reasoning_file': 'different'},
          },
        ))),
      );
      expect(
        const CustomUiPart(
          'openai.foo',
          providerMetadata: {
            'openai': {'custom': 'meta'},
          },
        ),
        equals(const CustomUiPart(
          'openai.foo',
          providerMetadata: {
            'openai': {'custom': 'meta'},
          },
        )),
      );
      expect(
        const CustomUiPart(
          'openai.foo',
          providerMetadata: {
            'openai': {'custom': 'meta'},
          },
        ),
        isNot(equals(const CustomUiPart(
          'openai.foo',
          providerMetadata: {
            'openai': {'custom': 'different'},
          },
        ))),
      );
      expect(
        const DataUiPart(
          type: 'data-weather',
          id: 'weather_1',
          data: {'temp': 72},
        ),
        equals(const DataUiPart(
          type: 'data-weather',
          id: 'weather_1',
          data: {'temp': 72},
        )),
      );
      expect(
        const DataUiPart(type: 'data-weather', id: 'weather_1', data: null),
        isNot(equals(const DataUiPart(
          type: 'data-weather',
          id: 'weather_2',
          data: null,
        ))),
      );
      expect(const StepStartUiPart(), equals(const StepStartUiPart()));
    });

    test('text and reasoning parts append text and mark done', () {
      const text = TextUiPart(
        'hel',
        state: UiPartState.streaming,
        providerMetadata: {
          'openai': {'id': 'txt_1'},
        },
      );
      expect(
        text.append('lo'),
        const TextUiPart(
          'hello',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'id': 'txt_1'},
          },
        ),
      );
      expect(
        text.markDone(
          providerMetadata: const {
            'openai': {'id': 'txt_done'},
          },
        ),
        const TextUiPart(
          'hel',
          state: UiPartState.done,
          providerMetadata: {
            'openai': {'id': 'txt_done'},
          },
        ),
      );

      const reasoning = ReasoningUiPart(
        'think',
        state: UiPartState.streaming,
        providerMetadata: {
          'openai': {'id': 'rsn_1'},
        },
      );
      expect(
        reasoning.append('ing'),
        const ReasoningUiPart(
          'thinking',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'id': 'rsn_1'},
          },
        ),
      );
      expect(
        reasoning.markDone(
          providerMetadata: const {
            'openai': {'id': 'rsn_done'},
          },
        ),
        const ReasoningUiPart(
          'think',
          state: UiPartState.done,
          providerMetadata: {
            'openai': {'id': 'rsn_done'},
          },
        ),
      );
    });

    test('tool part and approval compare by value', () {
      const pendingApproval = UiToolApproval(approvalId: 'ap_pending');
      const approval = UiToolApproval(
        approvalId: 'ap_1',
        approved: true,
        reason: 'ok',
      );
      const otherApproval = UiToolApproval(
        approvalId: 'ap_1',
        approved: true,
        reason: 'ok',
      );
      const part = ToolUiPart(
        toolCallId: 'call_1',
        toolName: 'lookup',
        state: UiToolState.outputAvailable,
        input: {'city': 'SF'},
        output: {'weather': 'sunny'},
        providerExecuted: false,
        preliminary: true,
        callProviderMetadata: {
          'openai': {'call': 'meta'},
        },
        resultProviderMetadata: {
          'openai': {'result': 'meta'},
        },
        approval: approval,
      );
      const otherPart = ToolUiPart(
        toolCallId: 'call_1',
        toolName: 'lookup',
        state: UiToolState.outputAvailable,
        input: {'city': 'SF'},
        output: {'weather': 'sunny'},
        providerExecuted: false,
        preliminary: true,
        callProviderMetadata: {
          'openai': {'call': 'meta'},
        },
        resultProviderMetadata: {
          'openai': {'result': 'meta'},
        },
        approval: otherApproval,
      );

      expect(pendingApproval.approved, isNull);
      expect(
        pendingApproval.copyWith(approved: false, reason: 'not now'),
        const UiToolApproval(
          approvalId: 'ap_pending',
          approved: false,
          reason: 'not now',
        ),
      );
      expect(approval, equals(otherApproval));
      expect(part, equals(otherPart));
      expect(part.toolCallId, 'call_1');
      expect(part.toolName, 'lookup');
      expect(part.state, UiToolState.outputAvailable);
      expect(part.input, const {'city': 'SF'});
      expect(part.output, const {'weather': 'sunny'});
      expect(part.providerExecuted, isFalse);
      expect(part.preliminary, isTrue);
      expect(part.callProviderMetadata, const {
        'openai': {'call': 'meta'},
      });
      expect(part.resultProviderMetadata, const {
        'openai': {'result': 'meta'},
      });
      expect(part.approval, approval);
      expect(part.approval!.approvalId, 'ap_1');
      expect(part.approval!.approved, isTrue);
      expect(part.approval!.reason, 'ok');
    });

    test('tool approval copyWith updates and clears nullable fields', () {
      const approval = UiToolApproval(approvalId: 'ap_1');

      expect(
        approval.copyWith(approved: true, reason: 'ok'),
        const UiToolApproval(
          approvalId: 'ap_1',
          approved: true,
          reason: 'ok',
        ),
      );
      expect(
        const UiToolApproval(
          approvalId: 'ap_1',
          approved: false,
          reason: 'no',
        ).copyWith(approved: null, reason: null),
        const UiToolApproval(approvalId: 'ap_1'),
      );
    });

    test('tool part copyWith updates and clears nullable fields', () {
      const approval = UiToolApproval(
        approvalId: 'ap_1',
        approved: true,
        reason: 'ok',
      );
      const part = ToolUiPart(
        toolCallId: 'call_1',
        toolName: 'lookup',
        state: UiToolState.outputError,
        input: {'city': 'SF'},
        output: {'weather': 'sunny'},
        errorText: 'old error',
        providerExecuted: true,
        preliminary: true,
        callProviderMetadata: {
          'openai': {'call': 'meta'},
        },
        resultProviderMetadata: {
          'openai': {'result': 'meta'},
        },
        approval: approval,
      );

      expect(
        part.copyWith(
          input: {'city': 'NYC'},
          output: {'weather': 'rainy'},
          errorText: 'ignored error',
        ),
        equals(part),
      );
      expect(
        part.copyWith(
          state: UiToolState.outputAvailable,
          input: {'city': 'NYC'},
          output: {'weather': 'rainy'},
          errorText: null,
          setInput: true,
          setOutput: true,
          setErrorText: true,
          preliminary: null,
        ),
        const ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'NYC'},
          output: {'weather': 'rainy'},
          providerExecuted: true,
          callProviderMetadata: {
            'openai': {'call': 'meta'},
          },
          resultProviderMetadata: {
            'openai': {'result': 'meta'},
          },
          approval: approval,
        ),
      );
      expect(
        part.copyWith(
          input: null,
          output: null,
          errorText: null,
          setInput: true,
          setOutput: true,
          setErrorText: true,
          providerExecuted: null,
          preliminary: null,
          callProviderMetadata: null,
          resultProviderMetadata: null,
          approval: null,
        ),
        const ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputError,
        ),
      );
      expect(
        part,
        isNot(equals(part.copyWith(
          state: UiToolState.outputDenied,
          providerExecuted: false,
        ))),
      );
    });
  });
}
