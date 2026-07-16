import '../prompt/content_part.dart';
import '../prompt/model_message.dart';

/// Strategy for pruning reasoning content from assistant messages.
enum PruneReasoning {
  /// Remove reasoning content from all assistant messages.
  all,

  /// Remove assistant reasoning content before the last message.
  beforeLastMessage,

  /// Keep reasoning content.
  none,
}

/// Strategy for messages whose content is empty after pruning.
enum PruneEmptyMessages {
  /// Keep messages whose content is empty after pruning.
  keep,

  /// Remove messages whose content is empty after pruning.
  remove,
}

/// Rule for pruning tool calls, tool results, and tool approvals.
final class ToolCallPruning {
  ToolCallPruning._({
    required this.keepLastMessagesCount,
    Iterable<String>? tools,
  }) : tools = tools == null ? null : List<String>.unmodifiable(tools) {
    final count = keepLastMessagesCount;
    if (count != null && count < 1) {
      throw ArgumentError.value(
        count,
        'count',
        'must be greater than zero',
      );
    }
  }

  /// Prune all matching tool-related content.
  factory ToolCallPruning.all({Iterable<String>? tools}) {
    return ToolCallPruning._(
      keepLastMessagesCount: null,
      tools: tools,
    );
  }

  /// Prune matching tool-related content before the last message.
  factory ToolCallPruning.beforeLastMessage({Iterable<String>? tools}) {
    return ToolCallPruning.beforeLastMessages(1, tools: tools);
  }

  /// Prune matching tool-related content before the last [count] messages.
  factory ToolCallPruning.beforeLastMessages(
    int count, {
    Iterable<String>? tools,
  }) {
    return ToolCallPruning._(
      keepLastMessagesCount: count,
      tools: tools,
    );
  }

  /// Number of trailing messages to keep; `null` means no trailing window.
  final int? keepLastMessagesCount;

  /// Tool names to prune. `null` prunes all tools.
  final List<String>? tools;
}

/// Prunes reasoning, tool calls, tool results, and approval context.
List<ModelMessage> pruneMessages({
  required List<ModelMessage> messages,
  PruneReasoning reasoning = PruneReasoning.none,
  List<ToolCallPruning> toolCalls = const [],
  PruneEmptyMessages emptyMessages = PruneEmptyMessages.remove,
}) {
  var pruned = List<ModelMessage>.of(messages);

  if (reasoning == PruneReasoning.all ||
      reasoning == PruneReasoning.beforeLastMessage) {
    pruned = [
      for (var i = 0; i < pruned.length; i++)
        _pruneReasoningFromMessage(
          pruned[i],
          keepReasoning: reasoning == PruneReasoning.beforeLastMessage &&
              i == pruned.length - 1,
        ),
    ];
  }

  for (final rule in toolCalls) {
    pruned = _pruneToolCalls(pruned, rule);
  }

  if (emptyMessages == PruneEmptyMessages.remove) {
    pruned = [
      for (final message in pruned)
        if (_hasContent(message)) message,
    ];
  }

  return List<ModelMessage>.unmodifiable(pruned);
}

ModelMessage _pruneReasoningFromMessage(
  ModelMessage message, {
  required bool keepReasoning,
}) {
  if (keepReasoning || message is! AssistantModelMessage) {
    return message;
  }

  return AssistantModelMessage(
    [
      for (final part in message.content)
        if (part is! ReasoningPart && part is! ReasoningFilePart) part,
    ],
    providerOptions: message.providerOptions,
  );
}

List<ModelMessage> _pruneToolCalls(
  List<ModelMessage> messages,
  ToolCallPruning rule,
) {
  final keepLastMessagesCount = rule.keepLastMessagesCount;
  final keptToolCallIds = <String>{};
  final keptApprovalIds = <String>{};

  if (keepLastMessagesCount != null) {
    final candidateStart = messages.length - keepLastMessagesCount;
    final start = candidateStart < 0 ? 0 : candidateStart;
    for (final message in messages.skip(start)) {
      _scanToolParts(
        message,
        onToolCallId: keptToolCallIds.add,
        onApprovalId: keptApprovalIds.add,
      );
    }
  }

  final toolCallIdToToolName = <String, String>{};
  for (final message in messages) {
    _scanToolParts(
      message,
      onToolPart: (part) {
        if (part case ToolCallPart(:final toolCallId, :final toolName)) {
          toolCallIdToToolName[toolCallId] = toolName;
        } else if (part
            case ToolResultPart(:final toolCallId, :final toolName)) {
          toolCallIdToToolName[toolCallId] = toolName;
        }
      },
    );
  }

  final approvalIdToToolCallId = <String, String>{};
  final approvalIdToToolName = <String, String>{};
  for (final message in messages) {
    _scanToolParts(
      message,
      onToolPart: (part) {
        if (part
            case ToolApprovalRequestPart(
              :final approvalId,
              :final toolCallId,
            )) {
          approvalIdToToolCallId[approvalId] = toolCallId;
          final toolName = toolCallIdToToolName[toolCallId];
          if (toolName != null) {
            approvalIdToToolName[approvalId] = toolName;
          }
        }
      },
    );
  }

  // A kept approval response may be the only trailing part. Keep the original
  // tool call so the approved tool can still be executed on resume.
  for (final approvalId in keptApprovalIds) {
    final toolCallId = approvalIdToToolCallId[approvalId];
    if (toolCallId != null) {
      keptToolCallIds.add(toolCallId);
    }
  }

  return [
    for (var i = 0; i < messages.length; i++)
      _pruneToolPartsFromMessage(
        messages[i],
        rule: rule,
        keepMessage: keepLastMessagesCount != null &&
            i >= messages.length - keepLastMessagesCount,
        keptToolCallIds: keptToolCallIds,
        keptApprovalIds: keptApprovalIds,
        approvalIdToToolName: approvalIdToToolName,
      ),
  ];
}

ModelMessage _pruneToolPartsFromMessage(
  ModelMessage message, {
  required ToolCallPruning rule,
  required bool keepMessage,
  required Set<String> keptToolCallIds,
  required Set<String> keptApprovalIds,
  required Map<String, String> approvalIdToToolName,
}) {
  if (keepMessage) {
    return message;
  }

  if (message is AssistantModelMessage) {
    return AssistantModelMessage(
      [
        for (final part in message.content)
          if (_shouldKeepToolPart(
            part,
            rule: rule,
            keptToolCallIds: keptToolCallIds,
            keptApprovalIds: keptApprovalIds,
            approvalIdToToolName: approvalIdToToolName,
          ))
            part,
      ],
      providerOptions: message.providerOptions,
    );
  }

  if (message is ToolModelMessage) {
    return ToolModelMessage(
      [
        for (final part in message.content)
          if (_shouldKeepToolPart(
            part,
            rule: rule,
            keptToolCallIds: keptToolCallIds,
            keptApprovalIds: keptApprovalIds,
            approvalIdToToolName: approvalIdToToolName,
          ))
            part,
      ],
      providerOptions: message.providerOptions,
    );
  }

  return message;
}

bool _shouldKeepToolPart(
  Object part, {
  required ToolCallPruning rule,
  required Set<String> keptToolCallIds,
  required Set<String> keptApprovalIds,
  required Map<String, String> approvalIdToToolName,
}) {
  final toolCallId = _toolCallIdOf(part);
  if (toolCallId != null && keptToolCallIds.contains(toolCallId)) {
    return true;
  }

  final approvalId = _approvalIdOf(part);
  if (approvalId != null && keptApprovalIds.contains(approvalId)) {
    return true;
  }

  if (toolCallId == null && approvalId == null) {
    return true;
  }

  final partToolName = switch (part) {
    ToolCallPart(:final toolName) => toolName,
    ToolResultPart(:final toolName) => toolName,
    ToolApprovalRequestPart(:final approvalId) =>
      approvalIdToToolName[approvalId],
    ToolApprovalResponsePart(:final approvalId) =>
      approvalIdToToolName[approvalId],
    _ => null,
  };

  final tools = rule.tools;
  return tools != null && partToolName != null && !tools.contains(partToolName);
}

String? _toolCallIdOf(Object part) {
  return switch (part) {
    ToolCallPart(:final toolCallId) => toolCallId,
    ToolResultPart(:final toolCallId) => toolCallId,
    _ => null,
  };
}

String? _approvalIdOf(Object part) {
  return switch (part) {
    ToolApprovalRequestPart(:final approvalId) => approvalId,
    ToolApprovalResponsePart(:final approvalId) => approvalId,
    _ => null,
  };
}

void _scanToolParts(
  ModelMessage message, {
  void Function(Object part)? onToolPart,
  void Function(String toolCallId)? onToolCallId,
  void Function(String approvalId)? onApprovalId,
}) {
  final parts = switch (message) {
    AssistantModelMessage(:final content) => content,
    ToolModelMessage(:final content) => content,
    _ => const <Object>[],
  };

  for (final part in parts) {
    onToolPart?.call(part);
    final toolCallId = _toolCallIdOf(part);
    if (toolCallId != null) {
      onToolCallId?.call(toolCallId);
    }
    final approvalId = _approvalIdOf(part);
    if (approvalId != null) {
      onApprovalId?.call(approvalId);
    }
  }
}

bool _hasContent(ModelMessage message) {
  return switch (message) {
    SystemModelMessage(:final content) => content.isNotEmpty,
    UserModelMessage(:final content) => content.isNotEmpty,
    AssistantModelMessage(:final content) => content.isNotEmpty,
    ToolModelMessage(:final content) => content.isNotEmpty,
  };
}
