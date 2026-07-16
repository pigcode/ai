import 'package:equatable/equatable.dart';

import '../json_value/json.dart';

/// 输入侧用量。字段"存在但可空"→ Dart int?。
final class InputTokens extends Equatable {
  const InputTokens(
      {this.total, this.noCache, this.cacheRead, this.cacheWrite});

  /// 输入 token 总数。
  final int? total;

  /// 未命中缓存的输入 token 数。
  final int? noCache;

  /// 命中缓存读取的输入 token 数。
  final int? cacheRead;

  /// 写入缓存的输入 token 数。
  final int? cacheWrite;

  @override
  List<Object?> get props => <Object?>[total, noCache, cacheRead, cacheWrite];
}

/// 输出侧用量。字段"存在但可空"→ Dart int?。
final class OutputTokens extends Equatable {
  const OutputTokens({this.total, this.text, this.reasoning});

  /// 输出 token 总数。
  final int? total;

  /// 文本输出 token 数。
  final int? text;

  /// 推理输出 token 数。
  final int? reasoning;

  @override
  List<Object?> get props => <Object?>[total, text, reasoning];
}

/// 嵌套用量(无顶层 totalTokens)。raw 保留 provider 原始用量对象。
final class LanguageModelUsage extends Equatable {
  const LanguageModelUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.raw,
  });

  /// 输入侧用量。
  final InputTokens inputTokens;

  /// 输出侧用量。
  final OutputTokens outputTokens;

  /// provider 原始用量对象(原样保留)。
  final JsonObject? raw;

  @override
  List<Object?> get props => <Object?>[inputTokens, outputTokens, raw];
}
