import '../common/availability.dart';
import '../common/source_identity.dart';

const analysisServerMinimumApiVersion = AnalysisServerApiVersion(1, 38, 0);
const analysisServerCurrentApiVersion = AnalysisServerApiVersion(1, 40, 1);

final analysisServerVersionPolicy = AnalysisServerVersionPolicy(
  minimum: analysisServerMinimumApiVersion,
  current: analysisServerCurrentApiVersion,
);

const analysisServerMinimumSourceIdentity = AnalysisServerSourceIdentity(
  sourceRelease: '3.6.0',
  sourceRevision: 'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04',
  artifactSha256:
      '839ffd353fe1804add14106d07c62992e1da0153d08ce9bc2ddfda60dd4fdc28',
  apiVersion: analysisServerMinimumApiVersion,
);

const analysisServerCurrentSourceIdentity = AnalysisServerSourceIdentity(
  sourceRelease: '3.12.2',
  sourceRevision: 'd684a576a6aa954ae107a03b2b4e1d61c3bebe93',
  artifactSha256:
      '72931aaae9706d5ba6927ee019f95c8de013eec547ff52463f529153c87c3c22',
  apiVersion: analysisServerCurrentApiVersion,
);
