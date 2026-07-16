import 'package:equatable/equatable.dart';

/// 归一化的结束原因分类。
enum FinishReasonType { stop, length, contentFilter, toolCalls, error, other }

/// 结束原因:归一化分类 + 保留 provider 原始字符串。
final class LanguageModelFinishReason extends Equatable {
  const LanguageModelFinishReason(this.unified, {this.raw});

  /// 归一化后的结束原因分类。
  final FinishReasonType unified;

  /// provider 返回的原始结束原因字符串(原样保留)。
  final String? raw;

  @override
  List<Object?> get props => <Object?>[unified, raw];
}
