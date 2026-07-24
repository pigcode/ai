import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('Analysis Server source identities remain exact', () {
    expect(analysisServerMinimumApiVersion.toString(), '1.38.0');
    expect(analysisServerCurrentApiVersion.toString(), '1.40.1');
    expect(
      analysisServerMinimumSourceIdentity.sourceRevision,
      'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04',
    );
    expect(
      analysisServerCurrentSourceIdentity.sourceRevision,
      'd684a576a6aa954ae107a03b2b4e1d61c3bebe93',
    );
    expect(
      analysisServerMinimumSourceIdentity.artifactSha256,
      '839ffd353fe1804add14106d07c62992e1da0153d08ce9bc2ddfda60dd4fdc28',
    );
    expect(
      analysisServerCurrentSourceIdentity.artifactSha256,
      '72931aaae9706d5ba6927ee019f95c8de013eec547ff52463f529153c87c3c22',
    );
  });
}
