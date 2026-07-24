import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('current-only notification is unavailable to the minimum API', () {
    final registry = AnalysisServerModelRegistry.instance;

    expect(
      registry.isNotificationAvailable(
        'server.pluginError',
        analysisServerMinimumApiVersion,
      ),
      isFalse,
    );
    expect(
      registry.isNotificationAvailable(
        'server.pluginError',
        analysisServerCurrentApiVersion,
      ),
      isTrue,
    );
  });

  test('Analysis Server enums preserve unknown future values', () {
    final known = AnalysisServerEnumValue.parse(
      'AnalysisService',
      'FOLDING',
    );
    final unknown = AnalysisServerEnumValue.parse(
      'AnalysisService',
      'FUTURE_SERVICE',
    );

    expect(known.isKnown, isTrue);
    expect(unknown.isKnown, isFalse);
    expect(unknown.value, 'FUTURE_SERVICE');
  });
}
