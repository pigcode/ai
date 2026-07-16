import 'package:pigcode_ai/src/telemetry/telemetry.dart';
import 'package:pigcode_ai/src/telemetry/telemetry_settings.dart';
import 'package:test/test.dart';

final class _NoopTelemetry with Telemetry {}

void main() {
  group('TelemetrySettings', () {
    test('const construction with defaults', () {
      const s = TelemetrySettings();
      expect(s.isEnabled, isNull);
      expect(s.recordInputs, isNull);
      expect(s.recordOutputs, isNull);
      expect(s.functionId, isNull);
      expect(s.includeRuntimeContext, isNull);
      expect(s.includeToolsContext, isNull);
      expect(s.integrations, isEmpty);
    });

    test('holds all fields', () {
      final integration = _NoopTelemetry();
      final s = TelemetrySettings(
        isEnabled: false,
        recordInputs: false,
        recordOutputs: true,
        functionId: 'chatbot',
        includeRuntimeContext: const {'userId': true},
        includeToolsContext: const {
          'search': {'region': true}
        },
        integrations: [integration],
      );
      expect(s.isEnabled, isFalse);
      expect(s.recordInputs, isFalse);
      expect(s.recordOutputs, isTrue);
      expect(s.functionId, 'chatbot');
      expect(s.includeRuntimeContext, {'userId': true});
      expect(s.includeToolsContext, {
        'search': {'region': true}
      });
      expect(s.integrations, [integration]);
    });

    test('value equality compares config scalars, not integrations identity',
        () {
      const a = TelemetrySettings(functionId: 'f', recordInputs: false);
      final b = TelemetrySettings(
        functionId: 'f',
        recordInputs: false,
        integrations: [_NoopTelemetry()],
      );
      // integrations 不纳入值相等,仅比较配置。
      expect(a, equals(b));
    });

    test('differs when a config scalar differs', () {
      const a = TelemetrySettings(functionId: 'a');
      const b = TelemetrySettings(functionId: 'b');
      expect(a, isNot(equals(b)));
    });
  });
}
