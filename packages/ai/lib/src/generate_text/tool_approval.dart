import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

import '../tool/tool.dart';

/// 工具审批状态类型，对齐上游 v7 当前 `toolApproval` 的四态。
enum ToolApprovalStatusType {
  /// 该工具调用不适用审批，按普通本地工具调用处理。
  notApplicable,

  /// 自动批准，记录审批请求/回复后继续执行工具。
  approved,

  /// 自动拒绝，记录审批请求/回复并产出 execution-denied 工具结果。
  denied,

  /// 需要调用方/用户审批，记录审批请求并停止当前工具循环。
  userApproval,
}

/// 工具审批状态。
final class ToolApprovalStatus with EquatableMixin {
  const ToolApprovalStatus._(this.type) : reason = null;

  /// 不适用审批。
  static const notApplicable = ToolApprovalStatus._(
    ToolApprovalStatusType.notApplicable,
  );

  /// 需要用户审批。
  static const userApproval = ToolApprovalStatus._(
    ToolApprovalStatusType.userApproval,
  );

  /// 自动批准。
  const ToolApprovalStatus.approved({this.reason})
      : type = ToolApprovalStatusType.approved;

  /// 自动拒绝。
  const ToolApprovalStatus.denied({this.reason})
      : type = ToolApprovalStatusType.denied;

  /// 状态类型。
  final ToolApprovalStatusType type;

  /// 可选的批准/拒绝原因。
  final String? reason;

  @override
  List<Object?> get props => [type, reason];
}

/// 动态工具审批函数。
typedef ToolApprovalFunction = FutureOr<ToolApprovalStatus?> Function(
  ToolApprovalOptions options,
);

/// 单个工具的动态审批函数。
typedef SingleToolApprovalFunction = FutureOr<ToolApprovalStatus?> Function(
  provider.JsonValue input,
  SingleToolApprovalOptions options,
);

/// 传给 [ToolApprovalFunction] 的上下文。
final class ToolApprovalOptions {
  const ToolApprovalOptions({
    required this.toolCall,
    required this.messages,
    required this.tools,
  });

  /// 当前待审批的工具调用。
  final provider.ToolCall toolCall;

  /// 当前模型调用看到的消息历史。
  final List<provider.LanguageModelMessage> messages;

  /// 当前步骤可用工具集。
  final ToolSet? tools;
}

/// 传给 [SingleToolApprovalFunction] 的上下文。
final class SingleToolApprovalOptions {
  const SingleToolApprovalOptions({
    required this.toolCallId,
    required this.messages,
  });

  /// 当前待审批工具调用的 ID。
  final String toolCallId;

  /// 当前模型调用看到的消息历史。
  final List<provider.LanguageModelMessage> messages;
}

/// 解析 `toolApproval` 配置。
///
/// 当前支持两种形态：
/// - `Map<String, ToolApprovalStatus | SingleToolApprovalFunction>`：
///   按工具名配置固定状态或动态函数。
/// - [ToolApprovalFunction]：按调用动态返回状态。
Future<ToolApprovalStatus> resolveToolApproval({
  required Object? toolApproval,
  required provider.ToolCall toolCall,
  required List<provider.LanguageModelMessage> messages,
  required ToolSet? tools,
}) async {
  if (toolApproval == null) {
    return ToolApprovalStatus.notApplicable;
  }
  if (toolApproval is ToolApprovalFunction) {
    return await toolApproval(ToolApprovalOptions(
          toolCall: toolCall,
          messages: messages,
          tools: tools,
        )) ??
        ToolApprovalStatus.notApplicable;
  }
  if (toolApproval is Map<String, Object?>) {
    final approval = toolApproval[toolCall.toolName];
    if (approval == null) {
      return ToolApprovalStatus.notApplicable;
    }
    if (approval is ToolApprovalStatus) {
      return approval;
    }
    if (approval is SingleToolApprovalFunction) {
      final input = jsonDecode(toolCall.input) as provider.JsonValue;
      return await approval(
            _cloneJsonValue(input),
            SingleToolApprovalOptions(
              toolCallId: toolCall.toolCallId,
              messages: messages,
            ),
          ) ??
          ToolApprovalStatus.notApplicable;
    }
    throw ArgumentError.value(
      approval,
      'toolApproval[${toolCall.toolName}]',
      'must be a ToolApprovalStatus or SingleToolApprovalFunction',
    );
  }
  throw ArgumentError.value(
    toolApproval,
    'toolApproval',
    'must be a Map<String, Object?> or ToolApprovalFunction',
  );
}

/// 当前审批配置是否需要先拥有可解析的工具输入。
bool toolApprovalRequiresInput({
  required Object? toolApproval,
  required provider.ToolCall toolCall,
}) {
  if (toolApproval is Map<String, Object?>) {
    return toolApproval[toolCall.toolName] is SingleToolApprovalFunction;
  }
  return false;
}

/// 当前审批配置是否可能在无需解析输入时阻断 repair。
bool toolApprovalMayBlockBeforeInput({
  required Object? toolApproval,
  required provider.ToolCall toolCall,
}) {
  if (toolApproval is Map<String, Object?>) {
    final approval = toolApproval[toolCall.toolName];
    return approval is ToolApprovalStatus &&
        approval.type == ToolApprovalStatusType.denied;
  }
  return false;
}

/// 用已解析的工具输入解析 `toolApproval` 配置。
///
/// 恢复历史审批时,消息里的 [provider.ToolCallPart.input] 已经是 JSON 值,
/// 不能再按 provider 输出侧的 stringified JSON 处理。
Future<ToolApprovalStatus> resolveToolApprovalFromInput({
  required Object? toolApproval,
  required String toolCallId,
  required String toolName,
  required provider.JsonValue input,
  provider.ToolCall? toolCall,
  bool? providerExecuted,
  provider.ProviderMetadata? providerMetadata,
  required List<provider.LanguageModelMessage> messages,
  required ToolSet? tools,
}) async {
  if (toolApproval == null) {
    return ToolApprovalStatus.notApplicable;
  }
  final approvalInput = _cloneJsonValue(input);
  if (toolApproval is ToolApprovalFunction) {
    return await toolApproval(ToolApprovalOptions(
          toolCall: toolCall ??
              provider.ToolCall(
                toolCallId: toolCallId,
                toolName: toolName,
                input: jsonEncode(approvalInput),
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
              ),
          messages: messages,
          tools: tools,
        )) ??
        ToolApprovalStatus.notApplicable;
  }
  if (toolApproval is Map<String, Object?>) {
    final approval = toolApproval[toolName];
    if (approval == null) {
      return ToolApprovalStatus.notApplicable;
    }
    if (approval is ToolApprovalStatus) {
      return approval;
    }
    if (approval is SingleToolApprovalFunction) {
      return await approval(
            approvalInput,
            SingleToolApprovalOptions(
              toolCallId: toolCallId,
              messages: messages,
            ),
          ) ??
          ToolApprovalStatus.notApplicable;
    }
    throw ArgumentError.value(
      approval,
      'toolApproval[$toolName]',
      'must be a ToolApprovalStatus or SingleToolApprovalFunction',
    );
  }
  throw ArgumentError.value(
    toolApproval,
    'toolApproval',
    'must be a Map<String, Object?> or ToolApprovalFunction',
  );
}

provider.JsonValue _cloneJsonValue(provider.JsonValue value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _cloneJsonValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[
      for (final item in value) _cloneJsonValue(item),
    ];
  }
  return value;
}

/// 一条从上一轮消息历史中收集到的审批回复及其匹配的工具调用。
final class CollectedToolApproval with EquatableMixin {
  CollectedToolApproval({
    required this.approvalRequest,
    required this.approvalResponse,
    required this.toolCall,
    required List<provider.LanguageModelMessage> messages,
  }) : messages = List<provider.LanguageModelMessage>.unmodifiable(messages);

  /// 审批请求。
  final provider.ToolApprovalRequestPart approvalRequest;

  /// 审批回复。
  final provider.ToolApprovalResponsePart approvalResponse;

  /// 被审批的工具调用。
  final provider.ToolCallPart toolCall;

  /// 触发该工具调用之前的对话消息(不含 system prompt)。
  final List<provider.LanguageModelMessage> messages;

  @override
  List<Object?> get props => [
        approvalRequest,
        approvalResponse,
        toolCall,
        messages,
      ];
}

/// 从上一轮消息历史中收集到的审批回复，按批准/拒绝分组。
final class CollectedToolApprovals with EquatableMixin {
  CollectedToolApprovals({
    List<CollectedToolApproval> approvedToolApprovals = const [],
    List<CollectedToolApproval> deniedToolApprovals = const [],
  })  : approvedToolApprovals =
            List<CollectedToolApproval>.unmodifiable(approvedToolApprovals),
        deniedToolApprovals =
            List<CollectedToolApproval>.unmodifiable(deniedToolApprovals);

  /// 空集合。
  const CollectedToolApprovals.empty()
      : approvedToolApprovals = const [],
        deniedToolApprovals = const [];

  /// 已批准、且尚未有工具结果的审批。
  final List<CollectedToolApproval> approvedToolApprovals;

  /// 已拒绝、且尚未有工具结果的审批。
  final List<CollectedToolApproval> deniedToolApprovals;

  /// 是否没有任何待处理审批。
  bool get isEmpty =>
      approvedToolApprovals.isEmpty && deniedToolApprovals.isEmpty;

  @override
  List<Object?> get props => [approvedToolApprovals, deniedToolApprovals];
}

/// 从消息历史中收集上一轮 tool message 携带的本地审批回复。
///
/// 仅检查最后一条消息是否为 [provider.ToolMessage]，并用之前 assistant
/// 消息中的 [provider.ToolApprovalRequestPart] / [provider.ToolCallPart]
/// 建立匹配关系；这与上游 `collectToolApprovals` 的本地审批闭环一致。
CollectedToolApprovals collectToolApprovals(
  List<provider.LanguageModelMessage> messages,
) {
  if (messages.isEmpty) {
    return const CollectedToolApprovals.empty();
  }
  final last = messages.last;
  if (last is! provider.ToolMessage) {
    return const CollectedToolApprovals.empty();
  }

  final toolCallsById = <String, provider.ToolCallPart>{};
  final messagesByToolCallId = <String, List<provider.LanguageModelMessage>>{};
  final approvalRequestsById = <String, provider.ToolApprovalRequestPart>{};

  for (var index = 0; index < messages.length - 1; index++) {
    final message = messages[index];
    if (message is! provider.AssistantMessage) {
      continue;
    }
    for (final part in message.content) {
      if (part is provider.ToolCallPart) {
        toolCallsById[part.toolCallId] = part;
        messagesByToolCallId[part.toolCallId] =
            List<provider.LanguageModelMessage>.unmodifiable(
          messages.take(index).where((m) => m is! provider.SystemMessage),
        );
      } else if (part is provider.ToolApprovalRequestPart) {
        approvalRequestsById[part.approvalId] = part;
      }
    }
  }

  final resolvedToolCallIds = <String>{
    for (final part in last.content)
      if (part is provider.ToolResultPart) part.toolCallId,
  };
  final approved = <CollectedToolApproval>[];
  final denied = <CollectedToolApproval>[];
  for (final part in last.content) {
    if (part is! provider.ToolApprovalResponsePart) {
      continue;
    }
    final request = approvalRequestsById[part.approvalId];
    if (request == null) {
      throw StateError(
        'Tool approval response references unknown approvalId: '
        '"${part.approvalId}"',
      );
    }
    final toolCall = toolCallsById[request.toolCallId];
    if (toolCall == null) {
      throw StateError(
        'Tool call "${request.toolCallId}" not found for approval request '
        '"${request.approvalId}".',
      );
    }
    if (resolvedToolCallIds.contains(toolCall.toolCallId)) {
      continue;
    }
    final approval = CollectedToolApproval(
      approvalRequest: request,
      approvalResponse: part,
      toolCall: toolCall,
      messages: messagesByToolCallId[toolCall.toolCallId] ?? const [],
    );
    if (part.approved) {
      approved.add(approval);
    } else {
      denied.add(approval);
    }
  }
  return CollectedToolApprovals(
    approvedToolApprovals: approved,
    deniedToolApprovals: denied,
  );
}
