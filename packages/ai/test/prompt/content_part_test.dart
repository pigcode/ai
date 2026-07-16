import 'dart:typed_data';

import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('TextPart', () {
    test('等值:相同 text 与 providerOptions 相等', () {
      expect(
        const TextPart('hello'),
        equals(const TextPart('hello')),
      );
      expect(
        const TextPart('hello', providerOptions: {
          'openai': {'foo': 'bar'},
        }),
        equals(const TextPart('hello', providerOptions: {
          'openai': {'foo': 'bar'},
        })),
      );
    });

    test('不等值:text 不同则不相等', () {
      expect(const TextPart('a'), isNot(equals(const TextPart('b'))));
    });

    test('可作为 UserContentPart 与 AssistantContentPart 出现', () {
      final List<UserContentPart> userParts = [const TextPart('hi')];
      final List<AssistantContentPart> assistantParts = [const TextPart('hi')];
      expect(userParts.single, isA<TextPart>());
      expect(assistantParts.single, isA<TextPart>());
    });
  });

  group('FilePart + DataContent', () {
    test('DataBytes 等值:相同字节数组相等', () {
      expect(
        FilePart(
          data: DataBytes(Uint8List.fromList([1, 2, 3])),
          mediaType: 'image/png',
        ),
        equals(FilePart(
          data: DataBytes(Uint8List.fromList([1, 2, 3])),
          mediaType: 'image/png',
        )),
      );
    });

    test('DataBase64 等值', () {
      expect(
        const FilePart(data: DataBase64('YWJj'), mediaType: 'text/plain'),
        equals(
          const FilePart(data: DataBase64('YWJj'), mediaType: 'text/plain'),
        ),
      );
    });

    test('DataText 等值', () {
      expect(
        const FilePart(data: DataText('plain document'), mediaType: 'text'),
        equals(
          const FilePart(data: DataText('plain document'), mediaType: 'text'),
        ),
      );
    });

    test('DataUrl 等值', () {
      expect(
        FilePart(
          data: DataUrl(Uri.parse('https://example.com/a.png')),
          mediaType: 'image/png',
        ),
        equals(FilePart(
          data: DataUrl(Uri.parse('https://example.com/a.png')),
          mediaType: 'image/png',
        )),
      );
    });

    test('DataProviderRef 等值', () {
      expect(
        const FilePart(
          data: DataProviderRef({'openai': 'file-123'}),
          mediaType: 'application/pdf',
        ),
        equals(const FilePart(
          data: DataProviderRef({'openai': 'file-123'}),
          mediaType: 'application/pdf',
        )),
      );
    });

    test('mediaType 或 data 不同则不相等', () {
      expect(
        const FilePart(data: DataBase64('YWJj'), mediaType: 'text/plain'),
        isNot(equals(
          const FilePart(data: DataBase64('YWJj'), mediaType: 'image/png'),
        )),
      );
      expect(
        const FilePart(data: DataBase64('YWJj'), mediaType: 'text/plain'),
        isNot(equals(
          const FilePart(data: DataBase64('xyz='), mediaType: 'text/plain'),
        )),
      );
      expect(
        const FilePart(data: DataText('hello'), mediaType: 'text/plain'),
        isNot(equals(
          const FilePart(data: DataText('world'), mediaType: 'text/plain'),
        )),
      );
    });

    test('可作为 UserContentPart 与 AssistantContentPart 出现', () {
      final List<UserContentPart> userParts = [
        const FilePart(data: DataBase64('YWJj'), mediaType: 'text/plain'),
      ];
      expect(userParts.single, isA<FilePart>());
    });
  });

  group('ReasoningPart', () {
    test('等值 + 仅可作为 AssistantContentPart', () {
      expect(
        const ReasoningPart('思考中'),
        equals(const ReasoningPart('思考中')),
      );
      final List<AssistantContentPart> parts = [const ReasoningPart('思考中')];
      expect(parts.single, isA<ReasoningPart>());
    });
  });

  group('CustomPart', () {
    test('等值:相同 kind 相等', () {
      expect(
        const CustomPart('ns.name'),
        equals(const CustomPart('ns.name')),
      );
      expect(
        const CustomPart('ns.a'),
        isNot(equals(const CustomPart('ns.b'))),
      );
    });
  });

  group('ToolCallPart', () {
    test('等值:input 为已解析 JsonValue', () {
      // input 显式标注为 JsonValue(Object?)以文档化「已解析值」语义。
      // ignore: unnecessary_nullable_for_final_variable_declarations
      const provider.JsonValue input = <String, Object?>{'x': 1};
      expect(
        const ToolCallPart(
          toolCallId: 'call_1',
          toolName: 'search',
          input: input,
        ),
        equals(const ToolCallPart(
          toolCallId: 'call_1',
          toolName: 'search',
          input: input,
        )),
      );
    });

    test('toolCallId 不同则不相等', () {
      expect(
        const ToolCallPart(toolCallId: 'a', toolName: 't', input: null),
        isNot(equals(
          const ToolCallPart(toolCallId: 'b', toolName: 't', input: null),
        )),
      );
    });
  });

  group('ToolApprovalRequestPart', () {
    test('等值:approvalId 与 toolCallId 相同即相等', () {
      expect(
        const ToolApprovalRequestPart(
          approvalId: 'approval-1',
          toolCallId: 'call_1',
        ),
        equals(const ToolApprovalRequestPart(
          approvalId: 'approval-1',
          toolCallId: 'call_1',
        )),
      );
    });

    test('仅可作为 AssistantContentPart 出现', () {
      final List<AssistantContentPart> parts = [
        const ToolApprovalRequestPart(
          approvalId: 'approval-1',
          toolCallId: 'call_1',
        ),
      ];
      expect(parts.single, isA<ToolApprovalRequestPart>());
    });
  });

  group('ToolResultPart', () {
    test('等值:output 复用契约 ToolResultOutput', () {
      expect(
        const ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'search',
          output: provider.ToolResultText('done'),
        ),
        equals(const ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'search',
          output: provider.ToolResultText('done'),
        )),
      );
    });

    test('可同时作为 AssistantContentPart 与 ToolContentPart 出现', () {
      const ToolResultPart part = ToolResultPart(
        toolCallId: 'call_1',
        toolName: 'search',
        output: provider.ToolResultText('done'),
      );
      final List<AssistantContentPart> assistantParts = [part];
      final List<ToolContentPart> toolParts = [part];
      expect(assistantParts.single, same(toolParts.single));
    });
  });

  group('ToolApprovalResponsePart', () {
    test('等值:审批字段相同即相等', () {
      expect(
        const ToolApprovalResponsePart(
          approvalId: 'approval-1',
          approved: true,
          reason: 'ok',
        ),
        equals(const ToolApprovalResponsePart(
          approvalId: 'approval-1',
          approved: true,
          reason: 'ok',
        )),
      );
    });

    test('仅可作为 ToolContentPart 出现', () {
      final List<ToolContentPart> parts = [
        const ToolApprovalResponsePart(
          approvalId: 'approval-1',
          approved: false,
          reason: 'blocked',
        ),
      ];
      expect(parts.single, isA<ToolApprovalResponsePart>());
    });
  });
}
