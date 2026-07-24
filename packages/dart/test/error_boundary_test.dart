import 'package:pigcode_ai_dart/pigcode_ai_dart.dart';
import 'package:test/test.dart';

void main() {
  test('stable tooling error families remain inspectable', () {
    const errors = <DartToolingError>[
      ToolingTransportError('transport_closed', 'Transport closed.'),
      ToolingFramingError('frame_invalid', 'Frame is invalid.'),
      ToolingCodecError('codec_invalid', 'Message is invalid.'),
      ToolingSchemaError('schema_invalid', 'Value is invalid.'),
      ToolingProtocolStateError('state_invalid', 'State is invalid.'),
      ToolingVersionError('version_unsupported', 'Version is unsupported.'),
      ToolingCapabilityError(
        'capability_missing',
        'Capability is unavailable.',
      ),
      ToolingRemoteError(
        'remote_failure',
        'Remote request failed.',
        remoteCode: 'REMOTE',
      ),
      ToolingProposalError('proposal_rejected', 'Proposal was rejected.'),
      ToolingResourceLimitError('limit_exceeded', 'Limit was exceeded.'),
    ];

    expect(
      errors.map((error) => error.family).toSet(),
      ToolingErrorFamily.values.toSet(),
    );
    expect(
        errors.every((error) => !error.toString().contains('REMOTE')), isTrue);
  });

  test('diagnostics redact secrets, environment, content, and large values',
      () {
    const redactor = DartToolingDiagnosticRedactor(
      maxStringLength: 16,
      maxCollectionEntries: 8,
      maxDepth: 3,
    );
    final redacted = redactor.redact(<String, Object?>{
      'safe': 'visible',
      'dtdSecret': 'must-not-leak',
      'environment': <String, Object?>{'API_KEY': 'must-not-leak'},
      'workspaceContent': 'class Secret {}',
      'large': List<String>.filled(64, 'x').join(),
      'values': <Object?>[1, 2, 3, 4, 5, 6, 7, 8, 9],
      'nested': <String, Object?>{
        'one': <String, Object?>{
          'two': <String, Object?>{'three': 'too-deep'},
        },
      },
    });
    final rendered = redacted.toString();

    expect(redacted['safe'], 'visible');
    expect(rendered, isNot(contains('must-not-leak')));
    expect(rendered, isNot(contains('class Secret')));
    expect(rendered, isNot(contains(List<String>.filled(17, 'x').join())));
    expect(
      redacted['values'],
      <Object?>[1, 2, 3, 4, 5, 6, 7, 8, '<truncated:1>'],
    );
    expect(rendered, contains('<max-depth>'));
  });
}
