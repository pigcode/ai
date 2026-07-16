import 'dart:typed_data';

import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/prompt/standardize_prompt.dart';
import 'package:pigcode_ai/src/prompt/to_language_model_prompt.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('convertToLanguageModelPrompt', () {
    test('prepends instructions as a provider SystemMessage', () {
      final standardized = StandardizedPrompt(
        instructions: 'be concise',
        messages: [UserModelMessage.text('hi')],
      );

      final result = convertToLanguageModelPrompt(standardized);

      expect(result.length, 2);
      expect(result.first, isA<provider.SystemMessage>());
      expect((result.first as provider.SystemMessage).content, 'be concise');
    });

    test('maps SystemModelMessage to provider.SystemMessage', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [const SystemModelMessage('follow rules')],
      );

      final result = convertToLanguageModelPrompt(standardized);

      expect(result, [const provider.SystemMessage('follow rules')]);
    });

    test('maps UserModelMessage text content to provider.UserMessage', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [UserModelMessage.text('hello world')],
      );

      final result = convertToLanguageModelPrompt(standardized);

      expect(result, [
        const provider.UserMessage([provider.TextPart('hello world')]),
      ]);
    });
  });

  group('FilePart data variant mapping', () {
    test('DataBytes maps to provider.FileDataBytes', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(data: DataBytes(bytes), mediaType: 'image/png'),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, isA<provider.FileDataBytes>());
      expect((filePart.data as provider.FileDataBytes).bytes, bytes);
      expect(filePart.mediaType, 'image/png');
    });

    test('DataBase64 maps to provider.FileDataBase64', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            const FilePart(
              data: DataBase64('aGVsbG8='),
              mediaType: 'text/plain',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(
        filePart.data,
        const provider.FileDataBase64('aGVsbG8='),
      );
    });

    test('DataText maps to provider.FileDataText', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            const FilePart(
              data: DataText('plain document'),
              mediaType: 'text/plain',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, const provider.FileDataText('plain document'));
      expect(filePart.mediaType, 'text/plain');
    });

    test('DataUrl maps to provider.FileDataUrl', () {
      final url = Uri.parse('https://example.com/a.png');
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(data: DataUrl(url), mediaType: 'image/png'),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, provider.FileDataUrl(url));
    });

    test('data URL maps to provider.FileDataBase64 with parsed media type', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(
              data: DataUrl(Uri.parse('data:text/plain;base64,aGVsbG8=')),
              mediaType: 'application/octet-stream',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, const provider.FileDataBase64('aGVsbG8='));
      expect(filePart.mediaType, 'text/plain');
    });

    test('base64 data URL decodes percent-escaped payload', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(
              data: DataUrl(
                Uri.parse('data:application/octet-stream;base64,%2B%2F8%3D'),
              ),
              mediaType: 'text/plain',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, const provider.FileDataBase64('+/8='));
      expect(filePart.mediaType, 'application/octet-stream');
    });

    test('base64 data URL normalizes URL-safe and unpadded payload', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(
              data: DataUrl(
                Uri(
                  scheme: 'data',
                  path: 'application/octet-stream;base64,AA_-',
                ),
              ),
              mediaType: 'text/plain',
            ),
            FilePart(
              data: DataUrl(
                Uri(scheme: 'data', path: 'text/plain;base64,SGVsbG8'),
              ),
              mediaType: 'application/octet-stream',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final firstFilePart = user.content.first as provider.FilePart;
      final secondFilePart = user.content.last as provider.FilePart;
      expect(firstFilePart.data, const provider.FileDataBase64('AA/+'));
      expect(firstFilePart.mediaType, 'application/octet-stream');
      expect(secondFilePart.data, const provider.FileDataBase64('SGVsbG8='));
      expect(secondFilePart.mediaType, 'text/plain');
    });

    test('data URL without media type falls back to FilePart mediaType', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(
              data: DataUrl(Uri.parse('data:;base64,aGVsbG8=')),
              mediaType: 'application/octet-stream',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, const provider.FileDataBase64('aGVsbG8='));
      expect(filePart.mediaType, 'application/octet-stream');
    });

    test('non-base64 data URL maps to decoded provider.FileDataBytes', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            FilePart(
              data: DataUrl(Uri.parse('data:text/plain,hello%20world')),
              mediaType: 'application/octet-stream',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(filePart.data, isA<provider.FileDataBytes>());
      expect(
        (filePart.data as provider.FileDataBytes).bytes.toList(),
        'hello world'.codeUnits,
      );
      expect(filePart.mediaType, 'text/plain');
    });

    test('DataProviderRef maps to provider.FileDataReference', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          UserModelMessage([
            const FilePart(
              data: DataProviderRef({'openai': 'file_123'}),
              mediaType: 'application/pdf',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final user = result.single as provider.UserMessage;
      final filePart = user.content.single as provider.FilePart;
      expect(
        filePart.data,
        const provider.FileDataReference({'openai': 'file_123'}),
      );
    });
  });

  group('AssistantModelMessage tool mapping', () {
    test('maps ToolCallPart to provider.ToolCallPart with parsed input', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          AssistantModelMessage([
            const ToolCallPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: {'city': 'Paris'},
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final assistant = result.single as provider.AssistantMessage;
      final toolCall = assistant.content.single as provider.ToolCallPart;
      expect(toolCall.toolCallId, 'call_1');
      expect(toolCall.toolName, 'get_weather');
      expect(toolCall.input, {'city': 'Paris'});
    });

    test('maps ToolResultPart to provider.ToolResultPart', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          AssistantModelMessage([
            const ToolResultPart(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              output: provider.ToolResultText('sunny, 20C'),
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final assistant = result.single as provider.AssistantMessage;
      final toolResult = assistant.content.single as provider.ToolResultPart;
      expect(toolResult.toolCallId, 'call_1');
      expect(toolResult.output, const provider.ToolResultText('sunny, 20C'));
    });

    test('maps ToolApprovalRequestPart to provider.ToolApprovalRequestPart',
        () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          AssistantModelMessage([
            const ToolApprovalRequestPart(
              approvalId: 'approval-1',
              toolCallId: 'call_1',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final assistant = result.single as provider.AssistantMessage;
      final request =
          assistant.content.single as provider.ToolApprovalRequestPart;
      expect(request.approvalId, 'approval-1');
      expect(request.toolCallId, 'call_1');
    });

    test('maps ReasoningFilePart to provider.ReasoningFilePart', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          AssistantModelMessage([
            const ReasoningFilePart(
              data: DataBase64('AAA='),
              mediaType: 'application/json',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final assistant = result.single as provider.AssistantMessage;
      final part = assistant.content.single as provider.ReasoningFilePart;
      expect(part.data, const provider.FileDataBase64('AAA='));
      expect(part.mediaType, 'application/json');
    });

    test('maps ToolModelMessage ToolResultPart to provider.ToolMessage', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          ToolModelMessage([
            const ToolResultPart(
              toolCallId: 'call_2',
              toolName: 'lookup',
              output: provider.ToolResultJson({'ok': true}),
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final tool = result.single as provider.ToolMessage;
      final toolResult = tool.content.single as provider.ToolResultPart;
      expect(toolResult.toolCallId, 'call_2');
      expect(toolResult.output, const provider.ToolResultJson({'ok': true}));
    });

    test(
        'maps ToolModelMessage ToolApprovalResponsePart to '
        'provider.ToolApprovalResponsePart', () {
      final standardized = StandardizedPrompt(
        instructions: null,
        messages: [
          ToolModelMessage([
            const ToolApprovalResponsePart(
              approvalId: 'approval-1',
              approved: true,
              reason: 'approved by user',
            ),
          ]),
        ],
      );

      final result = convertToLanguageModelPrompt(standardized);

      final tool = result.single as provider.ToolMessage;
      final response = tool.content.single as provider.ToolApprovalResponsePart;
      expect(response.approvalId, 'approval-1');
      expect(response.approved, isTrue);
      expect(response.reason, 'approved by user');
    });
  });
}
