import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('minimum/current name diff is fully classified', () {
    final registry = AnalysisServerModelRegistry.instance;

    expect(registry.minimumOnlyNames, isEmpty);
    expect(
      registry.currentOnlyNotificationNames,
      <String>{'server.pluginError'},
    );
    expect(
      registry.unclassifiedChangedDefinitions,
      isEmpty,
    );
  });
}
