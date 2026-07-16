import 'dart:typed_data';

import 'package:pigcode_ai_provider/src/language_model/finish_reason.dart';
import 'package:pigcode_ai_provider/src/language_model/language_model_events.dart';
import 'package:pigcode_ai_provider/src/shared/shared.dart';
import 'package:pigcode_ai_provider/src/language_model/usage.dart';
import 'package:test/test.dart';

void main() {
  group('shared items assignable to both sealed roots', () {
    test('ToolCall is a LanguageModelContent and a LanguageModelStreamPart',
        () {
      const toolCall = ToolCall(
        toolCallId: 'call_1',
        toolName: 'get_weather',
        input: '{"city":"paris"}',
      );
      expect(toolCall, isA<LanguageModelContent>());
      expect(toolCall, isA<LanguageModelStreamPart>());
    });

    test('the seven shared items satisfy both roles', () {
      final shared = <Object>[
        const ToolCall(toolCallId: 'c', toolName: 't', input: '{}'),
        const ToolResult(toolCallId: 'c', toolName: 't', result: 42),
        const ToolApprovalRequest(approvalId: 'a', toolCallId: 'c'),
        const SourceContent.url(id: 's', url: 'https://example.com'),
        const FileContent(
          data: FileDataBase64('eA=='),
          mediaType: 'text/plain',
        ),
        const ReasoningFileContent(
          data: FileDataBase64('eQ=='),
          mediaType: 'text/plain',
        ),
        const CustomContentBlock('ns.block'),
      ];
      for (final item in shared) {
        expect(item, isA<LanguageModelContent>());
        expect(item, isA<LanguageModelStreamPart>());
      }
    });

    test('TextContent/ReasoningContent are content-only (not stream parts)',
        () {
      // 流侧文本/推理走 id 关联的 delta 事件,聚合内容不进流。
      expect(const TextContent('hi'), isA<LanguageModelContent>());
      expect(const TextContent('hi'), isNot(isA<LanguageModelStreamPart>()));
      expect(const ReasoningContent('t'), isA<LanguageModelContent>());
      expect(
        const ReasoningContent('t'),
        isNot(isA<LanguageModelStreamPart>()),
      );
    });
  });

  group('exhaustive switch compiles over each sealed root', () {
    String describeContent(LanguageModelContent c) => switch (c) {
          TextContent() => 'text',
          ReasoningContent() => 'reasoning',
          ToolCall() => 'tool-call',
          ToolResult() => 'tool-result',
          ToolApprovalRequest() => 'tool-approval',
          SourceContent() => 'source',
          FileContent() => 'file',
          ReasoningFileContent() => 'reasoning-file',
          CustomContentBlock() => 'custom',
        };

    String describePart(LanguageModelStreamPart p) => switch (p) {
          ToolCall() => 'c:tool-call',
          ToolResult() => 'c:tool-result',
          ToolApprovalRequest() => 'c:tool-approval',
          SourceContent() => 'c:source',
          FileContent() => 'c:file',
          ReasoningFileContent() => 'c:reasoning-file',
          CustomContentBlock() => 'c:custom',
          TextStart() => 'text-start',
          TextDelta() => 'text-delta',
          TextEnd() => 'text-end',
          ReasoningStart() => 'reasoning-start',
          ReasoningDelta() => 'reasoning-delta',
          ReasoningEnd() => 'reasoning-end',
          ToolInputStart() => 'tool-input-start',
          ToolInputDelta() => 'tool-input-delta',
          ToolInputEnd() => 'tool-input-end',
          StreamStart() => 'stream-start',
          ResponseMetadata() => 'response-metadata',
          FinishPart() => 'finish',
          RawPart() => 'raw',
          ErrorPart() => 'error',
        };

    test('content switch returns tags', () {
      expect(describeContent(const TextContent('x')), 'text');
      expect(
        describeContent(
          const ToolCall(toolCallId: 'c', toolName: 't', input: '{}'),
        ),
        'tool-call',
      );
    });

    test('stream-part switch returns tags for shared and stream-only', () {
      expect(
        describePart(
          const ToolCall(toolCallId: 'c', toolName: 't', input: '{}'),
        ),
        'c:tool-call',
      );
      expect(describePart(const TextStart('t1')), 'text-start');
      expect(describePart(const TextDelta('t1', 'hel')), 'text-delta');
      expect(describePart(const ToolInputEnd('c1')), 'tool-input-end');
      expect(describePart(const RawPart(<String, Object?>{})), 'raw');
    });
  });

  group('equality of representative parts', () {
    test('shared items compare by value', () {
      expect(const TextContent('a'), const TextContent('a'));
      expect(const TextContent('a'), isNot(const TextContent('b')));
      expect(
        const ToolCall(toolCallId: 'c', toolName: 't', input: '{}'),
        const ToolCall(toolCallId: 'c', toolName: 't', input: '{}'),
      );
      expect(
        const ToolResult(toolCallId: 'c', toolName: 't', result: 1),
        isNot(const ToolResult(toolCallId: 'c', toolName: 't', result: 2)),
      );
    });

    test('ToolResult.result accepts null (v7: JSONValue includes null)', () {
      const result = ToolResult(toolCallId: 'c', toolName: 't', result: null);

      expect(result.result, isNull);
      expect(
        result,
        const ToolResult(toolCallId: 'c', toolName: 't', result: null),
      );
      expect(
        result,
        isNot(const ToolResult(toolCallId: 'c', toolName: 't', result: 1)),
      );
    });

    test('providerMetadata participates in equality (deep-compared)', () {
      expect(
        const TextContent('a', providerMetadata: {
          'openai': {'k': 1}
        }),
        const TextContent('a', providerMetadata: {
          'openai': {'k': 1}
        }),
      );
      expect(
        const TextContent('a', providerMetadata: {
          'openai': {'k': 1}
        }),
        isNot(const TextContent('a', providerMetadata: {
          'openai': {'k': 2}
        })),
      );
    });

    test('stream-only parts compare by value', () {
      expect(const TextDelta('t1', 'hel'), const TextDelta('t1', 'hel'));
      expect(const TextDelta('t1', 'hel'), isNot(const TextDelta('t1', 'lo')));
      expect(
        const ToolInputStart(id: 'c', toolName: 't', title: 'Weather'),
        const ToolInputStart(id: 'c', toolName: 't', title: 'Weather'),
      );
      expect(
        StreamStart(const [UnsupportedWarning('reasoning')]),
        StreamStart(const [UnsupportedWarning('reasoning')]),
      );
    });

    test('FinishPart compares by value including nested usage', () {
      const usage = LanguageModelUsage(
        inputTokens: InputTokens(total: 3),
        outputTokens: OutputTokens(total: 5),
      );
      const reason = LanguageModelFinishReason(FinishReasonType.stop);
      expect(
        const FinishPart(usage: usage, finishReason: reason),
        const FinishPart(usage: usage, finishReason: reason),
      );
    });

    test('FileContent compares FileData by value', () {
      expect(
        FileContent(
          data: FileDataBytes(Uint8List.fromList([1, 2, 3])),
          mediaType: 'application/octet-stream',
        ),
        FileContent(
          data: FileDataBytes(Uint8List.fromList([1, 2, 3])),
          mediaType: 'application/octet-stream',
        ),
      );
    });
  });

  group('ErrorPart holds error object', () {
    test('carries an arbitrary error value', () {
      final err = StateError('boom');
      final part = ErrorPart(err);
      expect(part.error, same(err));
    });

    test('is a stream part and null error is allowed', () {
      const part = ErrorPart(null);
      expect(part, isA<LanguageModelStreamPart>());
      expect(part.error, isNull);
    });
  });

  group('SourceContent named constructors', () {
    test('url source sets sourceType.url and leaves document fields null', () {
      const s = SourceContent.url(
        id: 's1',
        url: 'https://example.com',
        title: 'Example',
      );
      expect(s.sourceType, SourceType.url);
      expect(s.url, 'https://example.com');
      expect(s.mediaType, isNull);
      expect(s.filename, isNull);
    });

    test('document source sets sourceType.document and leaves url null', () {
      const s = SourceContent.document(
        id: 's2',
        mediaType: 'application/pdf',
        title: 'Doc',
        filename: 'doc.pdf',
      );
      expect(s.sourceType, SourceType.document);
      expect(s.url, isNull);
      expect(s.mediaType, 'application/pdf');
      expect(s.title, 'Doc');
      expect(s.filename, 'doc.pdf');
    });
  });
}
