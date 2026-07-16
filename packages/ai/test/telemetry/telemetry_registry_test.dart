import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_registry.dart';
import 'package:test/test.dart';

final class _T with Telemetry {
  _T(this.name);
  final String name;
}

void main() {
  tearDown(clearTelemetryIntegrations);

  test('starts empty', () {
    expect(globalTelemetryIntegrations(), isEmpty);
  });

  test('register appends; multiple registrations accumulate', () {
    final a = _T('a');
    final b = _T('b');
    final c = _T('c');
    registerTelemetry([a, b]);
    expect(globalTelemetryIntegrations(), [a, b]);
    registerTelemetry([c]);
    expect(globalTelemetryIntegrations(), [a, b, c]);
  });

  test('clear empties the registry', () {
    registerTelemetry([_T('a')]);
    clearTelemetryIntegrations();
    expect(globalTelemetryIntegrations(), isEmpty);
  });

  test('returned list is an unmodifiable copy', () {
    registerTelemetry([_T('a')]);
    final view = globalTelemetryIntegrations();
    expect(() => view.add(_T('x')), throwsUnsupportedError);
    // 外部无法通过返回的视图改动内部状态。
    expect(globalTelemetryIntegrations(), hasLength(1));
  });
}
