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
  _expect(sourceLock.formatVersion == 1, 'Unexpected source-lock version.');
  _expect(
    sourceLock.generatorIdentity == 'pigcode-protocol-codegen',
    'Unexpected generator identity.',
  );
  _expect(sourceLock.sources.length == 3, 'Expected exactly three sources.');
  _expect(
    _sourceTuples(sourceLock).toString() == _expectedSourceTuples.toString(),
    'Protocol source metadata drifted.\n'
    'Expected: $_expectedSourceTuples\n'
    'Actual: ${_sourceTuples(sourceLock)}',
  );

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

List<String> _sourceTuples(ProtocolSourceLock lock) => <String>[
      for (final source in lock.sources)
        <Object?>[
          source.sourceId,
          source.protocol,
          source.repository,
          source.release,
          source.revision,
          source.releaseDate,
          source.wireVersion,
          source.schemaDialect ?? '',
          source.entryRefs.join(','),
          for (final artifact in source.artifacts)
            '${artifact.artifactId}|${artifact.path}|'
                '${artifact.size}|${artifact.sha256}',
        ].join('::'),
    ];

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

const _expectedSourceTuples = <String>[
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
