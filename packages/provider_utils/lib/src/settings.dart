import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

final _trailingSlash = RegExp(r'/$');

/// 去掉 [url] 唯一一个尾部斜杠;`null` 原样返回 `null`。
String? withoutTrailingSlash(String? url) {
  if (url == null) {
    return null;
  }
  return url.replaceFirst(_trailingSlash, '');
}

/// 加载必需的 API key。
///
/// [apiKey] 非空时直接返回;缺失时抛出契约 `LoadApiKeyError`,提示调用方
/// 通过对应构造参数显式传入。不读取环境变量(保持 web/wasm 兼容,调用方
/// 需自行从环境注入)。
String loadApiKey({String? apiKey, required String settingName}) {
  if (apiKey != null) {
    return apiKey;
  }
  throw LoadApiKeyError(
    message:
        '$settingName is missing. Pass it using the corresponding constructor parameter.',
  );
}

/// 加载必需的字符串设置,语义同 [loadApiKey],缺失时抛出契约
/// `LoadSettingError`。
String loadSetting({String? settingValue, required String settingName}) {
  if (settingValue != null) {
    return settingValue;
  }
  throw LoadSettingError(
    message:
        '$settingName is missing. Pass it using the corresponding constructor parameter.',
  );
}

/// 加载可选的字符串设置;缺失时返回 `null`,不抛出。不读取环境变量。
String? loadOptionalSetting({String? settingValue}) {
  return settingValue;
}
