import 'package:pigcode_ai/src/generate_text/tool_approval.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('collectToolApprovals', () {
    test('returns no approvals when the last message is not a tool message',
        () {
      final approvals = collectToolApprovals([
        const provider.UserMessage([provider.TextPart('hello')]),
      ]);

      expect(approvals.approvedToolApprovals, isEmpty);
      expect(approvals.deniedToolApprovals, isEmpty);
    });

    test('splits approval responses into approved and denied groups', () {
      final approvals = collectToolApprovals([
        const provider.UserMessage([provider.TextPart('delete it')]),
        const provider.AssistantMessage([
          provider.ToolCallPart(
            toolCallId: 'call-delete',
            toolName: 'delete_file',
            input: {'path': 'a.txt'},
          ),
          provider.ToolApprovalRequestPart(
            approvalId: 'approval-1',
            toolCallId: 'call-delete',
          ),
          provider.ToolCallPart(
            toolCallId: 'call-email',
            toolName: 'send_email',
            input: {'to': 'team@example.com'},
          ),
          provider.ToolApprovalRequestPart(
            approvalId: 'approval-2',
            toolCallId: 'call-email',
          ),
        ]),
        const provider.ToolMessage([
          provider.ToolApprovalResponsePart(
            approvalId: 'approval-1',
            approved: true,
          ),
          provider.ToolApprovalResponsePart(
            approvalId: 'approval-2',
            approved: false,
            reason: 'not allowed',
          ),
        ]),
      ]);

      expect(approvals.approvedToolApprovals, hasLength(1));
      expect(approvals.approvedToolApprovals.single.toolCall.toolCallId,
          'call-delete');
      expect(
        approvals.approvedToolApprovals.single.approvalRequest.approvalId,
        'approval-1',
      );
      expect(
        approvals.approvedToolApprovals.single.approvalResponse.approved,
        isTrue,
      );

      expect(approvals.deniedToolApprovals, hasLength(1));
      expect(
        approvals.deniedToolApprovals.single.toolCall.toolCallId,
        'call-email',
      );
      expect(
        approvals.deniedToolApprovals.single.approvalResponse.reason,
        'not allowed',
      );
    });

    test(
        'skips an approval response when the same tool message already has '
        'the matching tool result', () {
      final approvals = collectToolApprovals([
        const provider.UserMessage([provider.TextPart('delete it')]),
        const provider.AssistantMessage([
          provider.ToolCallPart(
            toolCallId: 'call-delete',
            toolName: 'delete_file',
            input: {'path': 'a.txt'},
          ),
          provider.ToolApprovalRequestPart(
            approvalId: 'approval-1',
            toolCallId: 'call-delete',
          ),
        ]),
        const provider.ToolMessage([
          provider.ToolApprovalResponsePart(
            approvalId: 'approval-1',
            approved: true,
          ),
          provider.ToolResultPart(
            toolCallId: 'call-delete',
            toolName: 'delete_file',
            output: provider.ToolResultText('deleted'),
          ),
        ]),
      ]);

      expect(approvals.approvedToolApprovals, isEmpty);
      expect(approvals.deniedToolApprovals, isEmpty);
    });

    test('rejects approval responses with unknown approval ids', () {
      expect(
        () => collectToolApprovals([
          const provider.UserMessage([provider.TextPart('delete it')]),
          const provider.AssistantMessage([
            provider.ToolCallPart(
              toolCallId: 'call-delete',
              toolName: 'delete_file',
              input: {'path': 'a.txt'},
            ),
            provider.ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'call-delete',
            ),
          ]),
          const provider.ToolMessage([
            provider.ToolApprovalResponsePart(
              approvalId: 'stale-approval',
              approved: true,
            ),
          ]),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects approval requests that reference unknown tool calls', () {
      expect(
        () => collectToolApprovals([
          const provider.AssistantMessage([
            provider.ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'missing-call',
            ),
          ]),
          const provider.ToolMessage([
            provider.ToolApprovalResponsePart(
              approvalId: 'approval-1',
              approved: true,
            ),
          ]),
        ]),
        throwsA(isA<StateError>()),
      );
    });
  });
  group('resolveToolApproval', () {
    const messages = [
      provider.UserMessage([provider.TextPart('weather in Berlin?')]),
    ];
    const toolCall = provider.ToolCall(
      toolCallId: 'call-weather',
      toolName: 'weather',
      input: '{"city":"Berlin"}',
    );

    test('passes provider tool-call metadata to dynamic approval functions',
        () async {
      const metadata = {
        'openai': {'itemId': 'item-1'},
      };
      const toolCall = provider.ToolCall(
        toolCallId: 'call-weather',
        toolName: 'weather',
        input: '{"city":"Berlin"}',
        providerExecuted: true,
        isDynamic: true,
        providerMetadata: metadata,
      );
      provider.ToolCall? receivedToolCall;

      ToolApprovalStatus approvalFunction(ToolApprovalOptions options) {
        receivedToolCall = options.toolCall;
        return const ToolApprovalStatus.approved(reason: 'metadata ok');
      }

      final approval = await resolveToolApproval(
        toolApproval: approvalFunction,
        toolCall: toolCall,
        messages: messages,
        tools: null,
      );

      expect(
        approval,
        const ToolApprovalStatus.approved(reason: 'metadata ok'),
      );
      expect(receivedToolCall, same(toolCall));
      expect(receivedToolCall?.providerExecuted, isTrue);
      expect(receivedToolCall?.isDynamic, isTrue);
      expect(receivedToolCall?.providerMetadata, metadata);
    });

    test('does not decode input before a dynamic approval function', () async {
      const malformedToolCall = provider.ToolCall(
        toolCallId: 'call-weather',
        toolName: 'weather',
        input: '{',
      );
      provider.ToolCall? receivedToolCall;

      ToolApprovalStatus approvalFunction(ToolApprovalOptions options) {
        receivedToolCall = options.toolCall;
        return const ToolApprovalStatus.denied(reason: 'blocked');
      }

      final approval = await resolveToolApproval(
        toolApproval: approvalFunction,
        toolCall: malformedToolCall,
        messages: messages,
        tools: null,
      );

      expect(approval, const ToolApprovalStatus.denied(reason: 'blocked'));
      expect(receivedToolCall, same(malformedToolCall));
    });

    test('does not decode input before a static per-tool approval status',
        () async {
      const malformedToolCall = provider.ToolCall(
        toolCallId: 'call-weather',
        toolName: 'weather',
        input: '{',
      );

      final approval = await resolveToolApproval(
        toolApproval: {
          'weather': const ToolApprovalStatus.denied(reason: 'blocked'),
        },
        toolCall: malformedToolCall,
        messages: messages,
        tools: null,
      );

      expect(approval, const ToolApprovalStatus.denied(reason: 'blocked'));
    });

    test('calls a per-tool approval function with parsed input and options',
        () async {
      Object? receivedInput;
      SingleToolApprovalOptions? receivedOptions;

      final approval = await resolveToolApproval(
        toolApproval: {
          'weather': (
            provider.JsonValue input,
            SingleToolApprovalOptions options,
          ) {
            receivedInput = input;
            receivedOptions = options;
            return const ToolApprovalStatus.approved(reason: 'policy');
          },
        },
        toolCall: toolCall,
        messages: messages,
        tools: null,
      );

      expect(approval, const ToolApprovalStatus.approved(reason: 'policy'));
      expect(receivedInput, {'city': 'Berlin'});
      expect(receivedOptions?.toolCallId, 'call-weather');
      expect(receivedOptions?.messages, same(messages));
    });

    test('treats a null per-tool approval result as not applicable', () async {
      final approval = await resolveToolApproval(
        toolApproval: {
          'weather': (
            provider.JsonValue input,
            SingleToolApprovalOptions options,
          ) =>
              null,
        },
        toolCall: toolCall,
        messages: messages,
        tools: null,
      );

      expect(approval, ToolApprovalStatus.notApplicable);
    });

    test('keeps static per-tool approval statuses working', () async {
      final approval = await resolveToolApproval(
        toolApproval: {
          'weather': const ToolApprovalStatus.denied(reason: 'blocked'),
        },
        toolCall: toolCall,
        messages: messages,
        tools: null,
      );

      expect(approval, const ToolApprovalStatus.denied(reason: 'blocked'));
    });
  });
}
