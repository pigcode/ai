import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'client.dart';
import 'generated/mcp_models.g.dart';
import 'server.dart';

extension McpClientTasks on McpClient {
  Future<McpGetTaskResult> getTask(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpGetTaskResult.fromJson(
        await requestServer(
          'tasks/get',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpGetTaskPayloadResult> getTaskResult(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpGetTaskPayloadResult.fromJson(
        await requestServer(
          'tasks/result',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCancelTaskResult> cancelTask(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCancelTaskResult.fromJson(
        await requestServer(
          'tasks/cancel',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpListTasksResult> listTasks(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListTasksResult.fromJson(
        await requestServer(
          'tasks/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCreateTaskResult> callToolAsTask(
    McpCallToolRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCreateTaskResult.fromJson(
        await requestServer(
          'tools/call',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<void> notifyTaskStatus(McpTaskStatusNotificationParams params) =>
      notifyServer('notifications/tasks/status', params.toJson());
}

extension McpServerTasks on McpServer {
  Future<McpGetTaskResult> getTask(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpGetTaskResult.fromJson(
        await requestClient(
          'tasks/get',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpGetTaskPayloadResult> getTaskResult(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpGetTaskPayloadResult.fromJson(
        await requestClient(
          'tasks/result',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCancelTaskResult> cancelTask(
    String taskId, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCancelTaskResult.fromJson(
        await requestClient(
          'tasks/cancel',
          <String, Object?>{'taskId': taskId},
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpListTasksResult> listTasks(
    McpPaginatedRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpListTasksResult.fromJson(
        await requestClient(
          'tasks/list',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCreateTaskResult> createMessageAsTask(
    McpCreateMessageRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCreateTaskResult.fromJson(
        await requestClient(
          'sampling/createMessage',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<McpCreateTaskResult> elicitAsTask(
    McpElicitRequestParams params, {
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCreateTaskResult.fromJson(
        await requestClient(
          'elicitation/create',
          params.toJson(),
          cancellation: cancellation,
          timeout: timeout,
        ),
      );

  Future<void> notifyTaskStatus(McpTaskStatusNotificationParams params) =>
      notifyClient('notifications/tasks/status', params.toJson());
}

/// A task whose terminal state can be completed exactly once.
final class McpTrackedTask {
  McpTrackedTask._(JsonObject initial)
      : taskId = initial['taskId']! as String,
        _latest = initial {
    _updates.add(initial);
    if (_isTerminalStatus(status)) {
      _terminal.complete(initial);
    }
  }

  final String taskId;
  final StreamController<JsonObject> _changes =
      StreamController<JsonObject>.broadcast(sync: true);
  final Completer<JsonObject> _terminal = Completer<JsonObject>();
  final List<JsonObject> _updates = <JsonObject>[];
  JsonObject _latest;

  JsonObject get latest => _latest;
  String get status => _latest['status']! as String;
  bool get isTerminal => _terminal.isCompleted;
  Future<JsonObject> get terminal => _terminal.future;
  Stream<JsonObject> get changes => _changes.stream;
  List<JsonObject> get updates => List<JsonObject>.unmodifiable(_updates);

  void _update(JsonObject value) {
    _latest = value;
    _updates.add(value);
    _changes.add(value);
    if (_isTerminalStatus(status) && !_terminal.isCompleted) {
      _terminal.complete(value);
    }
  }

  Future<void> close() => _changes.close();
}

/// Tracks task IDs independently from request IDs and progress tokens.
final class McpTaskTracker {
  McpTaskTracker({
    ProtocolDiagnosticSink? diagnostics,
    this.maxTasks = 256,
  }) : diagnostics =
            diagnostics ?? BoundedProtocolDiagnostics(maxEntries: maxTasks) {
    if (maxTasks <= 0) {
      throw ArgumentError.value(maxTasks, 'maxTasks', 'Must be positive.');
    }
  }

  final ProtocolDiagnosticSink diagnostics;
  final int maxTasks;
  final Map<String, McpTrackedTask> _tasks = <String, McpTrackedTask>{};

  List<McpTrackedTask> get tasks =>
      List<McpTrackedTask>.unmodifiable(_tasks.values);

  McpTrackedTask? operator [](String taskId) => _tasks[taskId];

  McpTrackedTask? register(McpCreateTaskResult result) {
    final envelope = result.toJson()! as Map<String, Object?>;
    return registerTask(
      McpTask.fromJson(envelope['task']),
    );
  }

  McpTrackedTask? registerTask(McpTask task) {
    final snapshot = task.toJson()! as JsonObject;
    final taskId = snapshot['taskId']! as String;
    if (_tasks.containsKey(taskId)) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_duplicate_task_id',
          message: 'Ignored duplicate MCP task identifier.',
          method: 'notifications/tasks/status',
          details: <String, Object?>{'taskId': taskId},
        ),
      );
      return null;
    }
    if (_tasks.length >= maxTasks) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_task_limit',
          message: 'Ignored MCP task because the tracker is full.',
          details: <String, Object?>{'taskId': taskId},
        ),
      );
      return null;
    }
    final tracked = McpTrackedTask._(snapshot);
    _tasks[taskId] = tracked;
    return tracked;
  }

  bool observeStatus(McpTaskStatusNotificationParams params) =>
      _observe(McpTask.fromJson(params.toJson()));

  bool observeGetResult(McpGetTaskResult result) =>
      _observe(McpTask.fromJson(result.toJson()));

  bool observeCancelResult(McpCancelTaskResult result) =>
      _observe(McpTask.fromJson(result.toJson()));

  bool _observe(McpTask task) {
    final snapshot = task.toJson()! as JsonObject;
    final taskId = snapshot['taskId']! as String;
    final tracked = _tasks[taskId];
    if (tracked == null) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_unknown_task_id',
          message: 'Ignored MCP update for an unknown task identifier.',
          method: 'notifications/tasks/status',
          details: <String, Object?>{'taskId': taskId},
        ),
      );
      return false;
    }
    if (tracked.isTerminal) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_late_task_update',
          message: 'Ignored MCP update after the task became terminal.',
          method: 'notifications/tasks/status',
          details: <String, Object?>{
            'taskId': taskId,
            'terminalStatus': tracked.status,
            'lateStatus': snapshot['status']!,
          },
        ),
      );
      return false;
    }
    if (tracked.status == snapshot['status']) {
      _diagnose(
        ProtocolDiagnostic(
          code: 'mcp_duplicate_task_status',
          message: 'Ignored duplicate MCP task status.',
          method: 'notifications/tasks/status',
          details: <String, Object?>{
            'taskId': taskId,
            'status': tracked.status,
          },
        ),
      );
      return false;
    }
    tracked._update(snapshot);
    return true;
  }

  Future<void> close() async {
    for (final task in _tasks.values) {
      await task.close();
    }
  }

  void _diagnose(ProtocolDiagnostic diagnostic) {
    try {
      diagnostics.add(diagnostic);
    } on Object {
      // Caller diagnostics must not change task state.
    }
  }
}

bool _isTerminalStatus(String status) =>
    status == 'cancelled' || status == 'completed' || status == 'failed';
