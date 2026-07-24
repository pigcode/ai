import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('preserves structured argv, cwd, and environment', () {
    final proposal = DapRunInTerminalProposal.fromArguments(
      const <String, Object?>{
        'kind': 'integrated',
        'title': 'Run',
        'cwd': '/workspace',
        'args': <Object?>['dart', 'run', 'main.dart'],
        'env': <String, Object?>{'MODE': 'test', 'REMOVE': null},
      },
    );
    expect(proposal.argv, ['dart', 'run', 'main.dart']);
    expect(proposal.cwd, '/workspace');
    expect(proposal.environment, {'MODE': 'test', 'REMOVE': null});
    expect(proposal.shellCommand, isNull);
  });

  test('rejects NUL and oversized argv without spawning anything', () {
    expect(
      () => DapRunInTerminalProposal.fromArguments(
        const <String, Object?>{
          'cwd': '/workspace',
          'args': <Object?>['bad\u0000arg'],
        },
      ),
      throwsA(isA<DapProposalException>()),
    );
    expect(
      () => DapRunInTerminalProposal.fromArguments(
        <String, Object?>{
          'cwd': '/workspace',
          'args': <Object?>['x' * 65537],
        },
      ),
      throwsA(isA<DapProposalException>()),
    );
  });
}
