import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Anthropic 每请求允许的 cache breakpoint 上限(上游
/// get-cache-control.ts:8,`MAX_CACHE_BREAKPOINTS = 4`)。
const int _maxCacheBreakpoints = 4;

/// cache_control breakpoint 校验器:跨整个 prompt 共享计数,超过 4 个
/// breakpoint 时忽略后续并产生 warning(对照上游 get-cache-control.ts:25-66)。
///
/// [warnings] 由 convert 入口(convert_messages.dart)在返回前合并进
/// `AnthropicPromptResult.warnings` 单通道,模型层不单独读取。
final class CacheControlValidator {
  /// 已消耗的 breakpoint 计数;超限后继续递增,用于 warning 里的 found 数字
  /// (spec 疑点 #9 = 照上游)。
  int _breakpointCount = 0;

  /// 校验过程中累积的告警。
  final List<Warning> warnings = <Warning>[];

  /// 从 [providerOptions] 的 canonical `'anthropic'` key 下读取
  /// `cacheControl`(优先)或 `cache_control` 字段并原样透传
  /// (不做本地校验,由 Anthropic API 侧校验;上游 :15-22)。
  ///
  /// - 值为空 → 返回 null,不占计数(:35-37);
  /// - [canCache] 为 false → 返回 null 并追加 warning,不占计数(:40-47);
  /// - 计数超过 4 → 返回 null 并追加超限 warning(:50-58)。
  ///
  /// [contextType] 用于 warning 文案,如 `'thinking block'`。
  Object? getCacheControl(
    ProviderOptions? providerOptions, {
    required String contextType,
    required bool canCache,
  }) {
    final anthropicOptions = providerOptions?['anthropic'];
    final cacheControl =
        anthropicOptions?['cacheControl'] ?? anthropicOptions?['cache_control'];
    if (cacheControl == null) {
      return null;
    }

    if (!canCache) {
      warnings.add(
        UnsupportedWarning(
          'cache_control on non-cacheable context',
          details: 'cache_control cannot be set on $contextType. '
              'It will be ignored.',
        ),
      );
      return null;
    }

    _breakpointCount++;
    if (_breakpointCount > _maxCacheBreakpoints) {
      warnings.add(
        UnsupportedWarning(
          'cacheControl breakpoint limit',
          details: 'Maximum $_maxCacheBreakpoints cache breakpoints exceeded '
              '(found $_breakpointCount). This breakpoint will be ignored.',
        ),
      );
      return null;
    }

    return cacheControl;
  }
}
