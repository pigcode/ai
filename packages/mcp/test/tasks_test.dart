import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:test/test.dart';

import 'support/initialized_pair.dart';

void main() {
  test('tool tasks support create, get, result, list, cancel, and status',
      () async {
    final tracker = McpTaskTracker();
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(
        tools: true,
        taskCancel: true,
        taskList: true,
        taskToolCall: true,
      ),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{'tools': <Object?>[]},
          'tools/call': (_) => <String, Object?>{'task': _workingTask},
          'tasks/get': (_) => _workingTask,
          'tasks/result': (_) => const <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{'type': 'text', 'text': 'complete'},
                ],
              },
          'tasks/list': (_) => <String, Object?>{
                'tasks': <Object?>[_workingTask],
              },
          'tasks/cancel': (_) => _cancelledTask,
        },
        notifications: <String, McpNotificationHandler>{
          'notifications/tasks/status': (invocation) {
            tracker.observeStatus(
              McpTaskStatusNotificationParams.fromJson(invocation.params),
            );
          },
        },
      ),
    );

    final created = await pair.client.callToolAsTask(
      McpCallToolRequestParams.fromJson(
        const <String, Object?>{
          'name': 'deferred',
          'task': <String, Object?>{'ttl': 60000},
        },
      ),
    );
    final tracked = tracker.register(created)!;
    expect(tracked.taskId, 'task::opaque');
    expect((await pair.client.getTask('task::opaque')).toJson(), _workingTask);
    expect(
      (await pair.client.getTaskResult('task::opaque')).toJson(),
      containsPair('content', isNotEmpty),
    );
    expect(
      (await pair.client.listTasks(mcpPageRequest())).toJson(),
      containsPair('tasks', isNotEmpty),
    );

    final cancelled = await pair.client.cancelTask('task::opaque');
    expect(tracker.observeCancelResult(cancelled), isTrue);
    expect((await tracked.terminal)['status'], 'cancelled');
    expect(tracked.status, 'cancelled');
    await pair.close();
    await tracker.close();
  });

  test('task augmentation requires its specific negotiated capability',
      () async {
    final pair = await createInitializedMcpPair(
      serverCapabilities: McpServerCapabilities(tools: true),
      serverHandlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          'tools/list': (_) => const <String, Object?>{'tools': <Object?>[]},
          'tools/call': (_) => const <String, Object?>{'content': <Object?>[]},
        },
      ),
    );

    await expectLater(
      pair.client.callToolAsTask(
        McpCallToolRequestParams.fromJson(
          const <String, Object?>{
            'name': 'deferred',
            'task': <String, Object?>{},
          },
        ),
      ),
      throwsA(
        isA<McpCapabilityException>().having(
          (error) => error.code,
          'code',
          'mcp_task_augmentation_not_negotiated',
        ),
      ),
    );
    await pair.close();
  });
}

const _workingTask = <String, Object?>{
  'taskId': 'task::opaque',
  'status': 'working',
  'createdAt': '2026-07-23T00:00:00Z',
  'lastUpdatedAt': '2026-07-23T00:00:00Z',
  'ttl': 60000,
};

const _cancelledTask = <String, Object?>{
  'taskId': 'task::opaque',
  'status': 'cancelled',
  'statusMessage': 'cancelled by caller',
  'createdAt': '2026-07-23T00:00:00Z',
  'lastUpdatedAt': '2026-07-23T00:00:01Z',
  'ttl': 60000,
};
