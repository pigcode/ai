import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(String body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

final class _RecordingMultipartClient extends http.BaseClient {
  _RecordingMultipartClient(this.body);

  final String body;
  http.MultipartRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request as http.MultipartRequest;
    return _jsonResponse(body);
  }
}

OpenAiConfig _config(http.Client client, {String providerName = 'openai'}) {
  return OpenAiConfig(
    providerName: providerName,
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
  );
}

String _successBody() {
  return jsonEncode({
    'id': 'skill-abc',
    'name': 'demo',
    'description': 'A demo skill',
    'latest_version': 'v2',
    'default_version': 'v1',
    'created_at': 123,
    'updated_at': 456,
  });
}

void main() {
  group('OpenAiSkills', () {
    test('uploads skill files to /skills', () async {
      final client = _RecordingMultipartClient(_successBody());
      final skills = OpenAiSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: [
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
          displayTitle: 'Demo skill',
        ),
      );

      final request = client.lastRequest!;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.openai.com/v1/skills');
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(request.fields, isEmpty);
      expect(request.files.single.field, 'files[]');
      expect(request.files.single.filename, 'skill/SKILL.md');
      expect(await request.files.single.finalize().toBytes(),
          utf8.encode('# Demo'));

      expect(result.providerReference, {'openai': 'skill-abc'});
      expect(result.name, 'demo');
      expect(result.description, 'A demo skill');
      expect(result.latestVersion, 'v2');
      expect(result.providerMetadata, {
        'openai': {
          'defaultVersion': 'v1',
          'createdAt': 123,
          'updatedAt': 456,
        },
      });
      expect(result.warnings, [const UnsupportedWarning('displayTitle')]);
    });

    test('uses derived provider metadata key for Azure-style names', () async {
      final client = _RecordingMultipartClient(_successBody());
      final skills = OpenAiSkills(
        config: _config(client, providerName: 'azure-openai'),
      );

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: [
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(skills.provider, 'azure-openai.skills');
      expect(result.providerReference, {'azure': 'skill-abc'});
      expect(result.providerMetadata!.containsKey('openai'), isFalse);
      expect(result.providerMetadata!['azure'], isNotNull);
    });
  });
}
