/// 一等 reasoning 力度(升为标准调用参数)。
enum ReasoningEffort {
  providerDefault,
  none,
  minimal,
  low,
  medium,
  high,
  xhigh;

  /// wire 值:providerDefault → 'provider-default',其余变体与其 name 相同。
  String get wireValue => switch (this) {
        ReasoningEffort.providerDefault => 'provider-default',
        _ => name,
      };
}
