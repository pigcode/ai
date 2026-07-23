import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('maps text, binary, embedded, link, structured, and mixed content', () {
    final output = mapMcpToolResult(
      McpCallToolResult.fromJson(
        const <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'done'},
            <String, Object?>{
              'type': 'image',
              'data': 'aW1hZ2U=',
              'mimeType': 'image/png',
            },
            <String, Object?>{
              'type': 'audio',
              'data': 'YXVkaW8=',
              'mimeType': 'audio/wav',
            },
            <String, Object?>{
              'type': 'resource',
              'resource': <String, Object?>{
                'uri': 'file:///workspace/report.txt',
                'text': 'report',
                'mimeType': 'text/plain',
              },
            },
            <String, Object?>{
              'type': 'resource_link',
              'name': 'details',
              'uri': 'file:///workspace/details.json',
              'annotations': <String, Object?>{'unknown': 'kept'},
            },
          ],
          'structuredContent': <String, Object?>{'ok': true},
        },
      ),
    );

    expect(output, isA<ToolResultContentOutput>());
    final items = (output as ToolResultContentOutput).items;
    expect(items.whereType<ToolResultTextItem>(), hasLength(1));
    expect(items.whereType<ToolResultFileItem>(), hasLength(3));
    expect(items.whereType<ToolResultCustomItem>(), hasLength(2));
    final link = items.whereType<ToolResultCustomItem>().first;
    final linkMetadata = link.providerOptions!['mcp']!;
    expect(linkMetadata['dereferenced'], isFalse);
    expect(
      (linkMetadata['resourceLink']! as Map<String, Object?>)['annotations'],
      containsPair('unknown', 'kept'),
    );
    final structured = items.whereType<ToolResultCustomItem>().last;
    expect(
      structured.providerOptions!['mcp']!['structuredContent'],
      <String, Object?>{'ok': true},
    );
  });

  test('maps MCP isError as model-visible error instead of throwing', () {
    final output = mapMcpToolResult(
      McpCallToolResult.fromJson(
        const <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'invalid input'},
          ],
          'isError': true,
        },
      ),
    );

    expect(output, isA<ToolResultErrorText>());
    expect((output as ToolResultErrorText).value, 'invalid input');
  });

  test('uses structured JSON when no unstructured content exists', () {
    final output = mapMcpToolResult(
      McpCallToolResult.fromJson(
        const <String, Object?>{
          'content': <Object?>[],
          'structuredContent': <String, Object?>{'value': 42},
        },
      ),
    );

    expect(output, isA<ToolResultJson>());
    expect(
      (output as ToolResultJson).value,
      <String, Object?>{'value': 42},
    );
  });
}
