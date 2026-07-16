import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'default_settings_merge.dart';

/// 为 embedding 模型调用参数补默认 metadata 的中间件。
///
/// 对齐上游当前 `defaultEmbeddingSettingsMiddleware`:调用参数优先于
/// [settings],headers 与 providerOptions 会合并，providerOptions 内的嵌套
/// JSON object 递归合并，数组直接由调用参数替换。
provider.EmbeddingModelMiddleware defaultEmbeddingSettingsMiddleware({
  required DefaultEmbeddingModelSettings settings,
}) {
  return provider.EmbeddingModelMiddleware(
    transformParams: ({
      required provider.EmbeddingModelCallOptions params,
      required provider.EmbeddingModel model,
    }) async {
      return provider.EmbeddingModelCallOptions(
        values: params.values,
        headers: mergeHeaders(settings.headers, params.headers),
        providerOptions: mergeProviderOptionsDeep(
          settings.providerOptions,
          params.providerOptions,
        ),
        cancellation: params.cancellation,
      );
    },
  );
}

/// [defaultEmbeddingSettingsMiddleware] 可补入的 embedding 默认 metadata。
///
/// 上游当前只支持 headers 与 providerOptions,不包含 values 或 cancellation。
final class DefaultEmbeddingModelSettings {
  const DefaultEmbeddingModelSettings({
    this.headers,
    this.providerOptions,
  });

  final provider.Headers? headers;
  final provider.ProviderOptions? providerOptions;
}
