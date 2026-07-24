import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('startDebugging only reaches an explicit caller handler', () {
    final dispatcher = DapProposalDispatcher();
    expect(
      () => dispatcher.dispatch(
        'startDebugging',
        const <String, Object?>{
          'configuration': <String, Object?>{'type': 'dart'},
          'request': 'launch',
        },
      ),
      throwsA(isA<DapProposalException>()),
    );

    DapProposal? received;
    dispatcher.register('startDebugging', (proposal) {
      received = proposal;
      return const <String, Object?>{};
    });
    dispatcher.dispatch(
      'startDebugging',
      const <String, Object?>{
        'configuration': <String, Object?>{'type': 'dart'},
        'request': 'launch',
      },
    );
    expect(received, isA<DapStartDebuggingProposal>());
    final start = received! as DapStartDebuggingProposal;
    expect(start.request, 'launch');
    expect(start.configuration, {'type': 'dart'});
  });
}
