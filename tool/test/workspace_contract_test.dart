import 'dart:io';

import '../src/workspace_contract.dart';

typedef _TestBody = void Function();

const _packageNames = <String, String>{
  'provider': 'pigcode_ai_provider',
  'provider_utils': 'pigcode_ai_provider_utils',
  'ai': 'pigcode_ai',
  'openai': 'pigcode_ai_openai',
  'openai_compatible': 'pigcode_ai_openai_compatible',
  'anthropic': 'pigcode_ai_anthropic',
  'protocol_utils': 'pigcode_ai_protocol_utils',
  'acp': 'pigcode_ai_acp',
  'mcp': 'pigcode_ai_mcp',
  'agent': 'pigcode_ai_agent',
  'agent_kernel': 'pigcode_ai_agent_kernel',
  'agent_io': 'pigcode_ai_agent_io',
  'agent_dart': 'pigcode_ai_agent_dart',
  'lsp': 'pigcode_ai_lsp',
  'dap': 'pigcode_ai_dap',
  'dart': 'pigcode_ai_dart',
};

const _phase2bProtocolPaths = <String>[
  'analysis_options.yaml',
  'compatibility/phase-2b-dart-tooling.json',
  'compatibility/schema/dart-tooling-compatibility.schema.json',
  'compatibility/upstream/phase-2b-tooling-inventory.json',
  'docs/dart-tooling-support.md',
  'tool/check_dart_tooling_compatibility.dart',
  'tool/check_format.dart',
  'tool/src/dart_tooling_compatibility_manifest.dart',
  'tool/test/dart_tooling_compatibility_manifest_test.dart',
  'tool/test/dart_tooling_fixture_coverage_test.dart',
  'tool/src/lsp_inventory.dart',
  'tool/src/dap_inventory.dart',
  'tool/src/dart_tooling_inventory.dart',
  'tool/src/schema/draft_04.dart',
  'tool/src/schema/draft_07.dart',
  'tool/test/lsp_inventory_test.dart',
  'tool/test/dap_inventory_test.dart',
  'tool/test/dart_tooling_inventory_test.dart',
  'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.json',
  'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.schema.json',
  'tool/upstream/protocols/lsp/3.18-b7f5132/metaModel.ts',
  'tool/upstream/protocols/lsp/3.18-b7f5132/License.txt',
  'tool/upstream/protocols/lsp/3.18-b7f5132/License-code.txt',
  'tool/upstream/protocols/dap/v1.71.0/debugAdapterProtocol.json',
  'tool/upstream/protocols/dap/v1.71.0/License.txt',
  'tool/upstream/protocols/dap/v1.71.0/License-code.txt',
  'tool/upstream/protocols/dart/3.6.0/analysis_server/spec_input.html',
  'tool/upstream/protocols/dart/3.6.0/analysis_server/api.html',
  'tool/upstream/protocols/dart/3.6.0/analysis_server/protocol_generated.dart',
  'tool/upstream/protocols/dart/3.6.0/analysis_server/protocol_constants.dart',
  'tool/upstream/protocols/dart/3.6.0/dtd/dtd_protocol.md',
  'tool/upstream/protocols/dart/3.6.0/vm_service/service.md',
  'tool/upstream/protocols/dart/3.6.0/vm_service/vm_service.dart',
  'tool/upstream/protocols/dart/3.6.0/vm_service/service.h',
  'tool/upstream/protocols/dart/3.12.2/analysis_server/spec_input.html',
  'tool/upstream/protocols/dart/3.12.2/analysis_server/api.html',
  'tool/upstream/protocols/dart/3.12.2/analysis_server/protocol_generated.dart',
  'tool/upstream/protocols/dart/3.12.2/analysis_server/protocol_constants.dart',
  'tool/upstream/protocols/dart/3.12.2/dtd/dtd_protocol.md',
  'tool/upstream/protocols/dart/3.12.2/vm_service/service.md',
  'tool/upstream/protocols/dart/3.12.2/vm_service/vm_service.dart',
  'tool/upstream/protocols/dart/3.12.2/vm_service/service.h',
  'tool/upstream/protocols/dart/LICENSE',
  'tool/upstream/protocols/peers/phase-2b-peers.json',
  'packages/lsp/lib/src/codec.dart',
  'packages/lsp/example/portable_client.dart',
  'packages/lsp/lib/src/capabilities.dart',
  'packages/lsp/lib/src/cancellation.dart',
  'packages/lsp/lib/src/client.dart',
  'packages/lsp/lib/src/connection.dart',
  'packages/lsp/lib/src/document.dart',
  'packages/lsp/lib/src/errors.dart',
  'packages/lsp/lib/src/generated/lsp_inventory.g.dart',
  'packages/lsp/lib/src/generated/lsp_proposed_models.g.dart',
  'packages/lsp/lib/src/generated/lsp_stable_models.g.dart',
  'packages/lsp/lib/src/method.dart',
  'packages/lsp/lib/src/models.dart',
  'packages/lsp/lib/src/handlers.dart',
  'packages/lsp/lib/src/proposed.dart',
  'packages/lsp/lib/src/proposals.dart',
  'packages/lsp/lib/src/progress.dart',
  'packages/lsp/lib/src/recording.dart',
  'packages/lsp/lib/src/registration.dart',
  'packages/lsp/lib/src/source.dart',
  'packages/lsp/test/fixtures/golden/stable_messages.json',
  'packages/lsp/test/capability_test.dart',
  'packages/lsp/test/cancellation_test.dart',
  'packages/lsp/test/content_modified_test.dart',
  'packages/lsp/test/document_sync_test.dart',
  'packages/lsp/test/dynamic_registration_test.dart',
  'packages/lsp/test/initialize_test.dart',
  'packages/lsp/test/lifecycle_test.dart',
  'packages/lsp/test/reconnect_test.dart',
  'packages/lsp/test/progress_test.dart',
  'packages/lsp/test/reverse_request_test.dart',
  'packages/lsp/test/apply_edit_proposal_test.dart',
  'packages/lsp/test/chaos_framing_test.dart',
  'packages/lsp/test/record_replay_test.dart',
  'packages/lsp/test/scripted_peer_test.dart',
  'packages/lsp/test/support/scripted_peer.dart',
  'tool/fixtures/lsp_peer.dart',
  'tool/test/lsp_cross_process_test.dart',
  'tool/run_lsp_peer_matrix.dart',
  'tool/run_with_pinned_dart.dart',
  'tool/fixtures/lsp/dart_workspace/lib/main.dart',
  'tool/fixtures/lsp/dart_workspace/pubspec.yaml',
  'tool/fixtures/lsp/typescript/package-lock.json',
  'tool/fixtures/lsp/typescript/package.json',
  'tool/fixtures/lsp/typescript_workspace/index.ts',
  'tool/fixtures/lsp/typescript_workspace/tsconfig.json',
  'tool/src/lsp_peer_harness.dart',
  'tool/src/tooling_peer_cache.dart',
  'tool/src/tooling_process_harness.dart',
  'tool/test/lsp_peer_matrix_test.dart',
  'tool/test/pinned_dart_sdk_gate_test.dart',
  'packages/dap/lib/src/codec.dart',
  'packages/dap/example/portable_client.dart',
  'packages/dap/lib/src/capabilities.dart',
  'packages/dap/lib/src/cancellation.dart',
  'packages/dap/lib/src/client.dart',
  'packages/dap/lib/src/connection.dart',
  'packages/dap/lib/src/debug_state.dart',
  'packages/dap/lib/src/errors.dart',
  'packages/dap/lib/src/events.dart',
  'packages/dap/lib/src/generated/dap_inventory.g.dart',
  'packages/dap/lib/src/generated/dap_models.g.dart',
  'packages/dap/lib/src/method.dart',
  'packages/dap/lib/src/models.dart',
  'packages/dap/lib/src/open_value.dart',
  'packages/dap/lib/src/progress.dart',
  'packages/dap/lib/src/proposals.dart',
  'packages/dap/lib/src/references.dart',
  'packages/dap/lib/src/recording.dart',
  'packages/dap/lib/src/session.dart',
  'packages/dap/lib/src/source.dart',
  'packages/dap/test/fixtures/golden/messages.json',
  'packages/dap/test/capabilities_event_test.dart',
  'packages/dap/test/cancellation_test.dart',
  'packages/dap/test/chaos_framing_test.dart',
  'packages/dap/test/correlation_test.dart',
  'packages/dap/test/debug_state_test.dart',
  'packages/dap/test/initialize_test.dart',
  'packages/dap/test/lifecycle_test.dart',
  'packages/dap/test/progress_test.dart',
  'packages/dap/test/reference_lifetime_test.dart',
  'packages/dap/test/record_replay_test.dart',
  'packages/dap/test/run_in_terminal_proposal_test.dart',
  'packages/dap/test/schema/codec_golden_test.dart',
  'packages/dap/test/schema/invalid_fixture_test.dart',
  'packages/dap/test/schema/inventory_test.dart',
  'packages/dap/test/schema/open_enum_test.dart',
  'packages/dap/test/schema/source_test.dart',
  'packages/dap/test/terminal_race_test.dart',
  'packages/dap/test/start_debugging_proposal_test.dart',
  'packages/dap/test/scripted_peer_test.dart',
  'packages/dap/test/support/scripted_peer.dart',
  'tool/fixtures/dap_peer.dart',
  'tool/test/dap_cross_process_test.dart',
  'tool/run_dap_peer_matrix.dart',
  'tool/fixtures/dap/dart_app/bin/main.dart',
  'tool/fixtures/dap/dart_app/pubspec.yaml',
  'tool/fixtures/dap/javascript_app/main.js',
  'tool/src/dap_peer_harness.dart',
  'tool/test/dap_peer_matrix_test.dart',
  'packages/lsp/test/schema/codec_golden_test.dart',
  'packages/lsp/test/schema/invalid_fixture_test.dart',
  'packages/lsp/test/schema/inventory_test.dart',
  'packages/lsp/test/schema/proposed_boundary_test.dart',
  'packages/lsp/test/schema/source_test.dart',
  'packages/dart/lib/src/common/availability.dart',
  'packages/dart/lib/src/common/diagnostics.dart',
  'packages/dart/lib/src/common/errors.dart',
  'packages/dart/lib/src/common/source_identity.dart',
  'packages/dart/lib/src/analysis_server/capabilities.dart',
  'packages/dart/lib/src/analysis_server/client.dart',
  'packages/dart/lib/src/analysis_server/codec.dart',
  'packages/dart/lib/src/analysis_server/connection.dart',
  'packages/dart/lib/src/analysis_server/generated/inventory.g.dart',
  'packages/dart/lib/src/analysis_server/generated/models.g.dart',
  'packages/dart/lib/src/analysis_server/models.dart',
  'packages/dart/lib/src/analysis_server/proposals.dart',
  'packages/dart/lib/src/analysis_server/version.dart',
  'packages/dart/test/analysis_server/cancellation_test.dart',
  'packages/dart/test/analysis_server/codec_golden_test.dart',
  'packages/dart/test/analysis_server/correlation_test.dart',
  'packages/dart/test/analysis_server/edit_proposal_test.dart',
  'packages/dart/test/analysis_server/inventory_test.dart',
  'packages/dart/test/analysis_server/lifecycle_test.dart',
  'packages/dart/test/analysis_server/notification_test.dart',
  'packages/dart/test/analysis_server/source_test.dart',
  'packages/dart/test/analysis_server/upstream_diff_test.dart',
  'packages/dart/test/analysis_server/version_availability_test.dart',
  'packages/dart/test/entrypoint_boundary_test.dart',
  'packages/dart/test/error_boundary_test.dart',
  'packages/dart/test/source_identity_test.dart',
  'tool/src/analysis_server_codegen.dart',
  'tool/src/dtd_codegen.dart',
  'tool/upstream/protocols/dart/dtd-method-inventory.json',
  'packages/dart/lib/src/dtd/client.dart',
  'packages/dart/lib/src/dtd/codec.dart',
  'packages/dart/lib/src/dtd/connection.dart',
  'packages/dart/lib/src/dtd/file_system.dart',
  'packages/dart/lib/src/dtd/generated/inventory.g.dart',
  'packages/dart/lib/src/dtd/method.dart',
  'packages/dart/lib/src/dtd/models.dart',
  'packages/dart/lib/src/dtd/services.dart',
  'packages/dart/lib/src/dtd/streams.dart',
  'packages/dart/example/tooling_clients.dart',
  'packages/dart/test/dtd/codec_golden_test.dart',
  'packages/dart/test/dtd/dynamic_service_test.dart',
  'packages/dart/test/dtd/file_system_test.dart',
  'packages/dart/test/dtd/inventory_test.dart',
  'packages/dart/test/dtd/no_wire_version_test.dart',
  'packages/dart/test/dtd/reconnect_test.dart',
  'packages/dart/test/dtd/secret_redaction_test.dart',
  'packages/dart/test/dtd/service_lifecycle_test.dart',
  'packages/dart/test/dtd/source_test.dart',
  'packages/dart/test/dtd/stream_test.dart',
  'tool/src/vm_service_codegen.dart',
  'packages/dart/lib/src/vm_service/codec.dart',
  'packages/dart/lib/src/vm_service/capabilities.dart',
  'packages/dart/lib/src/vm_service/client.dart',
  'packages/dart/lib/src/vm_service/connection.dart',
  'packages/dart/lib/src/vm_service/generated/inventory.g.dart',
  'packages/dart/lib/src/vm_service/generated/models.g.dart',
  'packages/dart/lib/src/vm_service/models.dart',
  'packages/dart/lib/src/vm_service/references.dart',
  'packages/dart/lib/src/vm_service/streams.dart',
  'packages/dart/lib/src/vm_service/version.dart',
  'packages/dart/test/vm_service/codec_golden_test.dart',
  'packages/dart/test/vm_service/inventory_test.dart',
  'packages/dart/test/vm_service/lifecycle_test.dart',
  'packages/dart/test/vm_service/reference_lifetime_test.dart',
  'packages/dart/test/vm_service/source_test.dart',
  'packages/dart/test/vm_service/stream_test.dart',
  'packages/dart/test/vm_service/supported_protocols_test.dart',
  'packages/dart/test/vm_service/upstream_version_mismatch_test.dart',
  'packages/dart/test/vm_service/version_availability_test.dart',
  'packages/dart/test/vm_service/version_gate_test.dart',
  'tool/src/analysis_server_peer_harness.dart',
  'tool/run_analysis_server_peer_matrix.dart',
  'tool/fixtures/dart_tooling/analyzer_workspace/analysis_options.yaml',
  'tool/fixtures/dart_tooling/analyzer_workspace/lib/main.dart',
  'tool/fixtures/dart_tooling/analyzer_workspace/pubspec.yaml',
  'tool/test/analysis_server_peer_matrix_test.dart',
  'tool/src/dtd_peer_harness.dart',
  'tool/run_dtd_peer_matrix.dart',
  'tool/fixtures/dart_tooling/dtd_client_fixture.dart',
  'tool/test/dtd_peer_matrix_test.dart',
  'tool/src/vm_service_peer_harness.dart',
  'tool/run_vm_service_peer_matrix.dart',
  'tool/fixtures/dart_tooling/vm_service_app.dart',
  'tool/test/vm_service_peer_matrix_test.dart',
  'tool/run_workspace_tests.dart',
];

void main() {
  final tests = <String, _TestBody>{
    'safe fixture passes': () {
      _withFixture((fixture) {
        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );

        _expect(
          violations.isEmpty,
          'Expected no violations, got ${_describe(violations)}',
        );
      });
    },
    'rejects an unexpected tracked root path': () {
      _withFixture((fixture) {
        fixture.writeTracked('notes.txt', 'private notes\n');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'unexpected_tracked_path',
          messageFragment: 'notes.txt',
        );
      });
    },
    'requires the Phase 1 compatibility tooling': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/fixtures/ai_core_peer.dart');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/fixtures/ai_core_peer.dart',
        );
      });
    },
    'requires the Phase 2a protocol source lock and generator': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/upstream/protocols/sources.json');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/upstream/protocols/sources.json',
        );
      });
    },
    'requires the Phase 3 Agent Store crash matrix': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/run_agent_store_crash_matrix.dart');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/run_agent_store_crash_matrix.dart',
        );
      });
    },
    'requires the Phase 4 sandbox crash matrix': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/run_agent_sandbox_crash_matrix.dart');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/run_agent_sandbox_crash_matrix.dart',
        );
      });
    },
    'requires the Phase 3 security and secret gates': () {
      _withFixture((fixture) {
        fixture.removeTracked('tool/test/agent_kernel_secret_scan_test.dart');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'tool/test/agent_kernel_secret_scan_test.dart',
        );
      });
    },
    'requires the Phase 3 compatibility evidence gate': () {
      _withFixture((fixture) {
        fixture.removeTracked('compatibility/phase-3-kernel-store.json');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'compatibility/phase-3-kernel-store.json',
        );
      });
    },
    'requires the Phase 3 public support matrix and examples': () {
      _withFixture((fixture) {
        fixture.removeTracked('docs/kernel-store-support.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_required_path',
          messageFragment: 'docs/kernel-store-support.md',
        );
      });
    },
    'rejects non-canonical tracked paths before applying the allowlist': () {
      _withFixture((fixture) {
        const unsafePaths = <String>{
          '',
          '/packages/ai/pubspec.yaml',
          'packages/ai/',
          r'packages\ai\pubspec.yaml',
          'packages//ai/pubspec.yaml',
          'packages/./ai/pubspec.yaml',
          'packages/../notes.txt',
          '.github/../notes.txt',
        };
        fixture.trackedPaths.addAll(unsafePaths);

        final unexpectedPathViolations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        ).where((violation) => violation.code == 'unexpected_tracked_path');

        _expect(
          unexpectedPathViolations.length == unsafePaths.length,
          'Expected every non-canonical path to be rejected, got '
          '${unexpectedPathViolations.length} of ${unsafePaths.length}: '
          '${unexpectedPathViolations.map((violation) => violation.message).join('; ')}',
        );
      });
    },
    'does not read an absolute tracked pubspec outside the root': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideManifest = File.fromUri(
          outsideDirectory.uri.resolve('pubspec.yaml'),
        )..writeAsStringSync('''
dependencies:
  local_package:
    path: ../local_package
''');

        _withFixture((fixture) {
          fixture.trackedPaths.add(outsideManifest.absolute.path);

          final violations = validateWorkspace(
            fixture.root,
            fixture.trackedPaths,
          );

          _expect(
            violations.length == 1 &&
                violations.single.code == 'unexpected_tracked_path' &&
                violations.single.message.contains(
                  outsideManifest.absolute.path,
                ),
            'Expected only an unexpected path violation, got '
            '${_describe(violations)}',
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'rejects a required manifest symlink outside the root': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideManifest = File.fromUri(
          outsideDirectory.uri.resolve('pubspec.yaml'),
        )..writeAsStringSync(_packageManifest('pigcode_ai_provider'));

        _withFixture((fixture) {
          const manifestPath = 'packages/provider/pubspec.yaml';
          fixture.replaceWithSymlink(manifestPath, outsideManifest.path);

          _expectViolation(
            validateWorkspace(fixture.root, fixture.trackedPaths),
            code: 'non_regular_tracked_path',
            messageFragment: manifestPath,
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'fails closed when a tracked manifest is not UTF-8': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/provider/pubspec.yaml';
        fixture.writeTrackedBytes(manifestPath, const <int>[0xff]);

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_yaml',
          messageFragment: manifestPath,
        );
      });
    },
    'rejects credential patterns in ordinary tracked files': () {
      _withFixture((fixture) {
        final credentialSamples = <String, String>{
          'private_key': <String>['-----BEGIN ', 'PRIVATE KEY-----'].join(),
          'github_pat': <String>[
            'github',
            '_pat_',
            'aaaaaaaaaaaaaaaaaaaa',
          ].join(),
          'github_token': <String>[
            'gh',
            'p_',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234',
          ].join(),
          'anthropic': <String>[
            'sk',
            '-ant-',
            'abcdefghijklmnopqrst',
          ].join(),
          'openai': <String>[
            'sk',
            '-',
            'abcdefghijklmnopqrstuvwx',
          ].join(),
          'aws': <String>['AK', 'IA', 'ABCDEFGHIJKLMNOP'].join(),
        };

        for (final entry in credentialSamples.entries) {
          fixture.writeTracked(
            'packages/ai/lib/src/${entry.key}.dart',
            "const credential = '${entry.value}';\n",
          );
        }

        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );
        for (final name in credentialSamples.keys) {
          _expectViolation(
            violations,
            code: 'possible_secret',
            messageFragment: 'packages/ai/lib/src/$name.dart',
          );
        }
      });
    },
    'rejects ordinary tracked symlinks without reading targets': () {
      final outsideDirectory = Directory.systemTemp.createTempSync(
        'workspace_contract_outside_',
      );
      try {
        final outsideFile = File.fromUri(
          outsideDirectory.uri.resolve('source.dart'),
        )..writeAsStringSync(
            "const credential = '${<String>[
              'sk',
              '-',
              'abcdefghijklmnopqrstuvwx'
            ].join()}';\n",
          );

        _withFixture((fixture) {
          const sourcePath = 'packages/ai/lib/src/source.dart';
          fixture
            ..writeTracked(sourcePath, 'const safe = true;\n')
            ..replaceWithSymlink(sourcePath, outsideFile.path);

          final violations = validateWorkspace(
            fixture.root,
            fixture.trackedPaths,
          );
          _expectViolation(
            violations,
            code: 'non_regular_tracked_path',
            messageFragment: sourcePath,
          );
          _expect(
            !violations.any(
              (violation) =>
                  violation.code == 'possible_secret' &&
                  violation.message.contains(sourcePath),
            ),
            'Expected the symlink target not to be read, got '
            '${_describe(violations)}',
          );
        });
      } finally {
        outsideDirectory.deleteSync(recursive: true);
      }
    },
    'rejects an ordinary tracked file missing from the worktree': () {
      _withFixture((fixture) {
        const sourcePath = 'packages/ai/lib/src/source.dart';
        fixture
          ..writeTracked(sourcePath, 'const safe = true;\n')
          ..removeFileKeepingTracked(sourcePath);

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_tracked_path',
          messageFragment: sourcePath,
        );
      });
    },
    'reports a missing package directory': () {
      _withFixture((fixture) {
        fixture.removeDirectory('packages/provider');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_directory',
          messageFragment: 'packages/provider',
        );
      });
    },
    'reports an extra package directory': () {
      _withFixture((fixture) {
        fixture.writeTracked('packages/extra/README.md', '# Extra\n');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'unexpected_package_directory',
          messageFragment: 'packages/extra',
        );
      });
    },
    'rejects a wrong package name': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/provider/pubspec.yaml',
          'name: pigcode_ai_provider',
          'name: wrong_name',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_name',
          messageFragment: 'packages/provider/pubspec.yaml',
        );
      });
    },
    'reports a missing package README': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/ai/README.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_readme',
          messageFragment: 'packages/ai/README.md',
        );
      });
    },
    'reports a missing package changelog': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/openai/CHANGELOG.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_changelog',
          messageFragment: 'packages/openai/CHANGELOG.md',
        );
      });
    },
    'requires Agent README after Phase 4 documentation closeout': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/agent/README.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_readme',
          messageFragment: 'packages/agent/README.md',
        );
      });
    },
    'requires Agent Dart changelog after Phase 4 documentation closeout': () {
      _withFixture((fixture) {
        fixture.removeTracked('packages/agent_dart/CHANGELOG.md');

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_changelog',
          messageFragment: 'packages/agent_dart/CHANGELOG.md',
        );
      });
    },
    'reports a missing package barrel': () {
      _withFixture((fixture) {
        fixture.removeTracked(
          'packages/anthropic/lib/pigcode_ai_anthropic.dart',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'missing_package_barrel',
          messageFragment: 'packages/anthropic/lib/pigcode_ai_anthropic.dart',
        );
      });
    },
    'rejects a wrong package repository': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/openai/pubspec.yaml',
          'repository: https://github.com/pigcode/ai',
          'repository: https://example.invalid/ai',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_repository',
          messageFragment: 'packages/openai/pubspec.yaml',
        );
      });
    },
    'rejects a wrong package issue tracker': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/openai_compatible/pubspec.yaml',
          'issue_tracker: https://github.com/pigcode/ai/issues',
          'issue_tracker: https://example.invalid/issues',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_package_issue_tracker',
          messageFragment: 'packages/openai_compatible/pubspec.yaml',
        );
      });
    },
    'rejects wrong root workspace membership': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'pubspec.yaml',
          '  - packages/anthropic\n',
          '',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_workspace_membership',
          messageFragment: 'pubspec.yaml',
        );
      });
    },
    'rejects a path dependency in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/ai/pubspec.yaml',
          '''
dependencies:
  local_package:
    path: ../local_package
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/pubspec.yaml',
        );
      });
    },
    'rejects a git dependency in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/provider_utils/pubspec.yaml',
          '''
dev_dependencies:
  remote_package:
    git:
      url: https://example.invalid/remote.git
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: 'packages/provider_utils/pubspec.yaml',
        );
      });
    },
    'rejects a forbidden internal package dependency': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/protocol_utils/pubspec.yaml',
          '''
dependencies:
  pigcode_ai_mcp: ^0.0.1
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_internal_dependency',
          messageFragment: 'pigcode_ai_protocol_utils -> pigcode_ai_mcp',
        );
      });
    },
    'rejects an internal dependency from the portable agent kernel': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/agent_kernel/pubspec.yaml',
          '''
dependencies:
  pigcode_ai: ^0.0.1
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_internal_dependency',
          messageFragment: 'pigcode_ai_agent_kernel -> pigcode_ai',
        );
      });
    },
    'allows agent IO to depend only on the agent kernel': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/agent_io/pubspec.yaml',
          '  pigcode_ai_agent_kernel: ^0.0.1\n',
          '  pigcode_ai_agent_kernel: ^0.0.1\n'
              '  pigcode_ai_protocol_utils: ^0.0.1\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_internal_dependency',
          messageFragment: 'pigcode_ai_agent_io -> pigcode_ai_protocol_utils',
        );
      });
    },
    'allows portable agent dependencies only on AI and agent kernel': () {
      _withFixture((fixture) {
        for (final dependency in const <String>[
          'pigcode_ai_protocol_utils',
          'pigcode_ai_agent_io',
        ]) {
          fixture.replaceIn(
            'packages/agent/pubspec.yaml',
            '  pigcode_ai: ^0.0.1\n',
            '  pigcode_ai: ^0.0.1\n  $dependency: ^0.0.1\n',
          );
          _expectViolation(
            validateWorkspace(fixture.root, fixture.trackedPaths),
            code: 'forbidden_internal_dependency',
            messageFragment: 'pigcode_ai_agent -> $dependency',
          );
          fixture.replaceIn(
            'packages/agent/pubspec.yaml',
            '  $dependency: ^0.0.1\n',
            '',
          );
        }
      });
    },
    'rejects Flutter dependency from the portable agent': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/agent/pubspec.yaml',
          '  pigcode_ai: ^0.0.1\n',
          '  pigcode_ai: ^0.0.1\n  flutter: any\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_dependency',
          messageFragment: 'pigcode_ai_agent -> flutter',
        );
      });
    },
    'rejects MCP reverse dependency from Dart agent composition': () {
      _withFixture((fixture) {
        fixture.replaceIn(
          'packages/agent_dart/pubspec.yaml',
          '  pigcode_ai_agent: ^0.0.1\n',
          '  pigcode_ai_agent: ^0.0.1\n  pigcode_ai_mcp: ^0.0.1\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_internal_dependency',
          messageFragment: 'pigcode_ai_agent_dart -> pigcode_ai_mcp',
        );
      });
    },
    'allows tooling packages to depend only on protocol utilities': () {
      _withFixture((fixture) {
        for (final package in const <String>['lsp', 'dap', 'dart']) {
          fixture.replaceIn(
            'packages/$package/pubspec.yaml',
            '  pigcode_ai_protocol_utils: ^0.0.1\n',
            '  pigcode_ai_protocol_utils: ^0.0.1\n'
                '  pigcode_ai_provider: ^0.0.1\n',
          );
        }

        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );
        for (final package in const <String>['lsp', 'dap', 'dart']) {
          _expectViolation(
            violations,
            code: 'forbidden_internal_dependency',
            messageFragment: 'pigcode_ai_$package -> pigcode_ai_provider',
          );
        }
      });
    },
    'rejects dart:io in the portable agent kernel barrel': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/agent_kernel/lib/pigcode_ai_agent_kernel.dart',
          "export 'dart:io';\n",
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'portable_barrel_io_dependency',
          messageFragment:
              'packages/agent_kernel/lib/pigcode_ai_agent_kernel.dart',
        );
      });
    },
    'rejects dart:io in the portable agent barrel': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/agent/lib/pigcode_ai_agent.dart',
          "export 'dart:io';\n",
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'portable_barrel_io_dependency',
          messageFragment: 'packages/agent/lib/pigcode_ai_agent.dart',
        );
      });
    },
    'rejects dart:io in a portable protocol barrel': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/mcp/lib/pigcode_ai_mcp.dart',
          "export 'dart:io';\n",
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'portable_barrel_io_dependency',
          messageFragment: 'packages/mcp/lib/pigcode_ai_mcp.dart',
        );
      });
    },
    'rejects re-exporting the MCP IO entrypoint': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/mcp/lib/pigcode_ai_mcp.dart',
          "export 'pigcode_ai_mcp_io.dart';\n",
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'portable_barrel_reexports_io',
          messageFragment: 'packages/mcp/lib/pigcode_ai_mcp.dart',
        );
      });
    },
    'rejects re-exporting LSP proposed APIs from the stable barrel': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/lsp/lib/pigcode_ai_lsp.dart',
          "export 'pigcode_ai_lsp_proposed.dart';\n",
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'forbidden_barrel_export',
          messageFragment: 'pigcode_ai_lsp_proposed.dart',
        );
      });
    },
    'rejects an escaped path source key in a dependency block': () {
      _withFixture((fixture) {
        fixture.appendTo(
          'packages/ai/pubspec.yaml',
          r'''
dependencies:
  local_package:
    "pa\u0074h": ../local_package
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/pubspec.yaml',
        );
      });
    },
    'rejects an escaped git source key in a flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          r'''dependencies: {remote_package: {"g\u0069t": https://example.invalid/remote.git}}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'checks inline sources in every tracked pubspec': () {
      _withFixture((fixture) {
        fixture.writeTracked(
          'packages/ai/example/pubspec.yaml',
          'dependencies: {local_package: {path: ../local_package}}\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: 'packages/ai/example/pubspec.yaml',
        );
      });
    },
    'rejects a path source in a multiline flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  local_package: {
    path: ../local_package
  }
}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'path_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'rejects a git source in a multiline flow mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  remote_package: {
    git: https://example.invalid/remote.git
  }
}
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'git_dependency',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed on an unclosed flow dependency mapping': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies: {
  local_package: {
    hosted: https://example.invalid
''',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_yaml',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed when a dependency section is not a map': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          'dependencies: [local_package]\n',
        );

        _expectViolation(
          validateWorkspace(fixture.root, fixture.trackedPaths),
          code: 'invalid_dependency_section',
          messageFragment: manifestPath,
        );
      });
    },
    'fails closed when a dependency entry is a collection': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          '''
dependencies:
  foo:
    - path: ../local
''',
        );

        final violations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        );
        _expectViolation(
          violations,
          code: 'invalid_dependency_entry',
          messageFragment: manifestPath,
        );
        _expectViolation(
          violations,
          code: 'invalid_dependency_entry',
          messageFragment: 'foo',
        );
      });
    },
    'allows path and git as inline dependency package names': () {
      _withFixture((fixture) {
        const manifestPath = 'packages/ai/example/pubspec.yaml';
        fixture.writeTracked(
          manifestPath,
          'dependencies: {path: ^1.9.0, git: ^2.3.0}\n',
        );

        final sourceViolations = validateWorkspace(
          fixture.root,
          fixture.trackedPaths,
        ).where(
          (violation) =>
              (violation.code == 'path_dependency' ||
                  violation.code == 'git_dependency') &&
              violation.message.contains(manifestPath),
        );

        _expect(
          sourceViolations.isEmpty,
          'Expected legal dependency package names, got '
          '${sourceViolations.map((violation) => violation.message).join('; ')}',
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

void _withFixture(void Function(_WorkspaceFixture fixture) body) {
  final fixture = _WorkspaceFixture.create();
  try {
    body(fixture);
  } finally {
    fixture.dispose();
  }
}

void _expectViolation(
  List<WorkspaceViolation> violations, {
  required String code,
  required String messageFragment,
}) {
  final found = violations.any(
    (violation) =>
        violation.code == code && violation.message.contains(messageFragment),
  );
  _expect(
    found,
    'Expected $code containing "$messageFragment", got '
    '${_describe(violations)}',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

String _describe(List<WorkspaceViolation> violations) => violations
    .map((violation) => '${violation.code}: ${violation.message}')
    .join('; ');

final class _WorkspaceFixture {
  _WorkspaceFixture._(this.root);

  final Directory root;
  final Set<String> trackedPaths = <String>{};

  static _WorkspaceFixture create() {
    final fixture = _WorkspaceFixture._(
      Directory.systemTemp.createTempSync('workspace_contract_test_'),
    );

    fixture
      ..writeTracked('.gitignore', '.dart_tool/\n')
      ..writeTracked('CHANGELOG.md', '# Changelog\n')
      ..writeTracked('LICENSE', 'License text\n')
      ..writeTracked('PHASE4_DEVIATIONS.md', '# Phase 4 deviations\n')
      ..writeTracked('README.md', '# Pigcode AI\n')
      ..writeTracked('THIRD_PARTY_NOTICES.md', '# Third-party notices\n')
      ..writeTracked(
        'compatibility/phase-2a-protocol-foundation.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/schema/ai-core-compatibility.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/schema/protocol-foundation-compatibility.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/upstream/phase-2a-protocol-inventory.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/upstream/vercel-ai-7.0.35-paths.json',
        '{}\n',
      )
      ..writeTracked('compatibility/vercel-ai-7.0.35.json', '{}\n')
      ..writeTracked('docs/protocol-support.md', '# Protocol support\n')
      ..writeTracked(
        'docs/kernel-store-support.md',
        '# Kernel and Store support\n',
      )
      ..writeTracked(
        'docs/native-containment-support.md',
        '# Native containment support\n',
      )
      ..writeTracked('third_party/licenses/Apache-2.0.txt', 'Apache 2.0\n')
      ..writeTracked(
        'tool/check_compatibility.dart',
        '// Compatibility CLI fixture\n',
      )
      ..writeTracked(
        'tool/check_agent_kernel_schema.dart',
        '// Agent Kernel schema CLI fixture\n',
      )
      ..writeTracked(
        'tool/check_kernel_store_compatibility.dart',
        '// Agent Kernel and Store compatibility CLI fixture\n',
      )
      ..writeTracked(
        'tool/check_native_containment_compatibility.dart',
        '// Native containment compatibility CLI fixture\n',
      )
      ..writeTracked(
        'tool/check_native_containment_documentation.dart',
        '// Native containment documentation CLI fixture\n',
      )
      ..writeTracked(
        'tool/run_agent_store_crash_matrix.dart',
        '// Agent Store crash matrix CLI fixture\n',
      )
      ..writeTracked(
        'tool/run_agent_sandbox_crash_matrix.dart',
        '// Agent sandbox crash matrix CLI fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_sandbox_crash_child.dart',
        '// Agent sandbox crash child fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/native_journey_child.dart',
        '// Native journey child fixture\n',
      )
      ..writeTracked(
        'tool/src/agent_sandbox_crash_harness.dart',
        '// Agent sandbox crash harness fixture\n',
      )
      ..writeTracked(
        'tool/test/agent_sandbox_crash_matrix_test.dart',
        '// Agent sandbox crash matrix test fixture\n',
      )
      ..writeTracked(
        'tool/src/native_containment_compatibility_manifest.dart',
        '// Native containment manifest validator fixture\n',
      )
      ..writeTracked(
        'tool/src/native_containment_documentation.dart',
        '// Native containment documentation validator fixture\n',
      )
      ..writeTracked(
        'tool/test/native_containment_compatibility_manifest_test.dart',
        '// Native containment manifest test fixture\n',
      )
      ..writeTracked(
        'tool/test/native_containment_manifest_mutation_test.dart',
        '// Native containment mutation test fixture\n',
      )
      ..writeTracked(
        'tool/test/native_containment_documentation_test.dart',
        '// Native containment documentation test fixture\n',
      )
      ..writeTracked(
        'tool/test/native_journey_crash_restart_test.dart',
        '// Native journey crash/restart fixture\n',
      )
      ..writeTracked(
        'tool/check_protocol_compatibility.dart',
        '// Protocol compatibility CLI fixture\n',
      )
      ..writeTracked('tool/check_workspace.dart', '// CLI fixture\n')
      ..writeTracked('tool/conformance/mcp/package-lock.json', '{}\n')
      ..writeTracked('tool/conformance/mcp/package.json', '{}\n')
      ..writeTracked(
        'tool/protocol_codegen.dart',
        '// Protocol codegen CLI fixture\n',
      )
      ..writeTracked(
        'tool/run_acp_peer_matrix.dart',
        '// ACP peer matrix fixture\n',
      )
      ..writeTracked(
        'tool/run_mcp_conformance.dart',
        '// MCP conformance runner fixture\n',
      )
      ..writeTracked('tool/fixtures/acp_peer.dart', '// ACP peer fixture\n')
      ..writeTracked(
        'tool/fixtures/acp/rust/README.md',
        '# Rust ACP fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/acp/typescript/README.md',
        '# TypeScript ACP fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/acp/typescript/agent.mjs',
        '// TypeScript ACP peer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/acp/typescript/package-lock.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/acp/typescript/package.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/ai_core_peer.dart',
        '// Peer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/anthropic_peer.dart',
        '// Anthropic peer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/mcp_conformance_client.dart',
        '// MCP conformance client fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/mcp_conformance_server.dart',
        '// MCP conformance server fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/mcp_stdio_peer.dart',
        '// MCP stdio peer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/openai_compatible_peer.dart',
        '// OpenAI-compatible peer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/openai_peer.dart',
        '// OpenAI peer fixture\n',
      )
      ..writeTracked(
        'tool/generate_upstream_path_inventory.dart',
        '// Inventory generator fixture\n',
      )
      ..writeTracked(
        'tool/src/acp_peer_harness.dart',
        '// ACP peer harness fixture\n',
      )
      ..writeTracked(
        'tool/src/agent_kernel_schema.dart',
        '// Agent Kernel schema fixture\n',
      )
      ..writeTracked(
        'tool/src/agent_store_crash_harness.dart',
        '// Agent Store crash harness fixture\n',
      )
      ..writeTracked(
        'tool/src/agent_store_writer_fixture.dart',
        '// Agent Store writer fixture\n',
      )
      ..writeTracked(
        'tool/src/compatibility_manifest.dart',
        '// Compatibility contract fixture\n',
      )
      ..writeTracked(
        'tool/src/kernel_store_compatibility_manifest.dart',
        '// Agent Kernel and Store compatibility fixture\n',
      )
      ..writeTracked(
        'tool/src/protocol_compatibility_manifest.dart',
        '// Protocol compatibility contract fixture\n',
      )
      ..writeTracked(
        'tool/src/protocol_codegen.dart',
        '// Protocol codegen fixture\n',
      )
      ..writeTracked(
        'tool/src/protocol_inventory.dart',
        '// Protocol inventory fixture\n',
      )
      ..writeTracked(
        'tool/src/protocol_sources.dart',
        '// Protocol source-lock fixture\n',
      )
      ..writeTracked(
        'tool/src/workspace_contract.dart',
        '// Contract fixture\n',
      )
      ..writeTracked(
        'tool/test/ai_core_peer_test.dart',
        '// Peer test fixture\n',
      )
      ..writeTracked(
        'tool/test/agent_kernel_schema_test.dart',
        '// Agent Kernel schema test fixture\n',
      )
      ..writeTracked(
        'tool/test/agent_kernel_secret_scan_test.dart',
        '// Agent Kernel secret scan fixture\n',
      )
      ..writeTracked(
        'tool/test/agent_store_crash_matrix_test.dart',
        '// Agent Store crash matrix test fixture\n',
      )
      ..writeTracked(
        'tool/test/agent_store_multi_process_test.dart',
        '// Agent Store multi-process test fixture\n',
      )
      ..writeTracked(
        'tool/test/ai_core_cross_process_test.dart',
        '// Cross-process test fixture\n',
      )
      ..writeTracked(
        'tool/test/ai_core_cross_scripted_peer_test.dart',
        '// Cross-package scripted test fixture\n',
      )
      ..writeTracked(
        'tool/test/acp_cross_process_test.dart',
        '// ACP cross-process test fixture\n',
      )
      ..writeTracked(
        'tool/test/compatibility_manifest_test.dart',
        '// Compatibility test fixture\n',
      )
      ..writeTracked(
        'tool/test/kernel_store_compatibility_manifest_test.dart',
        '// Agent Kernel and Store compatibility test fixture\n',
      )
      ..writeTracked(
        'tool/test/kernel_store_fixture_coverage_test.dart',
        '// Agent Kernel and Store fixture coverage fixture\n',
      )
      ..writeTracked(
        'tool/test/mcp_conformance_inventory_test.dart',
        '// MCP conformance inventory test fixture\n',
      )
      ..writeTracked(
        'tool/test/mcp_stdio_cross_process_test.dart',
        '// MCP stdio cross-process test fixture\n',
      )
      ..writeTracked(
        'tool/test/protocol_codegen_test.dart',
        '// Protocol codegen test fixture\n',
      )
      ..writeTracked(
        'tool/test/protocol_compatibility_manifest_test.dart',
        '// Protocol compatibility test fixture\n',
      )
      ..writeTracked(
        'tool/test/protocol_fixture_coverage_test.dart',
        '// Protocol fixture coverage test fixture\n',
      )
      ..writeTracked(
        'tool/test/protocol_inventory_test.dart',
        '// Protocol inventory test fixture\n',
      )
      ..writeTracked(
        'tool/test/protocol_sources_test.dart',
        '// Protocol source test fixture\n',
      )
      ..writeTracked(
        'tool/test/workspace_contract_test.dart',
        '// Test fixture\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/acp/LICENSE',
        'Apache 2.0\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/acp/schema-v1.20.0/meta.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/acp/schema-v1.20.0/schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/mcp-conformance/LICENSE',
        'Mixed license\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/mcp-conformance/v0.1.16/package.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/mcp-conformance/v0.1.16/scenarios.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/mcp/2025-11-25/schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/mcp/LICENSE',
        'MIT\n',
      )
      ..writeTracked(
        'tool/upstream/protocols/sources.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/schema/agent_kernel/agent-event-v1.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/schema/agent_kernel/store-transaction-v1.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/schema/agent_kernel/snapshot-v1.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/schema/agent_kernel/store-manifest-v1.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/schema/agent_kernel/event-inventory-v1.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/phase-3-kernel-store.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/schema/kernel-store-compatibility.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/phase-4-native-containment.json',
        '{}\n',
      )
      ..writeTracked(
        'compatibility/schema/native-containment-compatibility.schema.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_kernel/schema/valid-event.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_kernel/schema/valid-root-manifest.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_kernel/schema/valid-session-manifest.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_kernel/schema/invalid-event-missing-id.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_kernel/schema/invalid-event-version.json',
        '{}\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_store_crash_writer.dart',
        '// Agent Store crash writer fixture\n',
      )
      ..writeTracked(
        'tool/fixtures/agent_store_writer.dart',
        '// Agent Store writer fixture\n',
      )
      ..writeTracked(
        'packages/agent_kernel/test/security/approval_principal_test.dart',
        '// Approval principal security fixture\n',
      )
      ..writeTracked(
        'packages/agent_kernel/test/security/capability_no_escalation_test.dart',
        '// Capability security fixture\n',
      )
      ..writeTracked(
        'packages/agent_kernel/test/security/secret_rejection_test.dart',
        '// Secret rejection fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/test/security/private_root_test.dart',
        '// Private root security fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/test/security/resource_limit_test.dart',
        '// Resource limit security fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/test/security/store_path_test.dart',
        '// Store path security fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/test/security/symlink_test.dart',
        '// Symlink security fixture\n',
      )
      ..writeTracked(
        'packages/agent_kernel/example/session_run.dart',
        '// Agent Kernel example fixture\n',
      )
      ..writeTracked(
        'packages/agent/example/native_agent.dart',
        '// Native Agent example fixture\n',
      )
      ..writeTracked(
        'packages/agent/test/example_compile_test.dart',
        '// Native Agent example test fixture\n',
      )
      ..writeTracked(
        'packages/agent_dart/example/dart_tooling_agent.dart',
        '// Dart tooling Agent example fixture\n',
      )
      ..writeTracked(
        'packages/agent_dart/test/example_compile_test.dart',
        '// Dart tooling Agent example test fixture\n',
      )
      ..writeTracked(
        'packages/agent_kernel/test/example_compile_test.dart',
        '// Agent Kernel example test fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/example/durable_store.dart',
        '// Agent Store example fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/example/sandboxed_process.dart',
        '// Agent sandbox example fixture\n',
      )
      ..writeTracked(
        'packages/agent_io/test/example_compile_test.dart',
        '// Agent Store example test fixture\n',
      )
      ..writeTracked(
        'packages/acp/lib/src/generated/acp_inventory.g.dart',
        '// Generated ACP inventory\n',
      )
      ..writeTracked(
        'packages/acp/example/client_agent.dart',
        '// ACP example\n',
      )
      ..writeTracked(
        'packages/acp/test/example_compile_test.dart',
        '// ACP example compile test\n',
      )
      ..writeTracked(
        'packages/mcp/lib/src/generated/mcp_inventory.g.dart',
        '// Generated MCP inventory\n',
      )
      ..writeTracked(
        'packages/mcp/example/portable_client_server.dart',
        '// MCP portable example\n',
      )
      ..writeTracked(
        'packages/mcp/example/stdio_io.dart',
        '// MCP stdio example\n',
      )
      ..writeTracked(
        'packages/mcp/example/streamable_http_io.dart',
        '// MCP HTTP IO example\n',
      )
      ..writeTracked(
        'packages/mcp/test/example_compile_test.dart',
        '// MCP example compile test\n',
      )
      ..writeTracked(
        'packages/mcp/test/io_example_compile_test.dart',
        '// MCP IO example compile test\n',
      )
      ..writeTracked(
        'packages/protocol_utils/example/json_rpc_peer.dart',
        '// Protocol utilities example\n',
      )
      ..writeTracked(
        'packages/protocol_utils/test/example_compile_test.dart',
        '// Protocol utilities example compile test\n',
      )
      ..writeTracked('.github/workflows/ci.yaml', 'name: CI\n')
      ..writeTracked('pubspec.yaml', _rootManifest());

    for (final path in _phase2bProtocolPaths) {
      fixture.writeTracked(
        path,
        path.endsWith('/pubspec.yaml')
            ? 'name: phase_2b_fixture\n'
                'publish_to: none\n'
                'environment:\n'
                '  sdk: ^3.6.0\n'
            : 'Phase 2b protocol fixture\n',
      );
    }

    for (final entry in _packageNames.entries) {
      final packagePath = 'packages/${entry.key}';
      fixture
        ..writeTracked('$packagePath/README.md', '# ${entry.value}\n')
        ..writeTracked('$packagePath/CHANGELOG.md', '# Changelog\n')
        ..writeTracked(
          '$packagePath/lib/${entry.value}.dart',
          'library;\n',
        )
        ..writeTracked(
          '$packagePath/pubspec.yaml',
          _packageManifest(
            entry.value,
            dependencies: switch (entry.key) {
              'agent_io' => const <String, String>{
                  'pigcode_ai_agent_kernel': '^0.0.1',
                },
              'agent' => const <String, String>{
                  'pigcode_ai_agent_kernel': '^0.0.1',
                  'pigcode_ai': '^0.0.1',
                },
              'agent_dart' => const <String, String>{
                  'pigcode_ai_agent': '^0.0.1',
                  'pigcode_ai_lsp': '^0.0.1',
                  'pigcode_ai_dap': '^0.0.1',
                  'pigcode_ai_dart': '^0.0.1',
                  'pigcode_ai_agent_io': '^0.0.1',
                },
              'lsp' || 'dap' || 'dart' => const <String, String>{
                  'pigcode_ai_protocol_utils': '^0.0.1',
                },
              _ => const <String, String>{},
            },
          ),
        );
    }
    fixture
      ..writeTracked(
        'packages/lsp/lib/pigcode_ai_lsp_proposed.dart',
        'library;\n',
      )
      ..writeTracked(
        'packages/dart/lib/pigcode_ai_dart_analysis_server.dart',
        'library;\n',
      )
      ..writeTracked(
        'packages/dart/lib/pigcode_ai_dart_dtd.dart',
        'library;\n',
      )
      ..writeTracked(
        'packages/dart/lib/pigcode_ai_dart_vm_service.dart',
        'library;\n',
      );

    return fixture;
  }

  void writeTracked(String path, String contents) {
    final file = _file(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    trackedPaths.add(path);
  }

  void writeTrackedBytes(String path, List<int> bytes) {
    final file = _file(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    trackedPaths.add(path);
  }

  void appendTo(String path, String contents) {
    _file(path).writeAsStringSync(contents, mode: FileMode.append);
  }

  void replaceIn(String path, String from, String to) {
    final file = _file(path);
    final contents = file.readAsStringSync();
    _expect(contents.contains(from), 'Fixture text not found in $path: $from');
    file.writeAsStringSync(contents.replaceFirst(from, to));
  }

  void replaceWithSymlink(String path, String target) {
    final file = _file(path);
    file.deleteSync();
    Link(file.path).createSync(target);
  }

  void removeTracked(String path) {
    final file = _file(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
    trackedPaths.remove(path);
  }

  void removeFileKeepingTracked(String path) {
    _file(path).deleteSync();
  }

  void removeDirectory(String path) {
    final directory = _directory(path);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    trackedPaths.removeWhere(
      (trackedPath) => trackedPath == path || trackedPath.startsWith('$path/'),
    );
  }

  void dispose() {
    root.deleteSync(recursive: true);
  }

  File _file(String path) => File.fromUri(root.uri.resolve(path));

  Directory _directory(String path) =>
      Directory.fromUri(root.uri.resolve('$path/'));
}

String _rootManifest() => '''
name: pigcode_ai_workspace
publish_to: none

environment:
  sdk: ^3.6.0

workspace:
  - packages/provider
  - packages/provider_utils
  - packages/ai
  - packages/openai
  - packages/openai_compatible
  - packages/anthropic
  - packages/protocol_utils
  - packages/acp
  - packages/mcp
  - packages/agent
  - packages/agent_kernel
  - packages/agent_io
  - packages/agent_dart
  - packages/lsp
  - packages/dap
  - packages/dart
''';

String _packageManifest(
  String name, {
  Map<String, String> dependencies = const <String, String>{},
}) {
  final dependencyBlock = dependencies.isEmpty
      ? ''
      : '\ndependencies:\n${dependencies.entries.map((entry) => '  ${entry.key}: ${entry.value}').join('\n')}\n';
  return '''
name: $name
version: 0.0.1
publish_to: none

environment:
  sdk: ^3.6.0

resolution: workspace
repository: https://github.com/pigcode/ai
issue_tracker: https://github.com/pigcode/ai/issues
$dependencyBlock''';
}
