import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(
  Object body, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json',
    },
  );
}

http.StreamedResponse _streamErrorResponse(Object error) {
  return http.StreamedResponse(
    Stream<List<int>>.error(error),
    200,
    headers: const <String, String>{
      'content-type': 'application/json',
    },
  );
}

final class _QueuedClient extends http.BaseClient {
  _QueuedClient(
    Iterable<http.StreamedResponse> responses, {
    this.errorAfterResponses,
  }) : responses = Queue<http.StreamedResponse>.of(responses);

  final Queue<http.StreamedResponse> responses;
  final Object? errorAfterResponses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (responses.isNotEmpty) {
      return responses.removeFirst();
    }
    final error = errorAfterResponses;
    if (error is Exception) {
      throw error;
    }
    if (error is Error) {
      throw error;
    }
    throw StateError('No queued response or error.');
  }
}

AnthropicConfig _config(
  http.Client client, {
  String name = 'anthropic.messages',
}) {
  return AnthropicConfig(
    providerName: name,
    baseUrl: 'https://api.anthropic.com/v1',
    headers: () => const <String, String>{
      'x-api-key': 'test-key',
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'custom-beta',
    },
    client: client,
  );
}

void main() {
  group('AnthropicSkills', () {
    test('creates a skill with raw multipart paths and canonical metadata',
        () async {
      const createdAt = '2025-10-02T12:34:56Z';
      const updatedAt = '2025-10-02T12:35:56Z';
      final client = _QueuedClient(
        <http.StreamedResponse>[
          _jsonResponse(<String, Object?>{
            'id': 'skill_abc',
            'type': 'skill',
            'display_title': 'Demo',
            'latest_version': null,
            'source': 'custom',
            'created_at': createdAt,
            'updated_at': updatedAt,
          }),
        ],
        errorAfterResponses: StateError('Unexpected extra request.'),
      );
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          displayTitle: 'Demo',
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
            SkillFile(
              path: 'scripts/run.py',
              data: FileDataText('print(1)'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(1));
      final request = client.requests.single as http.MultipartRequest;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.anthropic.com/v1/skills');
      expect(request.headers['x-api-key'], 'test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      final betaHeaderKeys = request.headers.keys
          .where((header) => header.toLowerCase() == anthropicBetaHeaderName)
          .toList();
      expect(betaHeaderKeys, <String>['anthropic-beta']);
      expect(
        request.headers['anthropic-beta']!.split(',').toSet(),
        <String>{'custom-beta', 'skills-2025-10-02'},
      );
      expect(request.fields, <String, String>{'display_title': 'Demo'});
      expect(
        request.files.map((file) => file.field),
        everyElement('files[]'),
      );
      expect(
        request.files.map((file) => file.filename),
        <String?>['SKILL.md', 'scripts/run.py'],
      );
      expect(
        await request.files[0].finalize().toBytes(),
        utf8.encode('# Demo'),
      );
      expect(
        await request.files[1].finalize().toBytes(),
        utf8.encode('print(1)'),
      );

      expect(skills.provider, 'anthropic.skills');
      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_abc',
      });
      expect(result.displayTitle, 'Demo');
      expect(result.latestVersion, isNull);
      expect(result.providerMetadata, <String, JsonObject>{
        'anthropic': <String, Object?>{
          'source': 'custom',
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        },
      });
      expect(result.warnings, isEmpty);
    });

    test('retrieves latest version metadata and prefers non-null fields',
        () async {
      const createdAt = '2025-10-02T12:34:56Z';
      const updatedAt = '2025-10-02T12:35:56Z';
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': createdAt,
          'updated_at': updatedAt,
          'name': 'create-name',
          'description': 'create-description',
        }),
        _jsonResponse(<String, Object?>{
          'type': 'skill_version',
          'skill_id': 'skill_abc',
          'name': 'version-name',
          'description': null,
        }),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      final request = client.requests[1];
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://api.anthropic.com/v1/skills/skill_abc/versions/100',
      );
      expect(request.headers['x-api-key'], 'test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      final betaHeaderKeys = request.headers.keys
          .where((header) => header.toLowerCase() == anthropicBetaHeaderName)
          .toList();
      expect(betaHeaderKeys, <String>['anthropic-beta']);
      expect(
        request.headers['anthropic-beta']!.split(',').toSet(),
        <String>{'custom-beta', 'skills-2025-10-02'},
      );
      expect(result.name, 'version-name');
      expect(result.description, 'create-description');
      expect(result.latestVersion, '100');
      expect(result.warnings, isEmpty);
    });

    test('resolves headers separately for create and version requests',
        () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
        }),
        _jsonResponse(<String, Object?>{
          'type': 'skill_version',
          'skill_id': 'skill_abc',
          'name': 'version-name',
          'description': 'version-description',
        }),
      ]);
      var headerCalls = 0;
      final skills = AnthropicSkills(
        config: AnthropicConfig(
          providerName: 'anthropic.messages',
          baseUrl: 'https://api.anthropic.com/v1',
          headers: () {
            headerCalls += 1;
            return <String, String>{
              'x-api-key': 'key-$headerCalls',
              'anthropic-version': '2023-06-01',
              'anthropic-beta': 'custom-beta',
            };
          },
          client: client,
        ),
      );

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(headerCalls, 2);
      expect(client.requests, hasLength(2));
      expect(client.requests[0].headers['x-api-key'], 'key-1');
      expect(client.requests[1].headers['x-api-key'], 'key-2');
      expect(result.warnings, isEmpty);
    });

    test('keeps the created skill when latest version HTTP retrieval fails',
        () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
          'name': 'create-name',
        }),
        _jsonResponse(
          <String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'overloaded_error',
              'message': 'try later',
            },
          },
          statusCode: 529,
        ),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_abc',
      });
      expect(result.name, 'create-name');
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('keeps the created skill when latest version transport fails',
        () async {
      final versionUri = Uri.parse(
        'https://api.anthropic.com/v1/skills/skill_abc/versions/100',
      );
      final client = _QueuedClient(
        <http.StreamedResponse>[
          _jsonResponse(<String, Object?>{
            'id': 'skill_abc',
            'type': 'skill',
            'display_title': 'Demo',
            'latest_version': '100',
            'source': 'custom',
            'created_at': '2025-10-02T12:34:56Z',
            'updated_at': '2025-10-02T12:35:56Z',
            'name': 'create-name',
          }),
        ],
        errorAfterResponses: http.ClientException('offline', versionUri),
      );
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      expect(client.requests[1].url, versionUri);
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('keeps the created skill when latest version send times out',
        () async {
      final error = TimeoutException('timed out');
      final client = _QueuedClient(
        <http.StreamedResponse>[
          _jsonResponse(<String, Object?>{
            'id': 'skill_abc',
            'type': 'skill',
            'display_title': 'Demo',
            'latest_version': '100',
            'source': 'custom',
            'created_at': '2025-10-02T12:34:56Z',
            'updated_at': '2025-10-02T12:35:56Z',
            'name': 'create-name',
          }),
        ],
        errorAfterResponses: error,
      );
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_abc',
      });
      expect(result.name, 'create-name');
      expect(result.latestVersion, '100');
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('propagates non-transport latest version send errors', () async {
      final error = StateError('programming error');
      final client = _QueuedClient(
        <http.StreamedResponse>[
          _jsonResponse(<String, Object?>{
            'id': 'skill_abc',
            'type': 'skill',
            'display_title': 'Demo',
            'latest_version': '100',
            'source': 'custom',
            'created_at': '2025-10-02T12:34:56Z',
            'updated_at': '2025-10-02T12:35:56Z',
          }),
        ],
        errorAfterResponses: error,
      );
      final skills = AnthropicSkills(config: _config(client));

      await expectLater(
        skills.uploadSkill(
          const SkillsUploadOptions(
            files: <SkillFile>[
              SkillFile(
                path: 'SKILL.md',
                data: FileDataText('# Demo'),
              ),
            ],
          ),
        ),
        throwsA(same(error)),
      );
      expect(client.requests, hasLength(2));
    });

    test('keeps the created skill when latest version body transport fails',
        () async {
      final versionUri = Uri.parse(
        'https://api.anthropic.com/v1/skills/skill_abc/versions/100',
      );
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
          'name': 'create-name',
        }),
        _streamErrorResponse(
          http.ClientException('body interrupted', versionUri),
        ),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_abc',
      });
      expect(result.name, 'create-name');
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('keeps the created skill when latest version body times out',
        () async {
      final error = TimeoutException('timed out');
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
          'name': 'create-name',
        }),
        _streamErrorResponse(error),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_abc',
      });
      expect(result.name, 'create-name');
      expect(result.latestVersion, '100');
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('propagates non-transport latest version body errors', () async {
      final error = StateError('programming error');
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
        }),
        _streamErrorResponse(error),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      await expectLater(
        skills.uploadSkill(
          const SkillsUploadOptions(
            files: <SkillFile>[
              SkillFile(
                path: 'SKILL.md',
                data: FileDataText('# Demo'),
              ),
            ],
          ),
        ),
        throwsA(same(error)),
      );
    });

    test('keeps the created skill when latest version response is invalid',
        () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': '100',
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
          'name': 'create-name',
        }),
        _jsonResponse(<String, Object?>{'name': 'version-name'}),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(client.requests, hasLength(2));
      expect(result.warnings, const <Warning>[
        OtherWarning(
          'Anthropic skill was created, but its latest version metadata could not be retrieved.',
        ),
      ]);
    });

    test('accepts Vercel-compatible create responses without type', () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_vercel',
          'name': 'demo',
          'description': 'Demo skill',
          'latest_version': null,
          'source': 'custom',
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
        }),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      final request = client.requests.single as http.MultipartRequest;
      expect(request.fields.containsKey('display_title'), isFalse);
      expect(result.displayTitle, isNull);
      expect(result.name, 'demo');
      expect(result.description, 'Demo skill');
      expect(result.latestVersion, isNull);
    });

    test('accepts unknown fields and explicit null optional fields', () async {
      const createdAt = '2025-10-02T12:34:56Z';
      const updatedAt = '2025-10-02T12:35:56Z';
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_nullable',
          'type': 'skill',
          'display_title': null,
          'latest_version': null,
          'source': 'custom',
          'created_at': createdAt,
          'updated_at': updatedAt,
          'name': null,
          'description': null,
          'future_field': <String, Object?>{'ignored': true},
        }),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      final result = await skills.uploadSkill(
        const SkillsUploadOptions(
          files: <SkillFile>[
            SkillFile(
              path: 'SKILL.md',
              data: FileDataText('# Demo'),
            ),
          ],
        ),
      );

      expect(result.providerReference, <String, String>{
        'anthropic': 'skill_nullable',
      });
      expect(result.displayTitle, isNull);
      expect(result.latestVersion, isNull);
      expect(result.name, isNull);
      expect(result.description, isNull);
      expect(result.providerMetadata, <String, JsonObject>{
        'anthropic': <String, Object?>{
          'source': 'custom',
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        },
      });
    });

    test('rejects wrong types for every recognized response field', () async {
      const validResponse = <String, Object?>{
        'id': 'skill_abc',
        'type': 'skill',
        'display_title': 'Demo',
        'latest_version': 'version_1',
        'source': 'custom',
        'created_at': '2025-10-02T12:34:56Z',
        'updated_at': '2025-10-02T12:35:56Z',
        'name': 'demo',
        'description': 'Demo skill',
      };
      const wrongValues = <String, Object?>{
        'id': 1,
        'source': <Object?>[],
        'created_at': 1,
        'updated_at': <Object?>[],
        'type': 1,
        'display_title': <Object?>[],
        'latest_version': 1,
        'name': <Object?>[],
        'description': 1,
      };
      const options = SkillsUploadOptions(
        files: <SkillFile>[
          SkillFile(
            path: 'SKILL.md',
            data: FileDataText('# Demo'),
          ),
        ],
      );

      for (final entry in wrongValues.entries) {
        final client = _QueuedClient(<http.StreamedResponse>[
          _jsonResponse(<String, Object?>{
            ...validResponse,
            entry.key: entry.value,
          }),
        ]);
        final skills = AnthropicSkills(config: _config(client));

        await expectLater(
          skills.uploadSkill(options),
          throwsA(isA<TypeValidationError>()),
          reason: 'field ${entry.key}',
        );
      }
    });

    test('rejects create responses missing required source', () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(<String, Object?>{
          'id': 'skill_abc',
          'type': 'skill',
          'display_title': 'Demo',
          'latest_version': null,
          'created_at': '2025-10-02T12:34:56Z',
          'updated_at': '2025-10-02T12:35:56Z',
        }),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      await expectLater(
        skills.uploadSkill(
          const SkillsUploadOptions(
            files: <SkillFile>[
              SkillFile(
                path: 'SKILL.md',
                data: FileDataText('# Demo'),
              ),
            ],
          ),
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('maps official create errors to ApiCallError', () async {
      final client = _QueuedClient(<http.StreamedResponse>[
        _jsonResponse(
          <String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'invalid_request_error',
              'message': 'invalid skill',
            },
          },
          statusCode: 400,
        ),
      ]);
      final skills = AnthropicSkills(config: _config(client));

      await expectLater(
        skills.uploadSkill(
          const SkillsUploadOptions(
            files: <SkillFile>[
              SkillFile(
                path: 'SKILL.md',
                data: FileDataText('# Demo'),
              ),
            ],
          ),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.message, 'message', 'invalid skill'),
        ),
      );
    });
  });
}
