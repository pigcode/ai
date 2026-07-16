import 'telemetry.dart';

/// 全局注册的 telemetry 集成。库私有可变列表(非 `globalThis` 式全局),
/// 可经 [clearTelemetryIntegrations] 清空以隔离测试。
final List<Telemetry> _integrations = [];

/// 全局注册一个或多个 telemetry 集成。追加语义。
void registerTelemetry(Iterable<Telemetry> integrations) {
  _integrations.addAll(integrations);
}

/// 清空全局注册的集成。
void clearTelemetryIntegrations() {
  _integrations.clear();
}

/// 返回全局注册集成的不可变快照。
List<Telemetry> globalTelemetryIntegrations() {
  return List<Telemetry>.unmodifiable(_integrations);
}
