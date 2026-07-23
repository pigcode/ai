import 'dart:convert';
import 'dart:io';

import '../src/compatibility_manifest.dart';

typedef _TestBody = void Function();

const _targetCommit = '799faf71e05a7d580914ad94d943d28c0400554c';
const _evidenceCommit = phase1EvidenceCommit;
const _peerHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _sources = <String, Map<String, String>>{
  'pigcode_ai_provider': <String, String>{
    'package': '@ai-sdk/provider',
    'packageVersion': '4.0.3',
    'tree': 'e317bb78b50fd0bdd6e0f6968246b3bc20835265',
    'path': 'packages/provider/src/index.ts',
    'directory': 'provider',
  },
  'pigcode_ai_provider_utils': <String, String>{
    'package': '@ai-sdk/provider-utils',
    'packageVersion': '5.0.12',
    'tree': 'b14c493fddd3c9de574e794c5e688f417d55bb9f',
    'path': 'packages/provider-utils/src/index.ts',
    'directory': 'provider_utils',
  },
  'pigcode_ai': <String, String>{
    'package': 'ai',
    'packageVersion': '7.0.35',
    'tree': '4007b95ee6c90a1caa03b5f765886990f8526f38',
    'path': 'packages/ai/src/index.ts',
    'directory': 'ai',
  },
  'pigcode_ai_openai': <String, String>{
    'package': '@ai-sdk/openai',
    'packageVersion': '4.0.18',
    'tree': '2166f24dcc1fc273374bad00c2d8f63910c1a7c7',
    'path': 'packages/openai/src/index.ts',
    'directory': 'openai',
  },
  'pigcode_ai_openai_compatible': <String, String>{
    'package': '@ai-sdk/openai-compatible',
    'packageVersion': '3.0.14',
    'tree': 'daea26741bc9737bd0fe727c48f142b32346c8e8',
    'path': 'packages/openai-compatible/src/index.ts',
    'directory': 'openai_compatible',
  },
  'pigcode_ai_anthropic': <String, String>{
    'package': '@ai-sdk/anthropic',
    'packageVersion': '4.0.18',
    'tree': '67d1d5804f178fb74f8ec7b49d9d82f2ce562f5c',
    'path': 'packages/anthropic/src/index.ts',
    'directory': 'anthropic',
  },
  'workspace': <String, String>{
    'package': 'ai',
    'packageVersion': '7.0.35',
    'tree': '4007b95ee6c90a1caa03b5f765886990f8526f38',
    'path': 'packages/ai/src/index.ts',
    'directory': 'workspace',
  },
};

final _expectedFixtureIds = <String>{
  ..._ids('PROVIDER', 8),
  ..._ids('UTIL', 8),
  ..._ids('CORE', 16),
  ..._ids('OPENAI', 8),
  ..._ids('COMPAT', 4),
  ..._ids('ANTHROPIC', 8),
  ..._ids('CROSS', 5),
};

void main() {
  final tests = <String, _TestBody>{
    'fixed fixture set has exactly the approved 57 IDs': () {
      _expect(
        phase1FixtureIds.length == 57 &&
            phase1FixtureIds.difference(_expectedFixtureIds).isEmpty &&
            _expectedFixtureIds.difference(phase1FixtureIds).isEmpty,
        'Validator fixture IDs differ from the approved 57-ID set.',
      );
    },
    'accepts a complete implemented manifest': () {
      _withFixture((fixture) {
        _expectNoViolations(fixture.validate());
      });
    },
    'repository schema carries the exact fixed fixture enum': () {
      _withFixture((fixture) {
        final repositorySchema = jsonDecode(
          File(
            'compatibility/schema/ai-core-compatibility.schema.json',
          ).readAsStringSync(),
        ) as Map<String, Object?>;
        fixture.schema
          ..clear()
          ..addAll(repositorySchema);
        _expectNoViolations(fixture.validate());
      });
    },
    'repository inventory carries the fixed upstream package trees': () {
      _withFixture((fixture) {
        final repositoryInventory = jsonDecode(
          File(
            'compatibility/upstream/vercel-ai-7.0.35-paths.json',
          ).readAsStringSync(),
        ) as Map<String, Object?>;
        fixture.inventory
          ..clear()
          ..addAll(repositoryInventory);
        _expectNoViolations(fixture.validate());
      });
    },
    'requires the schema enum to equal the Dart fixture set': () {
      _withFixture((fixture) {
        final definitions = fixture.schema[r'$defs'] as Map<String, Object?>;
        final fixtureId = definitions['fixtureId'] as Map<String, Object?>;
        (fixtureId['enum'] as List).remove('P1-CROSS-05');
        _expectViolation(fixture.validate(), 'schema_fixture_set_mismatch');
      });
    },
    'rejects missing extra and duplicate fixture IDs': () {
      _withFixture((fixture) {
        (fixture.claim('P1-CROSS-CLAIM-01')['fixtureIds'] as List)
            .cast<String>()
            .remove('P1-CROSS-05');
        _expectViolation(fixture.validate(), 'manifest_fixture_set_mismatch');
      });
      _withFixture((fixture) {
        (fixture.claim('P1-CROSS-CLAIM-01')['fixtureIds'] as List)
            .cast<String>()
            .add('P1-EXTRA-99');
        _expectViolation(fixture.validate(), 'unknown_fixture_id');
      });
      _withFixture((fixture) {
        final ids = fixture.claim('P1-CORE-CLAIM-01')['fixtureIds'] as List;
        ids.add(ids.first);
        _expectViolation(fixture.validate(), 'duplicate_fixture_id');
      });
    },
    'rejects duplicate claim IDs': () {
      _withFixture((fixture) {
        final claims = fixture.manifest['claims'] as List;
        claims.add(_deepCopy(claims.first));
        _expectViolation(fixture.validate(), 'duplicate_claim_id');
      });
    },
    'pins repository tag commit package version and tree': () {
      const mutations = <String, String>{
        'repository': 'https://example.invalid/vercel-ai',
        'tag': 'main',
        'commit': _evidenceCommit,
        'packageVersion': 'latest',
        'tree': _evidenceCommit,
      };
      for (final entry in mutations.entries) {
        _withFixture((fixture) {
          final source = fixture.claim('P1-OPENAI-CLAIM-01')['source'] as Map;
          source[entry.key] = entry.value;
          _expectViolation(fixture.validate(), 'invalid_source');
        });
      }
    },
    'requires pinned canonical upstream refs with exact coverage': () {
      _withFixture((fixture) {
        final ref = _firstRef(
          fixture.claim('P1-PROVIDER-CLAIM-01'),
          'upstreamRefs',
        );
        ref['commit'] = _evidenceCommit;
        _expectViolation(fixture.validate(), 'invalid_upstream_ref');
      });
      _withFixture((fixture) {
        final ref = _firstRef(
          fixture.claim('P1-UTIL-CLAIM-01'),
          'upstreamRefs',
        );
        ref['path'] = 'https://github.com/vercel/ai/blob/main/index.ts';
        _expectViolation(fixture.validate(), 'invalid_upstream_path');
      });
      _withFixture((fixture) {
        final ref = _firstRef(
          fixture.claim('P1-COMPAT-CLAIM-01'),
          'upstreamRefs',
        );
        ref['path'] = 'packages/openai-compatible/src/typo.ts';
        _expectViolation(fixture.validate(), 'upstream_path_not_in_inventory');
      });
      _withFixture((fixture) {
        final ref = _firstRef(
          fixture.claim('P1-CORE-CLAIM-01'),
          'upstreamRefs',
        );
        (ref['fixtureIds'] as List).removeLast();
        _expectViolation(fixture.validate(), 'upstream_coverage_mismatch');
      });
    },
    'rejects an upstream inventory whose package pin drifts': () {
      _withFixture((fixture) {
        final packages = fixture.inventory['packages'] as List;
        final provider = packages.first as Map<String, Object?>;
        provider['tree'] = _evidenceCommit;
        _expectViolation(fixture.validate(), 'invalid_upstream_inventory');
      });
    },
    'requires existing package-scoped Dart tests and fixture tokens': () {
      _withFixture((fixture) {
        final ref = _firstRef(fixture.claim('P1-OPENAI-CLAIM-01'), 'dartTests');
        ref['path'] = 'tool/test/workspace_contract_test.dart';
        _expectViolation(fixture.validate(), 'invalid_test_path');
      });
      _withFixture((fixture) {
        final ref = _firstRef(fixture.claim('P1-COMPAT-CLAIM-01'), 'dartTests');
        fixture.file(ref['path'] as String).writeAsStringSync('// no IDs\n');
        _expectViolation(fixture.validate(), 'missing_fixture_token');
      });
      _withFixture((fixture) {
        final ref = _firstRef(
          fixture.claim('P1-ANTHROPIC-CLAIM-01'),
          'dartTests',
        );
        fixture.file(ref['path'] as String).deleteSync();
        _expectViolation(fixture.validate(), 'missing_test_path');
      });
    },
    'accepts complete verified evidence': () {
      _withFixture((fixture) {
        fixture.makeVerified();
        _expectNoViolations(fixture.validate());
      });
    },
    'verified claims require both complete peer evidence layers': () {
      _withFixture((fixture) {
        fixture.makeVerified();
        fixture.claim('P1-PROVIDER-CLAIM-01')['scriptedPeerTests'] =
            <Object?>[];
        _expectViolation(fixture.validate(), 'scripted_peer_coverage_mismatch');
      });
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-UTIL-CLAIM-01'),
          'realProcessTests',
        );
        (ref['fixtureIds'] as List).removeLast();
        _expectViolation(fixture.validate(), 'real_process_coverage_mismatch');
      });
    },
    'verified evidence rejects incomplete mutable or missing tuples': () {
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-CORE-CLAIM-01'),
          'realProcessTests',
        );
        ref.remove('platform');
        _expectViolation(fixture.validate(), 'missing_key');
      });
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-OPENAI-CLAIM-01'),
          'realProcessTests',
        );
        ref['version'] = 'latest';
        _expectViolation(fixture.validate(), 'mutable_evidence_version');
      });
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-COMPAT-CLAIM-01'),
          'scriptedPeerTests',
        );
        fixture.file(ref['path'] as String).deleteSync();
        _expectViolation(fixture.validate(), 'missing_test_path');
      });
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-OPENAI-CLAIM-01'),
          'realProcessTests',
        );
        ref['peer'] = 'openai-peer';
        _expectViolation(fixture.validate(), 'invalid_evidence_tuple');
        ref['version'] = 'phase1-openai-peer-v1';
        _expectNoViolations(fixture.validate());
      });
    },
    'evidence tuples require the main-bound implementation commit': () {
      _withFixture((fixture) {
        fixture.makeVerified();
        final ref = _firstRef(
          fixture.claim('P1-CORE-CLAIM-01'),
          'realProcessTests',
        );
        ref['evidenceCommit'] = '1111111111111111111111111111111111111111';
        _expectViolation(fixture.validate(), 'evidence_commit_mismatch');
      });
    },
    'cross fixtures use only the fixed root-test exceptions': () {
      _withFixture((fixture) {
        final ref = _firstRef(fixture.claim('P1-CROSS-CLAIM-01'), 'dartTests');
        ref['path'] = 'tool/test/unapproved_test.dart';
        fixture.write(
          'tool/test/unapproved_test.dart',
          _metadata('unit', _ids('CROSS', 5)),
        );
        _expectViolation(fixture.validate(), 'invalid_test_path');
      });
    },
    'rejects unsupported unknown keys and missing keys': () {
      _withFixture((fixture) {
        fixture.claim('P1-PROVIDER-CLAIM-01')['status'] = 'unsupported';
        _expectViolation(fixture.validate(), 'unsupported_status');
      });
      _withFixture((fixture) {
        fixture.claim('P1-UTIL-CLAIM-01')['surprise'] = true;
        _expectViolation(fixture.validate(), 'unknown_key');
      });
      _withFixture((fixture) {
        fixture.claim('P1-CORE-CLAIM-01').remove('surface');
        _expectViolation(fixture.validate(), 'missing_key');
      });
    },
    'requires the exact four notApplicable records': () {
      _withFixture((fixture) {
        (fixture.manifest['notApplicable'] as List).removeLast();
        _expectViolation(fixture.validate(), 'not_applicable_set_mismatch');
      });
      _withFixture((fixture) {
        final record = (fixture.manifest['notApplicable'] as List).first as Map;
        record['boundary'] = 'node-anything';
        _expectViolation(fixture.validate(), 'invalid_not_applicable');
      });
      _withFixture((fixture) {
        final record = (fixture.manifest['notApplicable'] as List).first as Map;
        record['reason'] = '';
        _expectViolation(fixture.validate(), 'invalid_not_applicable');
      });
      _withFixture((fixture) {
        final record = (fixture.manifest['notApplicable'] as List).first as Map;
        record['upstreamPath'] = 'packages/provider-utils/src/typo.ts';
        _expectViolation(fixture.validate(), 'invalid_not_applicable');
      });
    },
    'fixture coverage scans unit scripted and process sets independently': () {
      _withFixture((fixture) {
        fixture.writeCoverageFiles();
        _expectNoViolations(validateFixtureCoverage(fixture.root));
        fixture.file('tool/test/all_scripted_test.dart').writeAsStringSync(
              _metadata(
                'scripted-peer',
                _expectedFixtureIds.difference(<String>{'P1-CROSS-05'}),
              ),
            );
        _expectViolation(
          validateFixtureCoverage(fixture.root),
          'scripted_peer_fixture_set_mismatch',
        );
      });
    },
  };

  var failures = 0;
  for (final entry in tests.entries) {
    try {
      entry.value();
      stdout.writeln('PASS ${entry.key}');
    } on Object catch (error, stackTrace) {
      failures += 1;
      stderr.writeln('FAIL ${entry.key}: $error');
      stderr.writeln(stackTrace);
    }
  }
  if (failures > 0) {
    stderr.writeln('$failures test(s) failed.');
    exitCode = 1;
  }
}

List<String> _ids(String family, int count) => <String>[
      for (var index = 1; index <= count; index += 1)
        'P1-$family-${index.toString().padLeft(2, '0')}',
    ];

Map<String, Object?> _firstRef(Map<String, Object?> claim, String key) =>
    (claim[key] as List).first as Map<String, Object?>;

Object? _deepCopy(Object? value) => jsonDecode(jsonEncode(value));

void _withFixture(void Function(_ManifestFixture fixture) body) {
  final fixture = _ManifestFixture.create();
  try {
    body(fixture);
  } finally {
    fixture.dispose();
  }
}

void _expectViolation(List<CompatibilityViolation> violations, String code) {
  _expect(
    violations.any((violation) => violation.code == code),
    'Expected $code, got ${violations.join('; ')}',
  );
}

void _expectNoViolations(List<CompatibilityViolation> violations) {
  _expect(
    violations.isEmpty,
    'Expected no violations: ${violations.join('; ')}',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _metadata(String kind, Iterable<String> ids) =>
    ids.map((id) => '// Compatibility fixture ($kind): $id').join('\n');

final class _ManifestFixture {
  _ManifestFixture._(this.root, this.manifest, this.schema, this.inventory);

  final Directory root;
  final Map<String, Object?> manifest;
  final Map<String, Object?> schema;
  final Map<String, Object?> inventory;

  static _ManifestFixture create() {
    final root = Directory.systemTemp.createTempSync(
      'compatibility_manifest_test_',
    );
    final claims = <Object?>[
      _claim(
        'P1-PROVIDER-CLAIM-01',
        'pigcode_ai_provider',
        _ids('PROVIDER', 8),
      ),
      _claim('P1-UTIL-CLAIM-01', 'pigcode_ai_provider_utils', _ids('UTIL', 8)),
      _claim('P1-CORE-CLAIM-01', 'pigcode_ai', _ids('CORE', 16)),
      _claim('P1-OPENAI-CLAIM-01', 'pigcode_ai_openai', _ids('OPENAI', 8)),
      _claim(
        'P1-COMPAT-CLAIM-01',
        'pigcode_ai_openai_compatible',
        _ids('COMPAT', 4),
      ),
      _claim(
        'P1-ANTHROPIC-CLAIM-01',
        'pigcode_ai_anthropic',
        _ids('ANTHROPIC', 8),
      ),
      _claim('P1-CROSS-CLAIM-01', 'workspace', _ids('CROSS', 5)),
    ];
    final fixture = _ManifestFixture._(
      root,
      <String, Object?>{
        'manifestVersion': 1,
        'claims': claims,
        'notApplicable': <Object?>[
          _notApplicable(
            'P1-NA-01',
            'javascript-callable-object',
            'packages/provider-utils/src/schema.ts',
          ),
          _notApplicable(
            'P1-NA-02',
            'node-express-server-response',
            'packages/ai/src/text-stream/pipe-text-stream-to-response.ts',
          ),
          _notApplicable(
            'P1-NA-03',
            'typescript-zod-ecosystem',
            'packages/provider-utils/src/to-json-schema/'
                'zod3-to-json-schema/zod3-to-json-schema.ts',
          ),
          _notApplicable(
            'P1-NA-04',
            'typescript-type-system',
            'packages/ai/src/ui/chat.ts',
          ),
        ],
      },
      _schema(_expectedFixtureIds),
      _inventory(),
    );
    for (final claim in claims.cast<Map<String, Object?>>()) {
      final ref = _firstRef(claim, 'dartTests');
      fixture.write(
        ref['path'] as String,
        _metadata('unit', (ref['fixtureIds'] as List).cast<String>()),
      );
    }
    return fixture;
  }

  Map<String, Object?> claim(String id) => (manifest['claims'] as List)
      .cast<Map<String, Object?>>()
      .singleWhere((claim) => claim['claimId'] == id);

  List<CompatibilityViolation> validate() {
    write(
      'manifest.json',
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    write('schema.json', const JsonEncoder.withIndent('  ').convert(schema));
    write(
      'inventory.json',
      const JsonEncoder.withIndent('  ').convert(inventory),
    );
    return validateCompatibilityManifest(
      root: root,
      manifestFile: file('manifest.json'),
      schemaFile: file('schema.json'),
      inventoryFile: file('inventory.json'),
    );
  }

  void makeVerified() {
    for (final claim
        in (manifest['claims'] as List).cast<Map<String, Object?>>()) {
      claim['status'] = 'verified';
      final ids = (claim['fixtureIds'] as List).cast<String>();
      final package = claim['package'] as String;
      final directory = _sources[package]!['directory']!;
      final scriptedPath = package == 'workspace'
          ? 'tool/test/ai_core_cross_scripted_peer_test.dart'
          : 'packages/$directory/test/compatibility/scripted_peer_test.dart';
      final processPath = package == 'workspace'
          ? 'tool/test/ai_core_cross_process_test.dart'
          : 'packages/$directory/test/compatibility/real_process_test.dart';
      claim['scriptedPeerTests'] = <Object?>[
        _evidenceRef(scriptedPath, ids, scripted: true),
      ];
      claim['realProcessTests'] = <Object?>[
        _evidenceRef(processPath, ids, scripted: false),
      ];
      write(scriptedPath, _metadata('scripted-peer', ids));
      write(processPath, _metadata('real-process', ids));
    }
  }

  void writeCoverageFiles() {
    write(
      'tool/test/all_unit_test.dart',
      _metadata('unit', _expectedFixtureIds),
    );
    write(
      'tool/test/all_scripted_test.dart',
      _metadata('scripted-peer', _expectedFixtureIds),
    );
    write(
      'tool/test/all_process_test.dart',
      _metadata('real-process', _expectedFixtureIds),
    );
  }

  void write(String path, String contents) {
    final target = file(path);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(contents);
  }

  File file(String path) => File.fromUri(root.uri.resolve(path));

  void dispose() => root.deleteSync(recursive: true);
}

Map<String, Object?> _claim(
  String claimId,
  String package,
  List<String> fixtureIds,
) {
  final source = _sources[package]!;
  final directory = source['directory']!;
  final dartPath = package == 'workspace'
      ? 'tool/test/workspace_contract_test.dart'
      : 'packages/$directory/test/compatibility/unit_test.dart';
  return <String, Object?>{
    'claimId': claimId,
    'package': package,
    'surface': claimId.toLowerCase(),
    'status': 'implemented',
    'source': <String, Object?>{
      'repository': 'https://github.com/vercel/ai',
      'tag': 'ai@7.0.35',
      'commit': _targetCommit,
      'package': source['package'],
      'packageVersion': source['packageVersion'],
      'tree': source['tree'],
    },
    'fixtureIds': fixtureIds.toList(),
    'upstreamRefs': <Object?>[
      <String, Object?>{
        'commit': _targetCommit,
        'path': source['path'],
        'fixtureIds': fixtureIds.toList(),
      },
    ],
    'dartTests': <Object?>[
      <String, Object?>{'path': dartPath, 'fixtureIds': fixtureIds.toList()},
    ],
    'scriptedPeerTests': <Object?>[],
    'realProcessTests': <Object?>[],
    'notes': 'Test claim.',
  };
}

Map<String, Object?> _evidenceRef(
  String path,
  List<String> fixtureIds, {
  required bool scripted,
}) =>
    <String, Object?>{
      'path': path,
      'fixtureIds': fixtureIds.toList(),
      'role': 'client',
      'transport': scripted ? 'in-process' : 'stdio',
      'version': scripted ? 'scripted-peer-v1' : 'phase1-ai-core-peer-v1',
      'capabilityProfile': 'phase1-ai-core',
      'platform': 'dart-vm',
      'peer': scripted ? 'scripted-peer' : 'ai-core-peer',
      'peerBinaryHash': _peerHash,
      'dartSdkConstraint': '^3.6.0',
      'evidenceCommit': _evidenceCommit,
    };

Map<String, Object?> _notApplicable(
  String id,
  String boundary,
  String upstreamPath,
) =>
    <String, Object?>{
      'id': id,
      'boundary': boundary,
      'upstreamCommit': _targetCommit,
      'upstreamPath': upstreamPath,
      'reason': 'The boundary exists only in the TypeScript or Node runtime.',
    };

Map<String, Object?> _schema(Iterable<String> fixtureIds) => <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      r'$defs': <String, Object?>{
        'fixtureId': <String, Object?>{
          'type': 'string',
          'enum': fixtureIds.toList()..sort(),
        },
      },
    };

Map<String, Object?> _inventory() => <String, Object?>{
      'inventoryVersion': 1,
      'repository': 'https://github.com/vercel/ai',
      'tag': 'ai@7.0.35',
      'commit': _targetCommit,
      'packages': <Object?>[
        for (final entry in _sources.entries)
          if (entry.key != 'workspace')
            <String, Object?>{
              'dartPackage': entry.key,
              'upstreamPackage': entry.value['package'],
              'packageVersion': entry.value['packageVersion'],
              'tree': entry.value['tree'],
              'root': _upstreamRoot(entry.value['path']!),
              'paths': <String>[
                entry.value['path']!,
                ...?_notApplicablePaths[entry.key],
              ]..sort(),
            },
      ],
    };

const _notApplicablePaths = <String, List<String>>{
  'pigcode_ai_provider_utils': <String>[
    'packages/provider-utils/src/schema.ts',
    'packages/provider-utils/src/to-json-schema/'
        'zod3-to-json-schema/zod3-to-json-schema.ts',
  ],
  'pigcode_ai': <String>[
    'packages/ai/src/text-stream/pipe-text-stream-to-response.ts',
    'packages/ai/src/ui/chat.ts',
  ],
};

String _upstreamRoot(String upstreamPath) =>
    upstreamPath.split('/').take(2).join('/');
