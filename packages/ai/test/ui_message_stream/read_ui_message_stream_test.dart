import 'package:pigcode_ai/src/ui/ui_message.dart';
import 'package:pigcode_ai/src/ui_message_stream/read_ui_message_stream.dart';
import 'package:pigcode_ai/src/ui_message_stream/ui_message_chunk.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('readUiMessageStream', () {
    test('accumulates text and reasoning into immutable snapshots', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          StartUiMessageChunk(messageId: 'm1'),
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'hel'),
          TextDeltaUiMessageChunk('txt_1', 'lo'),
          TextEndUiMessageChunk('txt_1'),
          ReasoningStartUiMessageChunk('rsn_1'),
          ReasoningDeltaUiMessageChunk('rsn_1', 'think'),
          ReasoningEndUiMessageChunk('rsn_1'),
          FinishUiMessageChunk(),
        ]),
      ).toList();

      expect(messages[2].parts, const [
        TextUiPart('hel', state: UiPartState.streaming),
      ]);
      expect(
          messages.last,
          UiMessage(
            id: 'm1',
            role: UiMessageRole.assistant,
            parts: const [
              TextUiPart('hello', state: UiPartState.done),
              ReasoningUiPart('think', state: UiPartState.done),
            ],
          ));
      expect(
        messages[2].parts,
        const [TextUiPart('hel', state: UiPartState.streaming)],
      );
      expect(
        () => messages.last.parts.add(const TextUiPart('x')),
        throwsUnsupportedError,
      );
    });

    test('preserves text and reasoning delta provider metadata', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk(
            'txt_1',
            'hello',
            providerMetadata: const {
              'openai': {'text-delta': 'meta'},
            },
          ),
          ReasoningStartUiMessageChunk('rsn_1'),
          ReasoningDeltaUiMessageChunk(
            'rsn_1',
            'thinking',
            providerMetadata: const {
              'openai': {'reasoning-delta': 'meta'},
            },
          ),
        ]),
      ).toList();

      expect(messages.last.parts, const [
        TextUiPart(
          'hello',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'text-delta': 'meta'},
          },
        ),
        ReasoningUiPart(
          'thinking',
          state: UiPartState.streaming,
          providerMetadata: {
            'openai': {'reasoning-delta': 'meta'},
          },
        ),
      ]);
    });

    test('updates tool state from input to approval to output', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          StartUiMessageChunk(messageId: 'm1'),
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            providerExecuted: false,
            providerMetadata: const {
              'openai': {'call': 'start'},
            },
          ),
          const ToolInputDeltaUiMessageChunk('call_1', '{"city"'),
          const ToolInputDeltaUiMessageChunk('call_1', ':"SF"}'),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
            providerMetadata: const {
              'openai': {'call': 'approval-request'},
            },
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
            reason: 'ok',
            providerExecuted: true,
            providerMetadata: const {
              'openai': {'result': 'approval-response'},
            },
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
        ]),
      ).toList();

      expect(messages.last.parts, [
        const ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
          providerExecuted: true,
          callProviderMetadata: {
            'openai': {'call': 'approval-request'},
          },
          resultProviderMetadata: {
            'openai': {'result': 'approval-response'},
          },
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
            reason: 'ok',
          ),
        ),
      ]);
    });

    test('updates tool input delta as raw text or repaired JSON object',
        () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
          ),
          const ToolInputDeltaUiMessageChunk('call_1', 'not json'),
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_2',
            toolName: 'lookup',
          ),
          const ToolInputDeltaUiMessageChunk('call_2', '{"city":"SF"'),
        ]),
      ).toList();

      expect((messages[1].parts.single as ToolUiPart).input, 'not json');
      expect(
        (messages.last.parts.last as ToolUiPart).input,
        const {'city': 'SF'},
      );
    });

    test('merges message metadata by top-level key', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          StartUiMessageChunk(
            messageId: 'm1',
            messageMetadata: const {
              'thread': {'id': 't1'},
            },
          ),
          MessageMetadataUiMessageChunk(const {
            'run': {'id': 'r1'},
          }),
          FinishUiMessageChunk(
            messageMetadata: const {
              'thread': {'id': 't2'},
            },
          ),
        ]),
      ).toList();

      expect(messages.last.metadata, const {
        'thread': {'id': 't2'},
        'run': {'id': 'r1'},
      });
      expect(messages.first.metadata, const {
        'thread': {'id': 't1'},
      });
    });

    test('reads step start and ignores step finish', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable(const [
          StartStepUiMessageChunk(),
          FinishStepUiMessageChunk(),
        ]),
      ).toList();

      expect(messages.first.parts, const [StepStartUiPart()]);
      expect(messages.last.parts, const [StepStartUiPart()]);
    });

    test('reports invalid chunk order and continues by default', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextDeltaUiMessageChunk('missing', 'x'),
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'ok'),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        TextUiPart('ok', state: UiPartState.streaming),
      ]);
    });

    test('terminates on invalid chunk order when requested', () async {
      expect(
        readUiMessageStream(
          stream: Stream<UiMessageChunk>.fromIterable([
            ToolOutputAvailableUiMessageChunk(
              toolCallId: 'missing',
              output: 'x',
            ),
          ]),
          terminateOnError: true,
        ).drain<void>(),
        throwsA(isA<provider.InvalidArgumentError>()),
      );
    });

    test('rejects duplicate active text and reasoning ids', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'ok'),
          ReasoningStartUiMessageChunk('rsn_1'),
          ReasoningStartUiMessageChunk('rsn_1'),
          ReasoningDeltaUiMessageChunk('rsn_1', 'thinking'),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, everyElement(isA<provider.InvalidArgumentError>()));
      expect(errors, hasLength(2));
      expect(messages.last.parts, const [
        TextUiPart('ok', state: UiPartState.streaming),
        ReasoningUiPart('thinking', state: UiPartState.streaming),
      ]);
    });

    test('terminates on duplicate active text id when requested', () async {
      expect(
        readUiMessageStream(
          stream: Stream<UiMessageChunk>.fromIterable([
            TextStartUiMessageChunk('txt_1'),
            TextStartUiMessageChunk('txt_1'),
          ]),
          terminateOnError: true,
        ).drain<void>(),
        throwsA(isA<provider.InvalidArgumentError>()),
      );
    });

    test('reports ErrorUiMessageChunk without changing parts', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'ok'),
          ErrorUiMessageChunk('boom'),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, const ['boom']);
      expect(messages.last.parts, const [
        TextUiPart('ok', state: UiPartState.streaming),
      ]);
    });

    test('merges terminal error metadata before reporting error', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          TextStartUiMessageChunk('txt_1'),
          TextDeltaUiMessageChunk('txt_1', 'ok'),
          ErrorUiMessageChunk(
            'boom',
            messageMetadata: const {
              'terminal': {'ok': true},
            },
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, const ['boom']);
      expect(messages.last.metadata, const {
        'terminal': {'ok': true},
      });
      expect(messages.last.parts, const [
        TextUiPart('ok', state: UiPartState.streaming),
      ]);
    });

    test('terminates on ErrorUiMessageChunk when requested', () async {
      expect(
        readUiMessageStream(
          stream: Stream<UiMessageChunk>.fromIterable([
            ErrorUiMessageChunk('boom'),
          ]),
          terminateOnError: true,
        ).drain<void>(),
        throwsA(isA<provider.InvalidArgumentError>().having(
          (error) => error.argument,
          'argument',
          'errorText',
        )),
      );
    });

    test('reports unfinished active tool input when stream finishes', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
          ),
          const ToolInputDeltaUiMessageChunk('call_1', '{"city"'),
          FinishUiMessageChunk(),
          TextStartUiMessageChunk('txt_1'),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(
        messages.last.parts.last,
        const TextUiPart('', state: UiPartState.streaming),
      );
    });

    test('reports unfinished active tool input when chunk stream closes',
        () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
          ),
          const ToolInputDeltaUiMessageChunk('call_1', '{"city"'),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(
        messages.last.parts.single,
        isA<ToolUiPart>().having(
          (part) => part.state,
          'state',
          UiToolState.inputStreaming,
        ),
      );
    });

    test('terminates on unfinished active tool input when chunk stream closes',
        () async {
      expect(
        readUiMessageStream(
          stream: Stream<UiMessageChunk>.fromIterable([
            ToolInputStartUiMessageChunk(
              toolCallId: 'call_1',
              toolName: 'lookup',
            ),
          ]),
          terminateOnError: true,
        ).drain<void>(),
        throwsA(isA<provider.InvalidArgumentError>()),
      );
    });

    test('rejects duplicate tool call starts', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
          ),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
          ToolInputStartUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
        ),
      ]);
    });

    test('rejects input available after input is already complete', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'LA'},
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'NYC'},
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, everyElement(isA<provider.InvalidArgumentError>()));
      expect(errors, hasLength(2));
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
        ),
      ]);
    });

    test('rejects approval request after output is available', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
        ),
      ]);
    });

    test('rejects output error after output is available', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
          ToolOutputErrorUiMessageChunk(
            toolCallId: 'call_1',
            errorText: 'failed',
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
        ),
      ]);
    });

    test('replaces preliminary tool output with the final output', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'generate_image',
            input: const {'prompt': 'city'},
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'image': 'partial'},
            providerExecuted: true,
            preliminary: true,
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'image': 'final'},
            providerExecuted: true,
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, isEmpty);
      expect(messages[1].parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'generate_image',
          state: UiToolState.outputAvailable,
          input: {'prompt': 'city'},
          output: {'image': 'partial'},
          providerExecuted: true,
          preliminary: true,
        ),
      ]);
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'generate_image',
          state: UiToolState.outputAvailable,
          input: {'prompt': 'city'},
          output: {'image': 'final'},
          providerExecuted: true,
        ),
      ]);
    });

    test('rejects output available after output error', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolOutputErrorUiMessageChunk(
            toolCallId: 'call_1',
            errorText: 'failed',
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputError,
          input: {'city': 'SF'},
          errorText: 'failed',
        ),
      ]);
    });

    test('scopes streamed tool and approval ids to each step', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
          const StartStepUiMessageChunk(),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'NYC'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: false,
            reason: 'not now',
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, isEmpty);
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
          ),
        ),
        StepStartUiPart(),
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.approvalResponded,
          input: {'city': 'NYC'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: false,
            reason: 'not now',
          ),
        ),
      ]);
    });

    test('keeps denied approval when execution-denied output follows',
        () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'delete_file',
            input: const {'path': '/tmp/a.txt'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: false,
            reason: 'blocked',
            providerMetadata: const {
              'openai': {'approval': 'meta'},
            },
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: 'blocked',
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, isEmpty);
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'delete_file',
          state: UiToolState.approvalResponded,
          input: {'path': '/tmp/a.txt'},
          resultProviderMetadata: {
            'openai': {'approval': 'meta'},
          },
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: false,
            reason: 'blocked',
          ),
        ),
      ]);
    });

    test('clears mutually exclusive output and error fields', () async {
      final outputMessages = await readUiMessageStream(
        message: UiMessage(
          id: 'm1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.inputAvailable,
              input: {'city': 'SF'},
              errorText: 'stale',
            ),
          ],
        ),
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
        ]),
      ).toList();

      expect(outputMessages.single.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
        ),
      ]);

      final errorMessages = await readUiMessageStream(
        message: UiMessage(
          id: 'm1',
          role: UiMessageRole.assistant,
          parts: const [
            ToolUiPart(
              toolCallId: 'call_1',
              toolName: 'lookup',
              state: UiToolState.inputAvailable,
              input: {'city': 'SF'},
              output: {'weather': 'sunny'},
            ),
          ],
        ),
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolOutputErrorUiMessageChunk(
            toolCallId: 'call_1',
            errorText: 'failed',
          ),
        ]),
      ).toList();

      expect(errorMessages.single.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputError,
          input: {'city': 'SF'},
          errorText: 'failed',
        ),
      ]);
    });

    test('allows approval response before output available', () async {
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            output: const {'weather': 'sunny'},
          ),
        ]),
      ).toList();

      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.outputAvailable,
          input: {'city': 'SF'},
          output: {'weather': 'sunny'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
          ),
        ),
      ]);
    });

    test('rejects approval response after response or output', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: false,
          ),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_2',
            toolName: 'search',
            input: const {'q': 'dart'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_2',
            toolCallId: 'call_2',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_2',
            approved: true,
          ),
          ToolOutputAvailableUiMessageChunk(
            toolCallId: 'call_2',
            output: const {'ok': true},
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_2',
            approved: false,
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors, everyElement(isA<provider.InvalidArgumentError>()));
      expect(errors, hasLength(2));
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.approvalResponded,
          input: {'city': 'SF'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
          ),
        ),
        ToolUiPart(
          toolCallId: 'call_2',
          toolName: 'search',
          state: UiToolState.outputAvailable,
          input: {'q': 'dart'},
          output: {'ok': true},
          approval: UiToolApproval(
            approvalId: 'ap_2',
            approved: true,
          ),
        ),
      ]);
    });

    test('rejects duplicate approval ids and routes response by index',
        () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_2',
            toolName: 'search',
            input: const {'q': 'dart'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_2',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.approvalResponded,
          input: {'city': 'SF'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
          ),
        ),
        ToolUiPart(
          toolCallId: 'call_2',
          toolName: 'search',
          state: UiToolState.inputAvailable,
          input: {'q': 'dart'},
        ),
      ]);
    });

    test('rejects a second approval id for the same tool', () async {
      final errors = <Object>[];
      final messages = await readUiMessageStream(
        stream: Stream<UiMessageChunk>.fromIterable([
          ToolInputAvailableUiMessageChunk(
            toolCallId: 'call_1',
            toolName: 'lookup',
            input: const {'city': 'SF'},
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_1',
            toolCallId: 'call_1',
          ),
          ToolApprovalRequestUiMessageChunk(
            approvalId: 'ap_2',
            toolCallId: 'call_1',
          ),
          ToolApprovalResponseUiMessageChunk(
            approvalId: 'ap_1',
            approved: true,
          ),
        ]),
        onError: errors.add,
      ).toList();

      expect(errors.single, isA<provider.InvalidArgumentError>());
      expect(messages.last.parts, const [
        ToolUiPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          state: UiToolState.approvalResponded,
          input: {'city': 'SF'},
          approval: UiToolApproval(
            approvalId: 'ap_1',
            approved: true,
          ),
        ),
      ]);
    });
  });
}
