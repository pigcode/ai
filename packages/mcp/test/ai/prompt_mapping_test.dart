import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('maps prompt roles and lossless embedded content', () {
    final mapped = mapMcpPrompt(
      McpGetPromptResult.fromJson(
        const <String, Object?>{
          'description': 'Inspect a file',
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'Inspect this',
                'annotations': <String, Object?>{'priority': 0.8},
              },
            },
            <String, Object?>{
              'role': 'assistant',
              'content': <String, Object?>{
                'type': 'resource',
                'resource': <String, Object?>{
                  'uri': 'file:///workspace/report.txt',
                  'text': 'report',
                },
              },
            },
          ],
        },
      ),
    );

    expect(mapped.description, 'Inspect a file');
    expect(mapped.messages.first, isA<UserModelMessage>());
    expect(mapped.messages.last, isA<AssistantModelMessage>());
    final text =
        (mapped.messages.first as UserModelMessage).content.single as TextPart;
    expect(
      text.providerOptions!['mcp']!['annotations'],
      containsPair('priority', 0.8),
    );
    final file = (mapped.messages.last as AssistantModelMessage).content.single
        as FilePart;
    expect(file.data, const DataText('report'));
  });

  test('prompt resource link requires explicit preserve policy', () {
    final result = McpGetPromptResult.fromJson(
      const <String, Object?>{
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <String, Object?>{
              'type': 'resource_link',
              'name': 'readme',
              'uri': 'file:///workspace/README.md',
            },
          },
        ],
      },
    );

    expect(() => mapMcpPrompt(result), throwsA(isA<McpMappingException>()));
    final mapped = mapMcpPrompt(
      result,
      policy: McpLossyMappingPolicy.preserveWithMetadata,
    );
    final part =
        (mapped.messages.single as UserModelMessage).content.single as TextPart;
    expect(part.providerOptions!['mcp']!['dereferenced'], isFalse);
  });
}
