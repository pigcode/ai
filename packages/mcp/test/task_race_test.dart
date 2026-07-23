import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('cancelled terminal state wins over a late completed update', () async {
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 16);
    final tracker = McpTaskTracker(diagnostics: diagnostics);
    final task = tracker.register(
      McpCreateTaskResult.fromJson(
        const <String, Object?>{'task': _workingTask},
      ),
    )!;

    expect(
      tracker.observeCancelResult(
        McpCancelTaskResult.fromJson(_cancelledTask),
      ),
      isTrue,
    );
    final terminal = await task.terminal;
    expect(terminal['status'], 'cancelled');
    expect(
      tracker.observeStatus(
        McpTaskStatusNotificationParams.fromJson(_completedTask),
      ),
      isFalse,
    );
    expect(task.status, 'cancelled');
    expect(task.updates, hasLength(2));
    expect(
      diagnostics.entries.single.code,
      'mcp_late_task_update',
    );
    await tracker.close();
    await diagnostics.dispose();
  });

  test('unknown and duplicate task IDs diagnose without association', () {
    final diagnostics = BoundedProtocolDiagnostics(maxEntries: 16);
    final tracker = McpTaskTracker(diagnostics: diagnostics);
    expect(
      tracker.register(
        McpCreateTaskResult.fromJson(
          const <String, Object?>{'task': _workingTask},
        ),
      ),
      isNotNull,
    );
    expect(
      tracker.register(
        McpCreateTaskResult.fromJson(
          const <String, Object?>{'task': _workingTask},
        ),
      ),
      isNull,
    );
    expect(
      tracker.observeStatus(
        McpTaskStatusNotificationParams.fromJson(
          const <String, Object?>{
            'taskId': 'task::unknown',
            'status': 'completed',
            'createdAt': '2026-07-23T00:00:00Z',
            'lastUpdatedAt': '2026-07-23T00:00:02Z',
            'ttl': 60000,
          },
        ),
      ),
      isFalse,
    );
    expect(
      diagnostics.entries.map((entry) => entry.code),
      <String>['mcp_duplicate_task_id', 'mcp_unknown_task_id'],
    );
  });
}

const _workingTask = <String, Object?>{
  'taskId': 'task::race',
  'status': 'working',
  'createdAt': '2026-07-23T00:00:00Z',
  'lastUpdatedAt': '2026-07-23T00:00:00Z',
  'ttl': 60000,
};

const _cancelledTask = <String, Object?>{
  'taskId': 'task::race',
  'status': 'cancelled',
  'createdAt': '2026-07-23T00:00:00Z',
  'lastUpdatedAt': '2026-07-23T00:00:01Z',
  'ttl': 60000,
};

const _completedTask = <String, Object?>{
  'taskId': 'task::race',
  'status': 'completed',
  'createdAt': '2026-07-23T00:00:00Z',
  'lastUpdatedAt': '2026-07-23T00:00:02Z',
  'ttl': 60000,
};
