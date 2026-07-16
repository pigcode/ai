import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 依据既往各步的 providerMetadata 推导应回传的 Anthropic container id。
///
/// 语义照上游(:19-37):倒序扫描 [stepProviderMetadata],找最近一步的
/// `['anthropic']['container']['id']` 非空 `String`(空串按 truthy 语义
/// 视为未命中,继续回溯),命中即返回
/// `{'anthropic': {'container': {'id': id}}}`,全部未命中返回 `null`。
///
/// 供 `prepareStep` 在多步工具循环里把 code_execution 容器 id 转发给后续
/// 请求(programmatic tool calling 跨请求续用同一容器);签名只收契约
/// 类型,调用方自行从各步结果映射 metadata 列表。用法示例:
///
/// ```dart
/// // (用户侧胶水,ai 包类型)
/// prepareStep: (options) {
///   final providerOptions = forwardAnthropicContainerIdFromLastStep(
///     [for (final step in options.steps) step.providerMetadata],
///   );
///   return providerOptions == null
///       ? null
///       : PrepareStepResult(providerOptions: providerOptions);
/// }
/// ```
///
/// 返回值与调用侧已有 providerOptions(如 `container.skills`)的合并由
/// 核心 `mergeProviderOptions` 深合并保证两者共存;若调用方使用自定义
/// provider key(如 `my-anthropic`),应传入 [providerKey] 或在步级 metadata
/// 中已挂同名 key,以便 `resolveAnthropicProviderOptions` 字段级合并时不
/// 让 custom.container 整段覆盖 canonical 转发的 id。
ProviderOptions? forwardAnthropicContainerIdFromLastStep(
  List<ProviderMetadata?> stepProviderMetadata, {
  String? providerKey,
}) {
  for (var i = stepProviderMetadata.length - 1; i >= 0; i--) {
    final metadata = stepProviderMetadata[i];
    if (metadata == null) {
      continue;
    }
    final container = metadata['anthropic']?['container'];
    if (container is! JsonObject) {
      continue;
    }
    final id = container['id'];
    if (id is String && id.isNotEmpty) {
      final containerEntry = <String, Object?>{
        'container': <String, Object?>{'id': id},
      };
      final result = <String, JsonObject>{
        'anthropic': containerEntry,
      };
      for (final key in metadata.keys) {
        if (key == 'anthropic') {
          continue;
        }
        final customContainer = metadata[key]?['container'];
        if (customContainer is JsonObject && customContainer['id'] == id) {
          result[key] = containerEntry;
        }
      }
      if (providerKey != null &&
          providerKey != 'anthropic' &&
          !result.containsKey(providerKey)) {
        result[providerKey] = containerEntry;
      }
      return result;
    }
  }
  return null;
}
