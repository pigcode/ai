import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('integer and string progress tokens remain distinct and opaque',
      () async {
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 16);
    final tracker = McpProgressTracker(diagnostics: diagnostics);
    final integer = tracker.register(McpProgressToken.fromJson(1))!;
    final string = tracker.register(McpProgressToken.fromJson('1'))!;

    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{'progressToken': 1, 'progress': 1},
        ),
      ),
      isTrue,
    );
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{'progressToken': '1', 'progress': 5},
        ),
      ),
      isTrue,
    );

    expect(integer.events.single.progress, 1);
    expect(string.events.single.progress, 5);
    expect(integer.token, isA<int>());
    expect(string.token, isA<String>());
    expect(diagnostics.entries, isEmpty);
    await tracker.complete(McpProgressToken.fromJson(1));
    await tracker.complete(McpProgressToken.fromJson('1'));
    await diagnostics.dispose();
  });

  test('unknown, duplicate, decreasing, and late progress only diagnose',
      () async {
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 16);
    final tracker = McpProgressTracker(diagnostics: diagnostics);
    final token = McpProgressToken.fromJson('opaque::token');
    final operation = tracker.register(token)!;

    expect(tracker.register(token), isNull);
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{
            'progressToken': 'unknown',
            'progress': 1,
          },
        ),
      ),
      isFalse,
    );
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{
            'progressToken': 'opaque::token',
            'progress': 2,
          },
        ),
      ),
      isTrue,
    );
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{
            'progressToken': 'opaque::token',
            'progress': 2,
          },
        ),
      ),
      isFalse,
    );
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{
            'progressToken': 'opaque::token',
            'progress': 1,
          },
        ),
      ),
      isFalse,
    );
    await tracker.complete(token);
    expect(
      tracker.handle(
        McpProgressNotificationParams.fromJson(
          const <String, Object?>{
            'progressToken': 'opaque::token',
            'progress': 3,
          },
        ),
      ),
      isFalse,
    );

    expect(operation.events, hasLength(1));
    expect(
      diagnostics.entries.map((entry) => entry.code),
      containsAll(<String>[
        'mcp_duplicate_progress_token',
        'mcp_unknown_progress_token',
        'mcp_duplicate_progress',
        'mcp_non_monotonic_progress',
        'mcp_late_progress_token',
      ]),
    );
    await diagnostics.dispose();
  });
}
