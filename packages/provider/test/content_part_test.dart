import 'dart:typed_data';

import 'package:pigcode_ai_provider/src/language_model/content_part.dart';
import 'package:pigcode_ai_provider/src/shared/shared.dart';
import 'package:pigcode_ai_provider/src/language_model/tool.dart';
import 'package:test/test.dart';

void main() {
  group('TextPart', () {
    test('值相等：文本与 providerOptions 相同即相等', () {
      const a = TextPart('hi', providerOptions: {
        'openai': {'k': 1},
      });
      const b = TextPart('hi', providerOptions: {
        'openai': {'k': 1},
      });
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：文本不同则不等', () {
      const a = TextPart('hi');
      const b = TextPart('bye');
      expect(a, isNot(equals(b)));
    });
  });

  group('FilePart', () {
    test('值相等：深比较字节数据', () {
      final a = FilePart(
        data: FileDataBytes(Uint8List.fromList([1, 2, 3])),
        mediaType: 'image/png',
        filename: 'a.png',
      );
      final b = FilePart(
        data: FileDataBytes(Uint8List.fromList([1, 2, 3])),
        mediaType: 'image/png',
        filename: 'a.png',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：mediaType 不同则不等', () {
      final a = FilePart(
        data: FileDataBase64('YQ=='),
        mediaType: 'image/png',
      );
      final b = FilePart(
        data: FileDataBase64('YQ=='),
        mediaType: 'image/jpeg',
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ReasoningPart / ReasoningFilePart / CustomPart', () {
    test('ReasoningPart 值相等', () {
      const a = ReasoningPart('because');
      const b = ReasoningPart('because');
      expect(a, equals(b));
    });

    test('ReasoningFilePart 值相等', () {
      final a = ReasoningFilePart(
        data: FileDataBase64('YQ=='),
        mediaType: 'application/json',
      );
      final b = ReasoningFilePart(
        data: FileDataBase64('YQ=='),
        mediaType: 'application/json',
      );
      expect(a, equals(b));
    });

    test('CustomPart 值相等', () {
      const a = CustomPart('ns.name');
      const b = CustomPart('ns.name');
      expect(a, equals(b));
      expect(a, isNot(equals(const CustomPart('ns.other'))));
    });
  });

  group('ToolCallPart', () {
    test('值相等：input 为已解析对象，深比较', () {
      const a = ToolCallPart(
        toolCallId: 'c1',
        toolName: 'search',
        input: {
          'q': 'dart',
          'n': [1, 2],
        },
        providerExecuted: true,
      );
      const b = ToolCallPart(
        toolCallId: 'c1',
        toolName: 'search',
        input: {
          'q': 'dart',
          'n': [1, 2],
        },
        providerExecuted: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：input 不同则不等', () {
      const a = ToolCallPart(
        toolCallId: 'c1',
        toolName: 'search',
        input: {'q': 'dart'},
      );
      const b = ToolCallPart(
        toolCallId: 'c1',
        toolName: 'search',
        input: {'q': 'go'},
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ToolApprovalRequestPart', () {
    test('值相等：审批请求字段相同即相等', () {
      const a = ToolApprovalRequestPart(
        approvalId: 'a1',
        toolCallId: 'c1',
      );
      const b = ToolApprovalRequestPart(
        approvalId: 'a1',
        toolCallId: 'c1',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：toolCallId 不同则不等', () {
      const a = ToolApprovalRequestPart(
        approvalId: 'a1',
        toolCallId: 'c1',
      );
      const b = ToolApprovalRequestPart(
        approvalId: 'a1',
        toolCallId: 'c2',
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ToolResultPart', () {
    test('值相等：output 变体相同即相等', () {
      const a = ToolResultPart(
        toolCallId: 'c1',
        toolName: 'search',
        output: ToolResultText('ok'),
      );
      const b = ToolResultPart(
        toolCallId: 'c1',
        toolName: 'search',
        output: ToolResultText('ok'),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：output 不同则不等', () {
      const a = ToolResultPart(
        toolCallId: 'c1',
        toolName: 'search',
        output: ToolResultText('ok'),
      );
      const b = ToolResultPart(
        toolCallId: 'c1',
        toolName: 'search',
        output: ToolResultJson({'ok': true}),
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ToolApprovalResponsePart', () {
    test('值相等：审批字段相同即相等', () {
      const a = ToolApprovalResponsePart(
        approvalId: 'a1',
        approved: true,
        reason: 'looks safe',
      );
      const b = ToolApprovalResponsePart(
        approvalId: 'a1',
        approved: true,
        reason: 'looks safe',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('值不等：approved 不同则不等', () {
      const a = ToolApprovalResponsePart(approvalId: 'a1', approved: true);
      const b = ToolApprovalResponsePart(approvalId: 'a1', approved: false);
      expect(a, isNot(equals(b)));
    });
  });

  group('角色标记接口（编译期安全）', () {
    test('List<UserContentPart> 接受 TextPart 与 FilePart', () {
      final userParts = <UserContentPart>[
        const TextPart('hello'),
        FilePart(
          data: FileDataBase64('YQ=='),
          mediaType: 'image/png',
        ),
      ];
      expect(userParts, hasLength(2));
      expect(userParts.first, isA<TextPart>());
      expect(userParts.last, isA<FilePart>());
    });

    test('List<AssistantContentPart> 接受 assistant 侧各 part', () {
      final assistantParts = <AssistantContentPart>[
        const TextPart('t'),
        const ReasoningPart('r'),
        const CustomPart('ns.name'),
        const ToolCallPart(
          toolCallId: 'c1',
          toolName: 'search',
          input: {'q': 'x'},
        ),
        const ToolApprovalRequestPart(
          approvalId: 'a1',
          toolCallId: 'c1',
        ),
        const ToolResultPart(
          toolCallId: 'c1',
          toolName: 'search',
          output: ToolResultText('ok'),
        ),
      ];
      expect(assistantParts, hasLength(6));
    });

    test('List<ToolContentPart> 接受 ToolResultPart 与 ToolApprovalResponsePart',
        () {
      final toolParts = <ToolContentPart>[
        const ToolResultPart(
          toolCallId: 'c1',
          toolName: 'search',
          output: ToolResultText('ok'),
        ),
        const ToolApprovalResponsePart(approvalId: 'a1', approved: true),
      ];
      expect(toolParts, hasLength(2));
      expect(toolParts.first, isA<ToolResultPart>());
      expect(toolParts.last, isA<ToolApprovalResponsePart>());
    });
  });
}
