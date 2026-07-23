import 'dart:async';

import 'package:pigcode_ai/pigcode_ai.dart' hide JsonObject, JsonValue;
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../client.dart';
import '../generated/mcp_models.g.dart';
import '../tasks.dart';
import '../tools.dart';
import 'content_mapping.dart';
import 'mapping_policy.dart';

/// Maps validated MCP tool definitions to executable neutral AI tools.
final class McpToolAdapter {
  const McpToolAdapter(
    this.client, {
    this.namePolicy = const McpToolNamePolicy.exact(),
    this.requestOptionalTasks = false,
  });

  final McpClient client;
  final McpToolNamePolicy namePolicy;

  /// Requests task augmentation for tools declaring optional task support.
  final bool requestOptionalTasks;

  ToolSet mapTools(
    Iterable<McpTool> tools, {
    ToolSet existing = const <String, Tool>{},
  }) {
    final mapped = <String, Tool>{...existing};
    for (final definition in tools) {
      final raw = definition.toJson()! as JsonObject;
      final mcpName = raw['name']! as String;
      final exposedName = namePolicy.map(mcpName);
      if (mapped.containsKey(exposedName)) {
        throw McpToolNameCollisionException(exposedName);
      }
      final execution = raw['execution'] as JsonObject?;
      final taskSupport = execution?['taskSupport'] as String? ?? 'forbidden';
      final useTask = taskSupport == 'required' ||
          (taskSupport == 'optional' && requestOptionalTasks);
      mapped[exposedName] = Tool(
        inputSchema: JsonSchema(raw['inputSchema']! as JsonObject),
        description: raw['description'] as String?,
        providerOptions: mcpProviderOptions(<String, Object?>{
          'name': mcpName,
          if (raw['title'] != null) 'title': raw['title'],
          if (raw['annotations'] != null) 'annotations': raw['annotations'],
          if (raw['execution'] != null) 'execution': raw['execution'],
          if (raw['outputSchema'] != null) 'outputSchema': raw['outputSchema'],
          if (raw['_meta'] != null) '_meta': raw['_meta'],
        }),
        execute: (input, options) => _execute(
          mcpName,
          input,
          options,
          useTask: useTask,
        ),
        toModelOutput: (_, output) => switch (output) {
          McpCallToolResult result => mapMcpToolResult(result),
          McpDeferredToolResult deferred => ToolResultJson(
              deferred.toJson(),
              providerOptions: mcpProviderOptions(<String, Object?>{
                'deferred': true,
                'task': deferred.toJson(),
              }),
            ),
          _ => throw McpMappingException(
              'mcp_unexpected_tool_output',
              'Mapped MCP tool returned an unexpected output type.',
              mcpType: output.runtimeType.toString(),
            ),
        },
      );
    }
    return Map<String, Tool>.unmodifiable(mapped);
  }

  Future<Object> _execute(
    String mcpName,
    JsonValue input,
    ToolExecuteOptions options, {
    required bool useTask,
  }) async {
    if (input is! JsonObject) {
      throw const McpMappingException(
        'mcp_tool_arguments_not_object',
        'MCP tool arguments must be a JSON object.',
      );
    }
    final cancellation = _bridgeCancellation(options.cancellation);
    try {
      final params = McpCallToolRequestParams.fromJson(<String, Object?>{
        'name': mcpName,
        'arguments': input,
        if (useTask) 'task': <String, Object?>{},
      });
      if (useTask) {
        return McpDeferredToolResult(
          client: client,
          created: await client.callToolAsTask(
            params,
            cancellation: cancellation,
          ),
        );
      }
      return await client.callTool(params, cancellation: cancellation);
    } on McpMappingException {
      rethrow;
    } on Object catch (error) {
      throw McpToolExecutionException(
        toolName: mcpName,
        cause: error,
      );
    }
  }
}

/// Typed handle returned when an MCP tool uses task-augmented execution.
final class McpDeferredToolResult {
  const McpDeferredToolResult({
    required this.client,
    required this.created,
  });

  final McpClient client;
  final McpCreateTaskResult created;

  JsonObject get task =>
      (created.toJson()! as JsonObject)['task']! as JsonObject;
  String get taskId => task['taskId']! as String;

  JsonObject toJson() => task;

  Future<McpGetTaskResult> getStatus({
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) =>
      client.getTask(
        taskId,
        cancellation: cancellation,
        timeout: timeout,
      );

  Future<McpCallToolResult> getResult({
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) async =>
      McpCallToolResult.fromJson(
        (await client.getTaskResult(
          taskId,
          cancellation: cancellation,
          timeout: timeout,
        ))
            .toJson(),
      );

  Future<McpCancelTaskResult> cancel({
    ProtocolCancellationSignal? cancellation,
    Duration? timeout,
  }) =>
      client.cancelTask(
        taskId,
        cancellation: cancellation,
        timeout: timeout,
      );

  @override
  String toString() => 'McpDeferredToolResult(taskId: $taskId)';
}

ProtocolCancellationSignal? _bridgeCancellation(
  CancellationSignal? cancellation,
) {
  if (cancellation == null) return null;
  final source = ProtocolCancellationSource();
  if (cancellation.isCancelled) {
    source.cancel(cancellation.reason);
  } else {
    unawaited(
      cancellation.whenCancelled.then(
        (_) => source.cancel(cancellation.reason),
      ),
    );
  }
  return source.signal;
}
