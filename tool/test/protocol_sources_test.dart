import 'dart:convert';
import 'dart:io';

import '../src/protocol_sources.dart';

void main() {
  final root = Directory.current;
  final violations = validateProtocolSources(root);
  _expect(
    violations.isEmpty,
    'Expected fixed protocol sources to validate, got '
    '${violations.map((violation) => violation.toString()).join('; ')}',
  );

  final sourceLock = loadProtocolSourceLock(root);
  _expect(sourceLock.formatVersion == 2, 'Unexpected source-lock version.');
  _expect(
    sourceLock.generatorIdentity == 'pigcode-protocol-codegen',
    'Unexpected generator identity.',
  );
  _expect(sourceLock.sources.length == 7, 'Expected exactly seven sources.');
  _expect(
    _sourceTuples(sourceLock.sources.take(3)).toString() ==
        _expectedLegacySourceTuples.toString(),
    'Legacy protocol source metadata drifted.\n'
    'Expected: $_expectedLegacySourceTuples\n'
    'Actual: ${_sourceTuples(sourceLock.sources.take(3))}',
  );
  _expect(
    _phase2bSourceTuples(sourceLock.sources.skip(3)).toString() ==
        _expectedPhase2bSourceTuples.toString(),
    'Phase 2b protocol source metadata drifted.\n'
    'Expected: $_expectedPhase2bSourceTuples\n'
    'Actual: ${_phase2bSourceTuples(sourceLock.sources.skip(3))}',
  );
  _expect(
    sourceLock.peerManifest?.artifactId == 'phase-2b-peers' &&
        sourceLock.peerManifest?.path ==
            'tool/upstream/protocols/peers/phase-2b-peers.json' &&
        sourceLock.peerManifest?.size == 3413 &&
        sourceLock.peerManifest?.sha256 ==
            'cd6c47611c8dee36884f89a0669e42d718a0eb919ae7ba872f254711a5aae881',
    'Phase 2b peer manifest metadata drifted.',
  );

  final sourceLockJson =
      jsonDecode(File(protocolSourceLockPath).readAsStringSync())
          as Map<String, Object?>;
  final legacyJson = Map<String, Object?>.from(sourceLockJson)
    ..['formatVersion'] = 1
    ..remove('peerManifest')
    ..['sources'] =
        (sourceLockJson['sources']! as List<Object?>).take(3).toList();
  final migratedLegacy = parseProtocolSourceLock(jsonEncode(legacyJson));
  _expect(
    migratedLegacy.formatVersion == 1 && migratedLegacy.sources.length == 3,
    'Expected deterministic format-1 source-lock compatibility.',
  );

  _expectViolationFromMutatedSourceLock(
    root,
    sourceLockJson,
    mutate: (document) {
      _source(document, 'dart-3.6.0')['sdkRole'] = 'fallback';
    },
    code: 'invalid_sdk_role',
  );
  _expectViolationFromMutatedSourceLock(
    root,
    sourceLockJson,
    mutate: (document) {
      _source(document, 'lsp-3.18-b7f5132')['schemaDialect'] =
          'https://example.invalid/schema';
    },
    code: 'unsupported_schema_dialect',
  );
  _expectViolationFromMutatedSourceLock(
    root,
    sourceLockJson,
    mutate: (document) {
      final artifacts =
          _source(document, 'dap-v1.71.0')['artifacts']! as List<Object?>;
      (artifacts.first as Map<String, Object?>)['path'] = '../escape.json';
    },
    code: 'invalid_artifact_path',
  );

  final peerManifest = jsonDecode(
    File(
      'tool/upstream/protocols/peers/phase-2b-peers.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final npmPackages = peerManifest['npmPackages']! as List<Object?>;
  (npmPackages.first as Map<String, Object?>)['integrity'] = '';
  final mutatedPeerDirectory = Directory.systemTemp.createTempSync(
    'protocol_peer_mutation_',
  );
  try {
    final mutatedPeer = File.fromUri(
      mutatedPeerDirectory.uri.resolve('phase-2b-peers.json'),
    )..writeAsStringSync(jsonEncode(peerManifest));
    final peerViolations = validateProtocolSources(
      root,
      artifactOverrides: <String, File>{'phase-2b-peers': mutatedPeer},
    );
    _expect(
      peerViolations.any(
        (violation) => violation.code == 'missing_peer_digest',
      ),
      'Expected a missing peer integrity digest to fail closed.',
    );
  } finally {
    mutatedPeerDirectory.deleteSync(recursive: true);
  }

  final schema = File(
    '${root.path}/tool/upstream/protocols/acp/'
    'schema-v1.20.0/schema.json',
  );
  final mutated = File.fromUri(
    Directory.systemTemp
        .createTempSync('protocol_source_mutation_')
        .uri
        .resolve('schema.json'),
  );
  try {
    mutated.writeAsBytesSync(<int>[...schema.readAsBytesSync(), 0x20]);
    final mutationViolations = validateProtocolSources(
      root,
      artifactOverrides: <String, File>{'acp-schema-v1': mutated},
    );
    _expect(
      mutationViolations.any(
        (violation) =>
            violation.code == 'artifact_size_mismatch' ||
            violation.code == 'artifact_hash_mismatch',
      ),
      'Expected a one-byte source mutation to fail closed.',
    );
  } finally {
    mutated.parent.deleteSync(recursive: true);
  }

  stdout.writeln('Protocol source lock validation passed.');
}

List<String> _sourceTuples(Iterable<ProtocolSource> sources) => <String>[
      for (final source in sources)
        <Object?>[
          source.sourceId,
          source.protocol,
          source.repository,
          source.release,
          source.revision,
          source.releaseDate,
          source.wireVersion ?? '',
          source.schemaDialect ?? '',
          source.entryRefs.join(','),
          for (final artifact in source.artifacts)
            '${artifact.artifactId}|${artifact.path}|'
                '${artifact.size}|${artifact.sha256}',
        ].join('::'),
    ];

List<String> _phase2bSourceTuples(Iterable<ProtocolSource> sources) => <String>[
      for (final source in sources)
        <Object?>[
          source.sourceId,
          source.protocol,
          source.repository,
          source.release,
          source.revision,
          source.releaseDate,
          source.wireVersion ?? '',
          source.schemaDialect ?? '',
          source.sdkRole?.name ?? '',
          _sortedEntries(source.componentVersions),
          _sortedEntries(source.componentRevisions),
          source.entryRefs.join(','),
          for (final artifact in source.artifacts)
            '${artifact.artifactId}|${artifact.role?.name ?? ''}|'
                '${artifact.path}|${artifact.size}|${artifact.sha256}',
        ].join('::'),
    ];

String _sortedEntries(Map<String, String> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join(',');
}

Map<String, Object?> _source(
  Map<String, Object?> document,
  String sourceId,
) {
  return (document['sources']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((source) => source['sourceId'] == sourceId);
}

void _expectViolationFromMutatedSourceLock(
  Directory root,
  Map<String, Object?> original, {
  required void Function(Map<String, Object?> document) mutate,
  required String code,
}) {
  final document = jsonDecode(jsonEncode(original)) as Map<String, Object?>;
  mutate(document);
  final directory = Directory.systemTemp.createTempSync(
    'protocol_source_lock_mutation_',
  );
  try {
    final file = File.fromUri(directory.uri.resolve('sources.json'))
      ..writeAsStringSync(jsonEncode(document));
    final violations = validateProtocolSources(
      root,
      sourceLockOverride: file,
    );
    _expect(
      violations.any((violation) => violation.code == code),
      'Expected source-lock mutation to produce $code, got '
      '${violations.map((violation) => violation.toString()).join('; ')}',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

const _expectedLegacySourceTuples = <String>[
  'acp-v1::acp::'
      'https://github.com/agentclientprotocol/agent-client-protocol::'
      'schema-v1.20.0::5e89c71497fe07dd4ae633c181a17224f4a8956d::'
      '2026-07-21::1::https://json-schema.org/draft/2020-12/schema::'
      'Agent,Client,ProtocolLevel::'
      'acp-schema-v1|tool/upstream/protocols/acp/'
      'schema-v1.20.0/schema.json|198609|'
      '92c1dfcda10dd47e99127500a3763da2b471f9ac61e12b9bf0430c32cf953796::'
      'acp-meta-v1|tool/upstream/protocols/acp/'
      'schema-v1.20.0/meta.json|1059|'
      'e0bf36f8123b2544b499174197fdc371ec49a1b4572a35114513d56492741599::'
      'acp-license|tool/upstream/protocols/acp/LICENSE|10782|'
      'f250d08cee4549b22b3b4aaaf3a743473336fd280316df5d0340717e5127a221',
  'mcp-2025-11-25::mcp::'
      'https://github.com/modelcontextprotocol/modelcontextprotocol::'
      '2025-11-25::38c84e9f93ad191d9eb26d92b945d17bd0efcaf3::'
      '2025-11-25::2025-11-25::'
      'https://json-schema.org/draft/2020-12/schema::'
      r'#/$defs/JSONRPCMessage,#/$defs/ClientRequest,#/$defs/ServerRequest,'
      r'#/$defs/ClientNotification,#/$defs/ServerNotification,'
      r'#/$defs/ClientResult,#/$defs/ServerResult::'
      'mcp-schema-2025-11-25|tool/upstream/protocols/mcp/'
      '2025-11-25/schema.json|174246|'
      '1ffe4c5577974012f5fa02af14ea88df4b7146679df1abaaad497c8d9230ca8a::'
      'mcp-license|tool/upstream/protocols/mcp/LICENSE|1095|'
      '346e57dc40801e3d58165e97f64d45b42c4571a68a76ecb10c3c12858acecb3f',
  'mcp-conformance-v0.1.16::mcp::'
      'https://github.com/modelcontextprotocol/conformance::'
      'v0.1.16::21a9a2febd7100d7c17ac1021ee7f2ed9f66a1e0::'
      '2026-03-27::2025-11-25::::::'
      'mcp-conformance-package|tool/upstream/protocols/'
      'mcp-conformance/v0.1.16/package.json|1779|'
      '2d99f94129bcaa84b8613dfd5ac50f1885cd8e01b72965da57e66ea848b4d0ab::'
      'mcp-conformance-scenarios|tool/upstream/protocols/'
      'mcp-conformance/v0.1.16/scenarios.json|1885|'
      'f589ee5e926838cf66ce06330b1baf156062444f9faf99603869a2fea79f1a08::'
      'mcp-conformance-license|tool/upstream/protocols/'
      'mcp-conformance/LICENSE|12227|'
      '0382b0057770ca05e9c350a50aa3b1c1fea84da0bc81d723bf00b9aa841be58a',
];

const _expectedPhase2bSourceTuples = <String>[
  'lsp-3.18-b7f5132::lsp::'
      'https://github.com/microsoft/language-server-protocol::'
      '3.18-audit-snapshot::b7f5132c95261c0898ae5124e7a91707abc48fcd::'
      '2026-07-16::::http://json-schema.org/draft-07/schema#::::::::'
      '#/definitions/MetaModel::'
      'lsp-meta-model|primary|tool/upstream/protocols/lsp/3.18-b7f5132/'
      'metaModel.json|434788|'
      'caae8df639a4248520a3f589fd72945365e9d8ebca5baf564161a515430d9d41::'
      'lsp-meta-model-schema|schema|tool/upstream/protocols/lsp/'
      '3.18-b7f5132/metaModel.schema.json|24466|'
      '0c18a4346b0d4af8f4ed7a168cae995bc8ce9b3df8f9fac93eb541d8acdf2f92::'
      'lsp-meta-model-typescript|generatedComparison|tool/upstream/protocols/'
      'lsp/3.18-b7f5132/metaModel.ts|11901|'
      '34adc4972d75a29af15992a95157add17eb6a4c8820fbc2a47850fb84f3170ae::'
      'lsp-license|license|tool/upstream/protocols/lsp/3.18-b7f5132/'
      'License.txt|18649|'
      '95df2e9564862e51d69683a899b6dcc8218d577057bdf67322880769ff85f29e::'
      'lsp-code-license|license|tool/upstream/protocols/lsp/3.18-b7f5132/'
      'License-code.txt|1072|'
      '18d3bb3458bb9dabcdf5e74dacf256a339b8a6486338ab09a97ba865d3214928',
  'dap-v1.71.0::dap::'
      'https://github.com/microsoft/debug-adapter-protocol::v1.71.0::'
      '51d95ea4e692b34c5d06601bbd1bebc1ff3fbdd4::2026-02-06::1.71.0::'
      'http://json-schema.org/draft-04/schema#::::::::'
      '#/definitions/Request,#/definitions/Response,#/definitions/Event::'
      'dap-schema|schema|tool/upstream/protocols/dap/v1.71.0/'
      'debugAdapterProtocol.json|189493|'
      'ff8ae4c6cfd588a050e9346c35fd104748a27ef4518d1c3268529ca6f8ff5818::'
      'dap-license|license|tool/upstream/protocols/dap/v1.71.0/'
      'License.txt|19078|'
      'e55d617bc6a67d3d224ace6bc227f19067597ad7e2da809c340fd5b404565b52::'
      'dap-code-license|license|tool/upstream/protocols/dap/v1.71.0/'
      'License-code.txt|1073|'
      '646f8936b8ddcd14e13e578ff6857e368780b0d1a4f6066bee89211923a373e2',
  'dart-3.6.0::dart-tooling::https://github.com/dart-lang/sdk::3.6.0::'
      'ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04::2024-12-11::::::minimum::'
      'analysisServerApi=1.38.0,dartSdk=3.6.0,dtdPackage=2.4.1-wip,'
      'vmService=4.16::'
      'devtools=711c998bb532d60c992bf48a780ab5c6595447d9::'
      'analysis-server:spec-input,dtd:protocol-document,vm-service:service::'
      'dart-3.6.0-analysis-spec|primary|tool/upstream/protocols/dart/3.6.0/'
      'analysis_server/spec_input.html|187193|'
      '839ffd353fe1804add14106d07c62992e1da0153d08ce9bc2ddfda60dd4fdc28::'
      'dart-3.6.0-analysis-api|generatedComparison|tool/upstream/protocols/'
      'dart/3.6.0/analysis_server/api.html|263091|'
      '86f11374f8d9b7f6ff673fa16dd9d980b71249c6016b0f67c3c61fe12b041656::'
      'dart-3.6.0-analysis-generated|generatedComparison|'
      'tool/upstream/protocols/dart/3.6.0/analysis_server/'
      'protocol_generated.dart|540505|'
      '4ac436b59b68efe1ed3955205d515d1fdf88973e9317c28309a86e0ef9257579::'
      'dart-3.6.0-analysis-constants|generatedComparison|'
      'tool/upstream/protocols/dart/3.6.0/analysis_server/'
      'protocol_constants.dart|21439|'
      '37463b793c89388a83e0dcbfbb72bd94a1e821d38dc2d6581af0b65a98819cf9::'
      'dart-3.6.0-dtd-protocol|specification|tool/upstream/protocols/dart/'
      '3.6.0/dtd/dtd_protocol.md|22802|'
      '02c73206e28998486a62c3453399ff2bb1aa225be335140241219f66f639529f::'
      'dart-3.6.0-vm-service|primary|tool/upstream/protocols/dart/3.6.0/'
      'vm_service/service.md|148920|'
      'f1582f15a835e52c91b6e906ddc41ceea23d9853435555a9b6e6f9089f1a9d20::'
      'dart-3.6.0-vm-generated|generatedComparison|tool/upstream/protocols/'
      'dart/3.6.0/vm_service/vm_service.dart|275158|'
      'ef1043c8303c7f85fd70cf79bcc16b7fdc2aced48c1e245b6b56a459c3bf1801::'
      'dart-3.6.0-vm-runtime-version|runtimeOracle|tool/upstream/protocols/'
      'dart/3.6.0/vm_service/service.h|11110|'
      '6df702745081d151ca17633c7316cc925d7478237b9ae421b4628609c650afe3::'
      'dart-sdk-license|license|tool/upstream/protocols/dart/LICENSE|1502|'
      '2cfa3ee8e7512e6d44c854b986510810fadc815f93f890373b3a81c1b6ccd256',
  'dart-3.12.2::dart-tooling::https://github.com/dart-lang/sdk::3.12.2::'
      'd684a576a6aa954ae107a03b2b4e1d61c3bebe93::2026-06-09::::::current::'
      'analysisServerApi=1.40.1,dartSdk=3.12.2,dtdPackage=4.0.0,'
      'vmService=4.21::'
      'devtools=fa063f322c03cc7a690d819db124c196a69cff56::'
      'analysis-server:spec-input,dtd:protocol-document,vm-service:service::'
      'dart-3.12.2-analysis-spec|primary|tool/upstream/protocols/dart/'
      '3.12.2/analysis_server/spec_input.html|189530|'
      '72931aaae9706d5ba6927ee019f95c8de013eec547ff52463f529153c87c3c22::'
      'dart-3.12.2-analysis-api|generatedComparison|tool/upstream/protocols/'
      'dart/3.12.2/analysis_server/api.html|270250|'
      'ef6fcfb9d19d127f1e1fddfbbb80172d5a38f05316f1568290e5aa071ee54b01::'
      'dart-3.12.2-analysis-generated|generatedComparison|'
      'tool/upstream/protocols/dart/3.12.2/analysis_server/'
      'protocol_generated.dart|539354|'
      '8fbcc7cd8e92714f82f84208ab9c57f8a24f002490715b0b9c73a611e3c62928::'
      'dart-3.12.2-analysis-constants|generatedComparison|'
      'tool/upstream/protocols/dart/3.12.2/analysis_server/'
      'protocol_constants.dart|20392|'
      '2cab2fc23e19f85b0be2a9396cea5a71c8d413acd9eb3149e30e945e9b66c298::'
      'dart-3.12.2-dtd-protocol|specification|tool/upstream/protocols/dart/'
      '3.12.2/dtd/dtd_protocol.md|22801|'
      'eb97d36feb8e0cb9ed0362775d4f606ea6f8ea982491c19055627253087a0fb2::'
      'dart-3.12.2-vm-service|primary|tool/upstream/protocols/dart/3.12.2/'
      'vm_service/service.md|152166|'
      'cc234c21330e47f467bca9bb3a1d95cda6691ea10fcb22be432235926f5a4e0e::'
      'dart-3.12.2-vm-generated|generatedComparison|tool/upstream/protocols/'
      'dart/3.12.2/vm_service/vm_service.dart|279996|'
      '69fae97213097830b74b8fb8f2bf5c64e1a7ed291533e7225ec6a60fdcc2eb1e::'
      'dart-3.12.2-vm-runtime-version|runtimeOracle|'
      'tool/upstream/protocols/dart/3.12.2/vm_service/service.h|10765|'
      'ccb5d3c10aeab9df1c97b59f02f23afe91a59b63ddf0c114e6e5ca142abc057d',
];
