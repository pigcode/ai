import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('uploadSkill', () {
    test('passes files and options through to Skills.uploadSkill', () async {
      final records = captureWarningLogs();
      final skills = _RecordingSkills(
        result: const contracts.SkillsUploadResult(
          providerReference: {'mock': 'skill-1'},
          displayTitle: 'Demo skill',
          name: 'demo',
          description: 'A demo skill',
          latestVersion: 'v1',
          warnings: [contracts.OtherWarning('skill note')],
        ),
      );

      final result = await uploadSkill(
        api: skills,
        files: const [
          contracts.SkillFile(
            path: 'SKILL.md',
            data: contracts.FileDataText('# Demo'),
          ),
        ],
        displayTitle: 'Demo skill',
        providerOptions: const {
          'mock': {'visibility': 'private'},
        },
      );

      expect(skills.calls, hasLength(1));
      expect(skills.calls.single.files.single.path, 'SKILL.md');
      expect(
        skills.calls.single.files.single.data,
        const contracts.FileDataText('# Demo'),
      );
      expect(skills.calls.single.displayTitle, 'Demo skill');
      expect(skills.calls.single.providerOptions, {
        'mock': {'visibility': 'private'},
      });
      expect(result.providerReference, {'mock': 'skill-1'});
      expect(result.displayTitle, 'Demo skill');
      expect(result.name, 'demo');
      expect(result.latestVersion, 'v1');
      expect(result.warnings, [const contracts.OtherWarning('skill note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (mock.skills): skill note',
      ]);
    });

    test('resolves Skills from Provider.skills()', () async {
      final skills = _RecordingSkills(
        result: const contracts.SkillsUploadResult(
          providerReference: {'mock': 'skill-1'},
          warnings: [],
        ),
      );
      final provider = _ProviderWithResources(skills: skills);

      await uploadSkill(
        api: provider,
        files: const [
          contracts.SkillFile(
            path: 'SKILL.md',
            data: contracts.FileDataText('# Demo'),
          ),
        ],
      );

      expect(provider.skillsCalls, 1);
      expect(skills.calls, hasLength(1));
    });
  });
}

final class _RecordingSkills implements contracts.Skills {
  _RecordingSkills({required this.result});

  final contracts.SkillsUploadResult result;
  final List<contracts.SkillsUploadOptions> calls = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'mock.skills';

  @override
  Future<contracts.SkillsUploadResult> uploadSkill(
    contracts.SkillsUploadOptions options,
  ) async {
    calls.add(options);
    return result;
  }
}

final class _ProviderWithResources implements contracts.Provider {
  _ProviderWithResources({required contracts.Skills skills}) : _skills = skills;

  final contracts.Skills _skills;
  var skillsCalls = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  contracts.LanguageModel languageModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.EmbeddingModel embeddingModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.ImageModel imageModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.TranscriptionModel transcriptionModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.SpeechModel speechModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.VideoModel videoModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.RerankingModel rerankingModel(String modelId) {
    throw const contracts.UnsupportedFunctionalityError(
      functionality: 'rerankingModel',
    );
  }

  @override
  contracts.Files files() {
    throw const contracts.UnsupportedFunctionalityError(
      functionality: 'files',
    );
  }

  @override
  contracts.Skills skills() {
    skillsCalls += 1;
    return _skills;
  }
}
