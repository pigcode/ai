import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:equatable/equatable.dart';

/// `copyWith` 的未传参哨兵,用于区分省略参数与显式传入 `null`。
const Object _unset = Object();

/// UI 消息角色。
enum UiMessageRole { system, user, assistant }

/// 流式 UI part 的完成状态。
enum UiPartState { streaming, done }

/// 工具 UI part 在输入、审批、输出生命周期中的状态。
enum UiToolState {
  /// 工具输入仍在流式拼接。
  inputStreaming,

  /// 工具输入已完整可用。
  inputAvailable,

  /// 工具调用等待用户或上层审批。
  approvalRequested,

  /// 工具审批已收到回复。
  approvalResponded,

  /// 工具输出已可用。
  outputAvailable,

  /// 工具执行产生错误文本。
  outputError,

  /// 工具输出因审批拒绝而不可用。
  outputDenied,
}

/// 面向 UI 层的不可变消息值对象。
final class UiMessage extends Equatable {
  /// 创建一条 UI 消息,并冻结 [parts] 列表快照。
  UiMessage({
    required this.id,
    required this.role,
    required List<UiMessagePart> parts,
    this.metadata,
  }) : parts = List<UiMessagePart>.unmodifiable(parts);

  /// 消息 id。
  final String id;

  /// 消息角色。
  final UiMessageRole role;

  /// 消息内容 part,构造时会被复制为不可变列表。
  final List<UiMessagePart> parts;

  /// UI 消息级元数据;显式 `null` 表示无元数据。
  final provider.JsonObject? metadata;

  /// 复制消息;未传字段保留旧值,显式传 `metadata: null` 会清空元数据。
  UiMessage copyWith({
    String? id,
    UiMessageRole? role,
    List<UiMessagePart>? parts,
    Object? metadata = _unset,
  }) {
    return UiMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      metadata: identical(metadata, _unset)
          ? this.metadata
          : metadata as provider.JsonObject?,
    );
  }

  @override
  List<Object?> get props => <Object?>[id, role, parts, metadata];
}

/// UI 消息 part 的封闭基类。
sealed class UiMessagePart extends Equatable {
  const UiMessagePart();
}

/// UI 文本 part。
final class TextUiPart extends UiMessagePart {
  const TextUiPart(
    this.text, {
    this.state = UiPartState.done,
    this.providerMetadata,
  });

  /// 文本内容。
  final String text;

  /// 文本是否仍在流式更新。
  final UiPartState state;

  /// provider 侧透传元数据,外层键为 provider 名。
  final provider.ProviderMetadata? providerMetadata;

  /// 返回追加 [delta] 后的新文本 part。
  TextUiPart append(
    String delta, {
    provider.ProviderMetadata? providerMetadata,
  }) {
    return TextUiPart(
      text + delta,
      state: state,
      providerMetadata: providerMetadata ?? this.providerMetadata,
    );
  }

  /// 返回标记为完成状态的新文本 part。
  TextUiPart markDone({provider.ProviderMetadata? providerMetadata}) {
    return TextUiPart(
      text,
      state: UiPartState.done,
      providerMetadata: providerMetadata ?? this.providerMetadata,
    );
  }

  @override
  List<Object?> get props => <Object?>[text, state, providerMetadata];
}

/// UI 推理文本 part。
final class ReasoningUiPart extends UiMessagePart {
  const ReasoningUiPart(
    this.text, {
    this.state = UiPartState.done,
    this.providerMetadata,
  });

  /// 推理文本内容。
  final String text;

  /// 推理文本是否仍在流式更新。
  final UiPartState state;

  /// provider 侧透传元数据,外层键为 provider 名。
  final provider.ProviderMetadata? providerMetadata;

  /// 返回追加 [delta] 后的新推理 part。
  ReasoningUiPart append(
    String delta, {
    provider.ProviderMetadata? providerMetadata,
  }) {
    return ReasoningUiPart(
      text + delta,
      state: state,
      providerMetadata: providerMetadata ?? this.providerMetadata,
    );
  }

  /// 返回标记为完成状态的新推理 part。
  ReasoningUiPart markDone({provider.ProviderMetadata? providerMetadata}) {
    return ReasoningUiPart(
      text,
      state: UiPartState.done,
      providerMetadata: providerMetadata ?? this.providerMetadata,
    );
  }

  @override
  List<Object?> get props => <Object?>[text, state, providerMetadata];
}

/// UI 文件 part。
final class FileUiPart extends UiMessagePart {
  const FileUiPart({
    required this.url,
    required this.mediaType,
    this.filename,
    this.providerReference,
    this.providerMetadata,
  });

  /// 文件 URL。
  final Uri url;

  /// 文件 MIME 类型。
  final String mediaType;

  /// 可选文件名。
  final String? filename;

  /// provider 侧文件引用,外层键为 provider 名。
  final provider.ProviderReference? providerReference;

  /// provider 侧透传元数据,外层键为 provider 名。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[
        url,
        mediaType,
        filename,
        providerReference,
        providerMetadata,
      ];
}

/// UI 推理文件 part。
final class ReasoningFileUiPart extends UiMessagePart {
  const ReasoningFileUiPart({
    required this.url,
    required this.mediaType,
    this.providerMetadata,
  });

  /// 推理文件 URL。
  final Uri url;

  /// 推理文件 MIME 类型。
  final String mediaType;

  /// provider 侧透传元数据,外层键为 provider 名。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[url, mediaType, providerMetadata];
}

/// provider 自定义 UI part。
final class CustomUiPart extends UiMessagePart {
  const CustomUiPart(this.kind, {this.providerMetadata});

  /// 自定义 part 种类,通常形如 `provider.kind`。
  final String kind;

  /// provider 侧透传元数据,外层键为 provider 名。
  final provider.ProviderMetadata? providerMetadata;

  @override
  List<Object?> get props => <Object?>[kind, providerMetadata];
}

/// UI 数据 part,用于承载自定义 JSON payload。
final class DataUiPart extends UiMessagePart {
  const DataUiPart({required this.type, required this.data, this.id});

  /// 数据 part 类型,通常形如 `data-weather`。
  final String type;

  /// 可选数据 part id。
  final String? id;

  /// JSON payload;可为 `null`、标量、数组或对象。
  final provider.JsonValue data;

  @override
  List<Object?> get props => <Object?>[type, id, data];
}

/// UI 工具审批回复。
final class UiToolApproval extends Equatable {
  const UiToolApproval({
    required this.approvalId,
    this.approved,
    this.reason,
  });

  /// 审批请求 id。
  final String approvalId;

  /// 审批结果;`null` 表示尚未给出批准或拒绝。
  final bool? approved;

  /// 可选审批原因。
  final String? reason;

  /// 复制审批回复;显式传 `null` 可清空 [approved] 或 [reason]。
  UiToolApproval copyWith({
    String? approvalId,
    Object? approved = _unset,
    Object? reason = _unset,
  }) {
    return UiToolApproval(
      approvalId: approvalId ?? this.approvalId,
      approved: identical(approved, _unset) ? this.approved : approved as bool?,
      reason: identical(reason, _unset) ? this.reason : reason as String?,
    );
  }

  @override
  List<Object?> get props => <Object?>[approvalId, approved, reason];
}

/// UI 工具调用 part。
final class ToolUiPart extends UiMessagePart {
  const ToolUiPart({
    required this.toolCallId,
    required this.toolName,
    required this.state,
    this.input,
    this.output,
    this.errorText,
    this.providerExecuted,
    this.preliminary,
    this.callProviderMetadata,
    this.resultProviderMetadata,
    this.approval,
  });

  /// 工具调用 id。
  final String toolCallId;

  /// 工具名称。
  final String toolName;

  /// 工具调用生命周期状态。
  final UiToolState state;

  /// 工具输入 JSON payload;`null` 表示尚无输入或已显式清空。
  final provider.JsonValue input;

  /// 工具输出 JSON payload;`null` 表示尚无输出或已显式清空。
  final provider.JsonValue output;

  /// 工具错误文本;`null` 表示无错误文本。
  final String? errorText;

  /// 是否由 provider 侧执行;`null` 表示未知或不适用。
  final bool? providerExecuted;

  /// 为真表示当前输出只是可被后续结果替换的部分结果。
  final bool? preliminary;

  /// 工具调用阶段的 provider 元数据,外层键为 provider 名。
  final provider.ProviderMetadata? callProviderMetadata;

  /// 工具结果阶段的 provider 元数据,外层键为 provider 名。
  final provider.ProviderMetadata? resultProviderMetadata;

  /// 可选工具审批回复。
  final UiToolApproval? approval;

  /// 复制工具 part。
  ///
  /// [input]、[output]、[errorText] 仅在对应 `set*` 参数为 `true` 时更新;
  /// 其余可空字段显式传 `null` 会清空。
  ToolUiPart copyWith({
    String? toolCallId,
    String? toolName,
    UiToolState? state,
    provider.JsonValue input,
    provider.JsonValue output,
    String? errorText,
    bool setInput = false,
    bool setOutput = false,
    bool setErrorText = false,
    Object? providerExecuted = _unset,
    Object? preliminary = _unset,
    Object? callProviderMetadata = _unset,
    Object? resultProviderMetadata = _unset,
    Object? approval = _unset,
  }) {
    return ToolUiPart(
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      state: state ?? this.state,
      input: setInput ? input : this.input,
      output: setOutput ? output : this.output,
      errorText: setErrorText ? errorText : this.errorText,
      providerExecuted: identical(providerExecuted, _unset)
          ? this.providerExecuted
          : providerExecuted as bool?,
      preliminary: identical(preliminary, _unset)
          ? this.preliminary
          : preliminary as bool?,
      callProviderMetadata: identical(callProviderMetadata, _unset)
          ? this.callProviderMetadata
          : callProviderMetadata as provider.ProviderMetadata?,
      resultProviderMetadata: identical(resultProviderMetadata, _unset)
          ? this.resultProviderMetadata
          : resultProviderMetadata as provider.ProviderMetadata?,
      approval: identical(approval, _unset)
          ? this.approval
          : approval as UiToolApproval?,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        toolCallId,
        toolName,
        state,
        input,
        output,
        errorText,
        providerExecuted,
        preliminary,
        callProviderMetadata,
        resultProviderMetadata,
        approval,
      ];
}

/// UI 步骤开始 marker part。
final class StepStartUiPart extends UiMessagePart {
  const StepStartUiPart();

  @override
  List<Object?> get props => const <Object?>[];
}
