import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('generated Analysis Server union inventory is complete', () {
    final registry = AnalysisServerModelRegistry.instance;

    expect(registry.minimumRequestNames, hasLength(59));
    expect(registry.currentRequestNames, hasLength(59));
    expect(registry.minimumNotificationNames, hasLength(21));
    expect(registry.currentNotificationNames, hasLength(22));
    expect(registry.typeNames, hasLength(55));
    expect(registry.enumNames, hasLength(16));
    expect(
      registry.currentOnlyNotificationNames,
      <String>{'server.pluginError'},
    );
    expect(registry.minimumOnlyNames, isEmpty);
  });
}
