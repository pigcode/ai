import 'package:equatable/equatable.dart';

import 'telemetry.dart';

/// per-call telemetry 配置。
///
/// 值相等仅比较配置标量([props]);[integrations] 是身份对象列表,不纳入值相等。
final class TelemetrySettings extends Equatable {
  /// 创建 telemetry 配置。
  const TelemetrySettings({
    this.isEnabled,
    this.recordInputs,
    this.recordOutputs,
    this.functionId,
    this.includeRuntimeContext,
    this.includeToolsContext,
    this.integrations = const [],
  });

  /// 是否启用。为 `false` 时 dispatcher 全部 no-op;为 `null`/`true` 时,若有生效
  /// 集成则启用。
  final bool? isEnabled;

  /// 是否记录 input(默认视为 `true`,在 dispatcher 层解析)。可空以区分"未设置"。
  final bool? recordInputs;

  /// 是否记录 output(默认视为 `true`)。可空以区分"未设置"。
  final bool? recordOutputs;

  /// 分组标识,随 [TelemetryMetadata] 注入每个回调。
  final String? functionId;

  /// runtime context 顶层键白名单(默认全排除,显式 `true` 才带)。
  final Map<String, bool>? includeRuntimeContext;

  /// 每工具的 context 键白名单(工具名 → 键 → 是否包含);仅对
  /// `Map<String, Object?>` 型工具 context 生效。
  final Map<String, Map<String, bool>>? includeToolsContext;

  /// per-call 集成;非空时优先于全局注册的集成。
  final List<Telemetry> integrations;

  @override
  List<Object?> get props => [
        isEnabled,
        recordInputs,
        recordOutputs,
        functionId,
        includeRuntimeContext,
        includeToolsContext,
      ];
}
