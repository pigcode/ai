import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('pagination cursors remain opaque across result and next request', () {
    const cursor = 'opaque::+/=?&%E4%B8%AD';
    final page = McpPage<McpListToolsResult>(
      McpListToolsResult.fromJson(
        const <String, Object?>{
          'tools': <Object?>[],
          'nextCursor': cursor,
        },
      ),
    );

    expect(page.hasNext, isTrue);
    expect(page.nextCursor, cursor);
    expect(
      (page.nextRequest().toJson()! as Map<String, Object?>)['cursor'],
      cursor,
    );
  });

  test('last page cannot synthesize a continuation request', () {
    final page = McpPage<McpListResourcesResult>(
      McpListResourcesResult.fromJson(
        const <String, Object?>{'resources': <Object?>[]},
      ),
    );

    expect(page.hasNext, isFalse);
    expect(page.nextCursor, isNull);
    expect(page.nextRequest, throwsStateError);
  });
}
