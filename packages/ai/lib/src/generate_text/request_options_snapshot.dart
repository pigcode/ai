import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../middleware/default_settings_merge.dart';
import 'context.dart';

Map<String, String>? snapshotHeaders(Map<String, String>? headers) {
  return headers == null ? null : Map<String, String>.unmodifiable(headers);
}

RuntimeContext snapshotRuntimeContext(RuntimeContext? context) {
  return context == null
      ? const <String, Object?>{}
      : Map<String, Object?>.unmodifiable(
          context.map(
            (key, value) => MapEntry(key, _deepUnmodifiableContextValue(value)),
          ),
        );
}

ToolsContext snapshotToolsContext(ToolsContext? context) {
  return context == null
      ? const <String, Object?>{}
      : Map<String, Object?>.unmodifiable(
          context.map(
            (key, value) => MapEntry(key, _deepUnmodifiableContextValue(value)),
          ),
        );
}

provider.ProviderOptions? snapshotProviderOptions(
  provider.ProviderOptions? options,
) {
  if (options == null) {
    return null;
  }
  return Map<String, provider.JsonObject>.unmodifiable(
    options.map(
      (key, value) => MapEntry(key, _deepUnmodifiableJsonObject(value)),
    ),
  );
}

/// 深合并两份 providerOptions(签名不变,语义升级为递归深合并,对齐上游
/// prepareStep 合并所用 mergeObjects(:23-84):嵌套 JsonObject 递归合并、
/// List 与原始值/显式 null 替换、override 缺席键保 base。实现直接复用
/// default_settings_merge 的 mergeProviderOptionsDeep(语义已逐点对齐,
/// 含显式 null 走替换分支);返回保持深不可变 snapshot。
provider.ProviderOptions? mergeProviderOptions(
  provider.ProviderOptions? base,
  provider.ProviderOptions? override,
) =>
    mergeProviderOptionsDeep(base, override);

provider.JsonObject _deepUnmodifiableJsonObject(provider.JsonObject value) {
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _deepUnmodifiableJsonValue(value))),
  );
}

Object? _deepUnmodifiableJsonValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepUnmodifiableJsonObject(value);
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, value) =>
            MapEntry(key as String, _deepUnmodifiableJsonValue(value)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiableJsonValue));
  }
  return value;
}

/// 任意值的深不可变视图:Map/List 递归包 unmodifiable,其余叶子按引用透传
/// (与 DataContent 二进制叶子的既有约定一致:透传、约定不可变)。供 telemetry
/// dispatcher 等需要"观察者改不动共享结构"的场景复用。
Object? deepUnmodifiableValue(Object? value) =>
    _deepUnmodifiableContextValue(value);

Object? _deepUnmodifiableContextValue(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, value) => MapEntry(key, _deepUnmodifiableContextValue(value)),
      ),
    );
  }
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(
      value.map(
        (key, value) => MapEntry(key, _deepUnmodifiableContextValue(value)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiableContextValue));
  }
  return value;
}
