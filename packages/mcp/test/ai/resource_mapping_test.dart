import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('maps text and blob resources while retaining URI metadata', () {
    final parts = mapMcpReadResourceResult(
      McpReadResourceResult.fromJson(
        const <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'uri': 'file:///workspace/README.md',
              'text': '# Readme',
              'mimeType': 'text/markdown',
              '_meta': <String, Object?>{'revision': 2},
            },
            <String, Object?>{
              'uri': 'file:///workspace/icon.png',
              'blob': 'AA==',
              'mimeType': 'image/png',
            },
          ],
        },
      ),
    );

    expect(parts, hasLength(2));
    final text = parts.first as FilePart;
    expect(text.data, const DataText('# Readme'));
    expect(text.filename, 'README.md');
    expect(text.providerOptions!['mcp']!['uri'], endsWith('README.md'));
    final image = parts.last as FilePart;
    expect(image.data, const DataBase64('AA=='));
  });

  test('caller can explicitly select plain text resource mapping', () {
    final parts = mapMcpReadResourceResult(
      McpReadResourceResult.fromJson(
        const <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'uri': 'file:///workspace/note.txt',
              'text': 'note',
            },
          ],
        },
      ),
      textMapping: McpTextResourceMapping.textPart,
    );

    expect(parts.single, isA<TextPart>());
    expect((parts.single as TextPart).text, 'note');
  });

  test('resource links are strict by default and never auto-read', () {
    final link = McpContentBlock.fromJson(
      const <String, Object?>{
        'type': 'resource_link',
        'name': 'private',
        'uri': 'file:///workspace/private.txt',
      },
    );

    expect(
      () => mapMcpPromptUserContent(link),
      throwsA(
        isA<McpMappingException>().having(
          (error) => error.code,
          'code',
          'mcp_resource_link_has_no_neutral_equivalent',
        ),
      ),
    );

    final preserved = mapMcpPromptUserContent(
      link,
      policy: McpLossyMappingPolicy.preserveWithMetadata,
    ) as TextPart;
    expect(preserved.text, contains('file:///workspace/private.txt'));
    expect(preserved.providerOptions!['mcp']!['dereferenced'], isFalse);
  });
}
